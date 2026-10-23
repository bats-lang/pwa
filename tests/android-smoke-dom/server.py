# A stand-in for the WebView's DevTools endpoint, as the forwarded socket shows it
# (bats-lang/pwa#166): GET /json lists a page and a worker, and the page's WebSocket
# answers Runtime.evaluate with a console event first and then the document, split
# in two frames (the second a continuation) of more than 65535 bytes each.
# usage: server.py <portfile> <ok|silent>
#   silent: takes the evaluation and never answers it
import base64, hashlib, json, socketserver, struct, sys, threading

GUID = b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
FILLER = 'x' * 100000
DOCUMENT = '<html><body><div id="bats-root">BATS PWA</div><p>' + FILLER + '</p></body></html>'
mode = sys.argv[2]


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
                 'webSocketDebuggerUrl': 'ws://127.0.0.1:%d/devtools/page/1' % self.server.server_address[1]},
                {'type': 'service_worker', 'url': 'https://localhost/service-worker.js'},
            ]).encode()
            self.wfile.write(b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n'
                             b'Connection: close\r\n\r\n' % len(body) + body)
            return
        accept = base64.b64encode(hashlib.sha1(headers['sec-websocket-key'].encode() + GUID).digest())
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
        assert call['params']['expression'] == 'document.documentElement.outerHTML', call
        if mode == 'silent':
            return
        self.wfile.write(frame(1, True, json.dumps({'method': 'Runtime.executionContextCreated'}).encode()))
        answer = json.dumps({'id': call['id'], 'result': {'result': {'type': 'string', 'value': DOCUMENT}}}).encode()
        half = len(answer) // 2
        self.wfile.write(frame(1, False, answer[:half]) + frame(9, True, b'') + frame(0, True, answer[half:]))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


with Server(('127.0.0.1', 0), Handler) as server:
    with open(sys.argv[1], 'w') as portfile:
        portfile.write(str(server.server_address[1]))
    server.serve_forever()
