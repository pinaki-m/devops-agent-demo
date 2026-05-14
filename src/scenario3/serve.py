"""
Minimal SageMaker-compatible inference server.
Implements the /ping and /invocations endpoints required by SageMaker.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", 8080))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        pass

    def do_GET(self):
        if self.path == "/ping":
            self._respond(200, {"status": "Healthy"})
        else:
            self._respond(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/invocations":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                payload = json.loads(body)
            except Exception:
                payload = body.decode(errors="replace")

            # Demo: echo input with a fake prediction
            result = {"prediction": 0, "score": 0.95, "input": payload}
            self._respond(200, result)
        else:
            self._respond(404, {"error": "not found"})

    def _respond(self, status: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"SageMaker inference server listening on port {PORT}")
    server.serve_forever()
