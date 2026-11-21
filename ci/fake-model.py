#!/usr/bin/env python3
"""A stand-in for the model that speaks HTTP, for comide under nautra (ci/check.sh).

    fake-model.py PORT DIR

An OpenAI-shaped chat-completions endpoint on 127.0.0.1:PORT. Call N writes what it was
sent to DIR/request-N.json (with the Authorization header it came with, as "authorization")
and answers with DIR/reply-N.json ({"content": ..., "reasoning": ...}) as a stream, a
chunk at a time.
"""
import http.server
import json
import sys

port, directory = int(sys.argv[1]), sys.argv[2]
count = 0


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        global count
        count += 1
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        body["authorization"] = self.headers.get("Authorization")
        json.dump(body, open(f"{directory}/request-{count}.json", "w"))
        try:
            reply = json.load(open(f"{directory}/reply-{count}.json"))
        except OSError:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b'{"error": "the stand-in has no such reply"}')
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()

        def send(chunk):
            self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
            self.wfile.flush()

        if reply.get("reasoning"):
            send({"choices": [{"delta": {"reasoning_content": reply["reasoning"]}}]})
        content = reply.get("content", "")
        for i in range(0, len(content), 40):
            send({"choices": [{"delta": {"content": content[i:i + 40]}}]})
        # "tool_calls": [{"name": ..., "arguments": {...}}] in the reply are sent as tool calls.
        calls = reply.get("tool_calls") or []
        for i, call in enumerate(calls):
            send({"choices": [{"delta": {"tool_calls": [{"index": i, "id": f"call-{count}-{i}", "type": "function",
                                                        "function": {"name": call["name"], "arguments": json.dumps(call.get("arguments", {}))}}]}}]})
        send({"choices": [{"delta": {}, "finish_reason": "tool_calls" if calls else "stop"}], "usage": {"prompt_tokens": 1000, "completion_tokens": 100}})
        self.wfile.write(b"data: [DONE]\n\n")

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
