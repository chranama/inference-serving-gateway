#!/usr/bin/env python3
"""Small deterministic mock upstream for local gateway proof runs."""

from __future__ import annotations

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class MockHandler(BaseHTTPRequestHandler):
    server_version = "InferenceGatewayMock/1.0"

    def _write_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        trace_id = self.headers.get("X-Trace-ID", "")
        if trace_id:
            self.send_header("X-Trace-ID", trace_id)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _maybe_sleep(self) -> None:
        if self.headers.get("X-Test-Behavior") == "slow":
            time.sleep(1.0)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/healthz":
            self._write_json(200, {"status": "ok"})
            return

        if self.path == "/readyz":
            self._write_json(200, {"status": "ready"})
            return

        if self.path.startswith("/v1/extract/jobs/"):
            job_id = self.path.rsplit("/", 1)[-1]
            self._write_json(
                200,
                {
                    "job_id": job_id,
                    "status": "succeeded",
                    "trace_id": self.headers.get("X-Trace-ID", ""),
                    "request_id": self.headers.get("X-Request-ID", ""),
                },
            )
            return

        self._write_json(404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        self._maybe_sleep()
        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length).decode("utf-8")

        if self.path == "/v1/extract":
            self._write_json(
                200,
                {
                    "path": self.path,
                    "method": "POST",
                    "body": raw_body,
                    "request_id": self.headers.get("X-Request-ID", ""),
                    "trace_id": self.headers.get("X-Trace-ID", ""),
                },
            )
            return

        if self.path == "/v1/extract/jobs":
            self._write_json(
                202,
                {
                    "job_id": "job-123",
                    "status": "queued",
                    "request_id": self.headers.get("X-Request-ID", ""),
                    "trace_id": self.headers.get("X-Trace-ID", ""),
                },
            )
            return

        self._write_json(404, {"error": "not_found"})

    def log_message(self, fmt: str, *args) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18081)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), MockHandler)
    print(f"mock upstream listening on 127.0.0.1:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()

