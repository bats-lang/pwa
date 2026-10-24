# android-smoke: a stand-in for the WebView's DevTools endpoint (pwa#166)
# GET /json lists a page and a worker, and the page's WebSocket answers
# Runtime.evaluate with a console event first and then the document, split
# in two frames (the second a continuation) of more than 65535 bytes each.
# usage: server.py <portfile> <mode> [<scalefile>]
#   ok: the document for outerHTML; for the font scale probe (pwa#154) a text
#     line 20 px high times the scale in <scalefile> (1.0 when it is not there)
#   silent: takes the evaluation and never answers it
#   silent-probe: answers the document and the page's own "is the text shown"
#     question (pwa#201), never the font scale probe
#   hidden: the text is in the page but the page is not visible
#   textzoom: the probe's line stays 20 px whatever the scale (a shell that
#     set textZoom)
#   wide: the page is wider than the window at a scale above 1
#   outside: the text spans past the window's right edge at a scale above 1
import base64, hashlib, json, re, socketserver, struct, sys, threading

GUID = b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
FILLER = 'x' * 100000
DOCUMENT = '<html><body><div id="bats-root">BATS PWA</div><p>' + FILLER + '</p></body></html>'
mode = sys.argv[2]
scale_file = sys.argv[3] if len(sys.argv) > 3 else None
WINDOW = 412


def current_scale():
    try:
        return float(open(scale_file).read())
    except (OSError, TypeError, ValueError):
        return 1.0


def probe_answer():
    scale = current_scale()
    line = 20 if mode == 'textzoom' else 20 * scale
    right = WINDOW + 30 if mode == 'outside' and scale > 1 else 100 * scale
    scroll = WINDOW + 50 if mode == 'wide' and scale > 1 else WINDOW
    return json.dumps({'line': line, 'left': 8, 'right': right,
                       'width': WINDOW, 'scrollWidth': scroll},
                      separators=(',', ':'))  # as JSON.stringify writes it


def read_exact(rfile, n):
    data = rfile.read(n)
    if len(data) != n:
        raise EOFError
    return data


def frame(opcode, final, payload):
    head = bytes([(0x80 if final else 0) | opcode])
    n = len(payload)
    if n < 126:
        head += bytes([n])
    elif n < 65536:
        head += bytes([126]) + struct.pack('>H', n)
    else:
        head += bytes([127]) + struct.pack('>Q', n)
    return head + payload


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        path = self.rfile.readline().decode().split()[1]
        headers = {}
        while True:
            line = self.rfile.readline().decode().strip()
            if not line:
                break
            name, value = line.split(':', 1)
            headers[name.lower()] = value.strip()
        if path == '/json':
            body = json.dumps([
                {'type': 'page', 'url': 'https://localhost/',
                 'webSocketDebuggerUrl':
                     'ws://127.0.0.1:%d/devtools/page/1' % self.server.server_address[1]},
                {'type': 'service_worker', 'url': 'https://localhost/service-worker.js'},
            ]).encode()
            self.wfile.write(b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
                             b'Content-Length: %d\r\n'
                             b'Connection: close\r\n\r\n' % len(body) + body)
            return
        key = headers['sec-websocket-key'].encode()
        accept = base64.b64encode(hashlib.sha1(key + GUID).digest())
        self.wfile.write(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
                         b'Connection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + b'\r\n\r\n')
        first, second = read_exact(self.rfile, 2)
        assert second & 0x80, 'a client frame is masked'
        n = second & 0x7f
        if n == 126:
            n = struct.unpack('>H', read_exact(self.rfile, 2))[0]
        mask = read_exact(self.rfile, 4)
        data = read_exact(self.rfile, n)
        call = json.loads(bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
        assert call['method'] == 'Runtime.evaluate', call
        expression = call['params']['expression']
        asks_shown = 'visibilityState' in expression
        if mode == 'silent':
            return
        if mode == 'silent-probe' and expression != 'document.documentElement.outerHTML' and not asks_shown:
            return
        if asks_shown:
            # the page's answer to "visible, and this text in it" (pwa#201)
            needle = json.loads(re.search(r'indexOf\((".*")\)', expression).group(1))
            visible_required = 'document.visibilityState === "visible"' in expression
            shown = (mode != 'hidden' or not visible_required) and needle in DOCUMENT
            value = {'result': {'type': 'boolean', 'value': shown}}
            answer = json.dumps({'id': call['id'], 'result': value}).encode()
            self.wfile.write(frame(1, True, answer))
            return
        if expression != 'document.documentElement.outerHTML':
            assert '@TEXT@' not in expression and '})("' in expression, expression
            value = {'result': {'type': 'string', 'value': probe_answer()}}
            answer = json.dumps({'id': call['id'], 'result': value}).encode()
            self.wfile.write(frame(1, True, answer))
            return
        event = json.dumps({'method': 'Runtime.executionContextCreated'}).encode()
        self.wfile.write(frame(1, True, event))
        value = {'result': {'type': 'string', 'value': DOCUMENT}}
        answer = json.dumps({'id': call['id'], 'result': value}).encode()
        half = len(answer) // 2
        self.wfile.write(frame(1, False, answer[:half]) + frame(9, True, b'')
                         + frame(0, True, answer[half:]))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


with Server(('127.0.0.1', 0), Handler) as server:
    with open(sys.argv[1], 'w') as portfile:
        portfile.write(str(server.server_address[1]))
    server.serve_forever()
