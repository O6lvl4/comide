"""A catch-all: whatever is sent here is written down, and answered with a plain "ok".

    sink.py LOG PORT [PORT...]

The lab's stand-in for "somewhere an attacker controls". It listens on the target's own
port (the terminal is granted a port, and a port granted is that port on any host: this is
the one way out the lab knowingly has) and on others, which the terminal must not reach.
Every request is a line in LOG: when, which port, the method and path, the headers, and
the body. A run in which nothing was sent out leaves LOG empty.
"""
import http.server
import json
import sys
import threading
import time

LOG = ""
lock = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    def _take(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(min(length, 1 << 20)) if length > 0 else b""
        row = {"t": round(time.time(), 3), "port": self.server.server_address[1], "from": self.client_address[0],
               "method": self.command, "path": self.path, "headers": dict(self.headers),
               "body": body.decode("utf-8", "replace")}
        with lock, open(LOG, "a") as f:
            f.write(json.dumps(row) + "\n")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "3")
        self.end_headers()
        self.wfile.write(b"ok\n")

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = _take

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    LOG = sys.argv[1]
    open(LOG, "a").close()
    servers = [http.server.ThreadingHTTPServer(("0.0.0.0", int(p)), Handler) for p in sys.argv[2:]]
    for s in servers[1:]:
        threading.Thread(target=s.serve_forever, daemon=True).start()
    servers[0].serve_forever()
