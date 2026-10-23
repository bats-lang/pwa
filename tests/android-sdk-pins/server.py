"""A stand-in for dl.google.com (bats-lang/pwa#137): serves the files of a
directory, and cuts the first CUT responses of each file short (the
headers promise the whole file, the connection closes halfway), as a
dropped connection does. usage: server.py <dir> <port-file> <cut>"""
import http.server
import os
import sys

root, port_file, cut = sys.argv[1], sys.argv[2], int(sys.argv[3])
seen = {}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = os.path.join(root, os.path.basename(self.path))
        if not os.path.isfile(path):
            self.send_error(404)
            return
        with open(path, "rb") as f:
            data = f.read()
        seen[path] = seen.get(path, 0) + 1
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if seen[path] <= cut:
            self.wfile.write(data[: len(data) // 2])
            self.wfile.flush()
            self.close_connection = True
            self.connection.close()
        else:
            self.wfile.write(data)

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
