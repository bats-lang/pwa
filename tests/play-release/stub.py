"""A stand-in for the Play Developer API's edits, for run.sh: it answers
as Play does (an edit's id, a bundle's version code) and writes each
request it gets, one JSON line each, to the log it is given. A path that
ends in one of the failing suffixes is answered 400, as Play answers a
refused request.

A failing suffix is a path suffix, or METHOD:suffix for one method only.
The codes Play already holds come from the environment, comma separated:
STUB_TRACK_CODES (the track's releases, as strings, as Play writes them),
STUB_BUNDLE_CODES (the edit's bundles, as numbers) and STUB_UPLOAD_CODE
(the version code of the bundle uploaded; 4242 by default).

usage: python3 stub.py <port-file> <log> [<failing suffix>...]"""
import base64
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port_file, log, failing = sys.argv[1], sys.argv[2], sys.argv[3:]


def codes(name):
    return [code for code in os.environ.get(name, "").split(",") if code]


track_codes = codes("STUB_TRACK_CODES")
bundle_codes = codes("STUB_BUNDLE_CODES")
upload_code = int(os.environ.get("STUB_UPLOAD_CODE", "4242"))


class Play(BaseHTTPRequestHandler):
    def answer(self):
        size = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(size)
        with open(log, "a") as out:
            out.write(json.dumps({
                "method": self.command,
                "path": self.path,
                "authorization": self.headers.get("Authorization"),
                "type": self.headers.get("Content-Type"),
                "body": base64.b64encode(body).decode(),
            }) + "\n")
        path = self.path.split("?")[0]
        if any(path.endswith(suffix.split(":", 1)[-1]) and
               (":" not in suffix or suffix.split(":", 1)[0] == self.command)
               for suffix in failing):
            self.reply(400, {"error": {"code": 400, "message": "refused by the stub"}})
        elif self.command == "POST" and path.endswith("/edits"):
            self.reply(200, {"id": "edit-1", "expiryTimeSeconds": "1"})
        elif self.command == "GET" and "/tracks/" in path:
            releases = [{"versionCodes": track_codes, "status": "completed"}] if track_codes else []
            self.reply(200, {"track": path.rsplit("/", 1)[1], "releases": releases})
        elif self.command == "GET" and path.endswith("/bundles"):
            self.reply(200, {"bundles": [{"versionCode": int(code), "sha256": "x"} for code in bundle_codes]})
        elif path.endswith("/bundles"):
            self.reply(200, {"versionCode": upload_code, "sha256": "x"})
        elif self.command == "DELETE":
            self.reply(204, None)
        else:
            self.reply(200, {"id": "edit-1"})

    def reply(self, code, value):
        data = b"" if value is None else json.dumps(value).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_DELETE = answer

    def log_message(self, *args):
        pass


server = HTTPServer(("127.0.0.1", 0), Play)
with open(port_file + ".tmp", "w") as out:
    out.write(str(server.server_port))
os.replace(port_file + ".tmp", port_file)
server.serve_forever()
