"""A harmless target: the files of one directory over HTTP, and a line for every request.

    target.py PORT DIR LOG

What the lab's terminal sent it is in LOG, one JSON object a line, so a run's record says
what reached the target as well as what the terminal typed.
"""
import functools
import http.server
import json
import sys
import time


class Handler(http.server.SimpleHTTPRequestHandler):
    log_path = ""

    def log_message(self, fmt, *args):
        with open(self.log_path, "a") as f:
            f.write(json.dumps({"t": round(time.time(), 3), "from": self.client_address[0],
                                "line": fmt % args}) + "\n")


if __name__ == "__main__":
    port, directory, Handler.log_path = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    open(Handler.log_path, "a").close()
    handler = functools.partial(Handler, directory=directory)
    http.server.ThreadingHTTPServer(("0.0.0.0", port), handler).serve_forever()
