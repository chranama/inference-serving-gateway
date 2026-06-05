#!/usr/bin/env python3
"""Capture gateway behavior against the deterministic mock upstream."""

from __future__ import annotations

import argparse
import json
import traceback
import sys
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


EXTRACT_PAYLOAD = '{"schema_id":"demo_schema_v1","text":"Vendor: ACME\\nTotal: 10.00"}'


@dataclass
class CapturedResponse:
    name: str
    status: int
    headers: dict[str, str]
    body: str
    body_path: str
    headers_path: str
    status_path: str
    json_body: Any | None


class Probe:
    def __init__(self, gateway_url: str, artifact_dir: Path) -> None:
        self.gateway_url = gateway_url.rstrip("/")
        self.artifact_dir = artifact_dir
        self.responses: dict[str, CapturedResponse] = {}
        self.checks: dict[str, bool] = {}
        self.artifacts: dict[str, str] = {}

    def request(
        self,
        name: str,
        method: str,
        path: str,
        *,
        body: str | None = None,
        headers: dict[str, str] | None = None,
        timeout: float = 10.0,
    ) -> CapturedResponse:
        url = f"{self.gateway_url}{path}"
        data = body.encode("utf-8") if body is not None else None
        request = urllib.request.Request(url, data=data, headers=headers or {}, method=method)

        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                status = response.status
                response_headers = dict(response.headers.items())
                response_body = response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            status = error.code
            response_headers = dict(error.headers.items())
            response_body = error.read().decode("utf-8")
        except urllib.error.URLError as error:
            status = 0
            response_headers = {}
            response_body = str(error)
        except Exception as error:  # pragma: no cover - defensive for live port-forward probes.
            status = 0
            response_headers = {}
            response_body = "".join(traceback.format_exception_only(type(error), error)).strip()

        json_body = parse_json(response_body)
        suffix = "json" if json_body is not None else "txt"
        status_path = f"{name}.status"
        headers_path = f"{name}.headers"
        body_path = f"{name}.body.{suffix}"

        (self.artifact_dir / status_path).write_text(f"{status}\n")
        (self.artifact_dir / headers_path).write_text(format_headers(response_headers))
        (self.artifact_dir / body_path).write_text(response_body)
        if response_body and not response_body.endswith("\n"):
            with (self.artifact_dir / body_path).open("a") as out:
                out.write("\n")

        captured = CapturedResponse(
            name=name,
            status=status,
            headers=lower_headers(response_headers),
            body=response_body,
            body_path=body_path,
            headers_path=headers_path,
            status_path=status_path,
            json_body=json_body,
        )
        self.responses[name] = captured
        self.artifacts[f"{name}_status"] = status_path
        self.artifacts[f"{name}_headers"] = headers_path
        self.artifacts[f"{name}_body"] = body_path
        return captured

    def add_check(self, name: str, value: bool) -> None:
        self.checks[name] = bool(value)

    def scenario_base(self) -> None:
        healthz = self.request("healthz", "GET", "/healthz")
        readyz = self.request("readyz", "GET", "/readyz")
        metrics = self.request("metrics", "GET", "/metrics")

        generated = self.request(
            "extract_generated",
            "POST",
            "/v1/extract",
            body=EXTRACT_PAYLOAD,
            headers={"Content-Type": "application/json"},
        )
        provided = self.request(
            "extract_provided",
            "POST",
            "/v1/extract",
            body=EXTRACT_PAYLOAD,
            headers={
                "Content-Type": "application/json",
                "X-Request-ID": "probe-request-1",
                "X-Trace-ID": "probe-trace-1",
            },
        )
        submit = self.request(
            "extract_jobs",
            "POST",
            "/v1/extract/jobs",
            body=EXTRACT_PAYLOAD,
            headers={
                "Content-Type": "application/json",
                "X-Request-ID": "probe-request-2",
                "X-Trace-ID": "probe-trace-2",
            },
        )

        job_id = ""
        if isinstance(submit.json_body, dict):
            job_id = str(submit.json_body.get("job_id", ""))

        status = self.request(
            "job_status",
            "GET",
            f"/v1/extract/jobs/{job_id}",
            headers={
                "X-Request-ID": "probe-request-3",
                "X-Trace-ID": "probe-trace-2",
            },
        )

        self.add_check("healthz_ok", healthz.status == 200 and healthz.json_body == {"status": "ok"})
        self.add_check("readyz_ready", readyz.status == 200 and readyz.json_body == {"status": "ready"})
        self.add_check("metrics_available", metrics.status == 200)
        self.add_check("metrics_include_gateway_requests_total", "gateway_requests_total" in metrics.body)
        self.add_check(
            "metrics_include_gateway_upstream_requests_total",
            "gateway_upstream_requests_total" in metrics.body,
        )
        self.add_check(
            "generated_identity_response_body",
            generated.status == 200
            and isinstance(generated.json_body, dict)
            and bool(generated.json_body.get("request_id"))
            and bool(generated.json_body.get("trace_id")),
        )
        self.add_check(
            "generated_identity_response_headers",
            generated.status == 200
            and bool(generated.headers.get("x-request-id"))
            and bool(generated.headers.get("x-trace-id")),
        )
        self.add_check(
            "provided_extract_identity_preserved",
            provided.status == 200
            and json_field(provided, "request_id") == "probe-request-1"
            and json_field(provided, "trace_id") == "probe-trace-1"
            and provided.headers.get("x-request-id") == "probe-request-1"
            and provided.headers.get("x-trace-id") == "probe-trace-1",
        )
        self.add_check(
            "async_submit_identity_preserved",
            submit.status == 202
            and json_field(submit, "request_id") == "probe-request-2"
            and json_field(submit, "trace_id") == "probe-trace-2"
            and submit.headers.get("x-request-id") == "probe-request-2"
            and submit.headers.get("x-trace-id") == "probe-trace-2",
        )
        self.add_check(
            "async_status_identity_preserved",
            status.status == 200
            and json_field(status, "request_id") == "probe-request-3"
            and json_field(status, "trace_id") == "probe-trace-2"
            and status.headers.get("x-request-id") == "probe-request-3"
            and status.headers.get("x-trace-id") == "probe-trace-2",
        )

    def scenario_timeout(self) -> None:
        response = self.request(
            "timeout_slow_extract",
            "POST",
            "/v1/extract",
            body=EXTRACT_PAYLOAD,
            headers={
                "Content-Type": "application/json",
                "X-Test-Behavior": "slow",
            },
        )
        self.add_check(
            "timeout_returns_gateway_timeout",
            response.status == 504 and error_code(response) == "upstream_timeout",
        )
        metrics = self.request("timeout_metrics", "GET", "/metrics")
        self.add_check(
            "timeout_metrics_include_edge_error",
            metrics.status == 200 and 'gateway_edge_errors_total{code="upstream_timeout"}' in metrics.body,
        )

    def scenario_concurrency(self) -> None:
        result: dict[str, CapturedResponse] = {}

        def run_slow_request() -> None:
            result["first"] = self.request(
                "concurrency_first_slow",
                "POST",
                "/v1/extract",
                body=EXTRACT_PAYLOAD,
                headers={
                    "Content-Type": "application/json",
                    "X-Test-Behavior": "slow",
                },
                timeout=15.0,
            )

        thread = threading.Thread(target=run_slow_request)
        thread.start()
        time.sleep(0.1)
        second = self.request(
            "concurrency_second",
            "POST",
            "/v1/extract",
            body=EXTRACT_PAYLOAD,
            headers={"Content-Type": "application/json"},
        )
        thread.join(timeout=15.0)

        first = result.get("first")
        self.add_check(
            "concurrency_first_request_completed",
            first is not None and first.status == 200,
        )
        self.add_check(
            "concurrency_second_request_rejected",
            second.status == 503 and error_code(second) == "concurrency_limited",
        )
        metrics = self.request("concurrency_metrics", "GET", "/metrics")
        self.add_check(
            "concurrency_metrics_include_edge_error",
            metrics.status == 200 and 'gateway_edge_errors_total{code="concurrency_limited"}' in metrics.body,
        )

    def scenario_upstream_unavailable(self) -> None:
        readyz = self.request("unavailable_readyz", "GET", "/readyz")
        extract = self.request(
            "unavailable_extract",
            "POST",
            "/v1/extract",
            body=EXTRACT_PAYLOAD,
            headers={"Content-Type": "application/json"},
        )
        self.add_check(
            "readyz_reports_upstream_unavailable",
            readyz.status == 503 and error_code(readyz) == "upstream_unavailable",
        )
        self.add_check(
            "extract_reports_upstream_unavailable",
            extract.status == 503 and error_code(extract) == "upstream_unavailable",
        )
        metrics = self.request("unavailable_metrics", "GET", "/metrics")
        self.add_check(
            "unavailable_metrics_include_edge_error",
            metrics.status == 200 and 'gateway_edge_errors_total{code="upstream_unavailable"}' in metrics.body,
        )

    def scenario_request_too_large(self) -> None:
        response = self.request(
            "request_too_large",
            "POST",
            "/v1/extract",
            body='{"too":"large"}',
            headers={"Content-Type": "application/json"},
        )
        self.add_check(
            "request_too_large_rejected",
            response.status == 413 and error_code(response) == "request_too_large",
        )
        metrics = self.request("request_too_large_metrics", "GET", "/metrics")
        self.add_check(
            "request_too_large_metrics_include_edge_error",
            metrics.status == 200 and 'gateway_edge_errors_total{code="request_too_large"}' in metrics.body,
        )

    def scenario_route_disabled(self) -> None:
        response = self.request(
            "route_disabled",
            "POST",
            "/v1/extract",
            body=EXTRACT_PAYLOAD,
            headers={"Content-Type": "application/json"},
        )
        self.add_check(
            "route_disabled_rejected",
            response.status == 403 and error_code(response) == "route_not_allowed",
        )
        metrics = self.request("route_disabled_metrics", "GET", "/metrics")
        self.add_check(
            "route_disabled_metrics_include_edge_error",
            metrics.status == 200 and 'gateway_edge_errors_total{code="route_not_allowed"}' in metrics.body,
        )

    def scenario_rate_limit(self) -> None:
        first = self.request(
            "rate_limit_first",
            "POST",
            "/v1/extract",
            body=EXTRACT_PAYLOAD,
            headers={"Content-Type": "application/json"},
        )
        second = self.request(
            "rate_limit_second",
            "POST",
            "/v1/extract",
            body=EXTRACT_PAYLOAD,
            headers={"Content-Type": "application/json"},
        )
        self.add_check("rate_limit_first_request_admitted", first.status == 200)
        self.add_check(
            "rate_limit_second_request_rejected",
            second.status == 429 and error_code(second) == "rate_limited",
        )
        metrics = self.request("rate_limit_metrics", "GET", "/metrics")
        self.add_check(
            "rate_limit_metrics_include_edge_error",
            metrics.status == 200 and 'gateway_edge_errors_total{code="rate_limited"}' in metrics.body,
        )

    def scenario_unsupported_route(self) -> None:
        response = self.request("unsupported_route", "GET", "/v1/unsupported")
        self.add_check(
            "unsupported_route_rejected",
            response.status == 404 and error_code(response) == "unsupported_route",
        )
        metrics = self.request("unsupported_route_metrics", "GET", "/metrics")
        self.add_check(
            "unsupported_route_metrics_include_request",
            metrics.status == 200
            and 'gateway_requests_total{method="GET",route="unsupported_route",status="404"}' in metrics.body,
        )

    def scenario_extract_jobs_disabled(self) -> None:
        response = self.request(
            "extract_jobs_disabled",
            "POST",
            "/v1/extract/jobs",
            body=EXTRACT_PAYLOAD,
            headers={"Content-Type": "application/json"},
        )
        self.add_check(
            "extract_jobs_disabled_rejected",
            response.status == 403 and error_code(response) == "route_not_allowed",
        )

    def scenario_job_status_disabled(self) -> None:
        response = self.request("job_status_disabled", "GET", "/v1/extract/jobs/job-123")
        self.add_check(
            "job_status_disabled_rejected",
            response.status == 403 and error_code(response) == "route_not_allowed",
        )

    def scenario_metrics_disabled(self) -> None:
        response = self.request("metrics_disabled", "GET", "/metrics")
        self.add_check(
            "metrics_disabled_route_not_served",
            response.status == 404 and error_code(response) == "unsupported_route",
        )

    def write_manifest(self, mode: str, scenarios: list[str], runtime_config: dict[str, str]) -> int:
        failed = [name for name, ok in self.checks.items() if not ok]
        manifest = {
            "mode": mode,
            "gateway_url": self.gateway_url,
            "scenarios": scenarios,
            "runtime_config": runtime_config,
            "checks": self.checks,
            "artifacts": self.artifacts,
            "interpretation_limits": [
                "This probe validates gateway behavior against the deterministic mock upstream.",
                "It does not validate real backend inference semantics.",
            ],
        }
        (self.artifact_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        self.write_summary(mode, scenarios, failed)
        if failed:
            print("Mock gateway probe validation failed:", file=sys.stderr)
            for name in failed:
                print(f" - {name}", file=sys.stderr)
            return 1
        return 0

    def write_summary(self, mode: str, scenarios: list[str], failed: list[str]) -> None:
        lines = [
            f"# {mode} Probe Summary",
            "",
            f"- Gateway URL: {self.gateway_url}",
            f"- Scenarios: {', '.join(scenarios)}",
            f"- Checks passed: {sum(1 for ok in self.checks.values() if ok)}",
            f"- Checks failed: {len(failed)}",
            "",
            "## Checks",
            "",
        ]
        for name, ok in self.checks.items():
            marker = "pass" if ok else "fail"
            lines.append(f"- {marker}: `{name}`")
        lines.append("")
        lines.append("Use `manifest.json` as the machine-readable proof contract for this probe.")
        lines.append("")
        (self.artifact_dir / "summary.md").write_text("\n".join(lines))


def parse_json(raw: str) -> Any | None:
    if not raw.strip():
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def lower_headers(headers: dict[str, str]) -> dict[str, str]:
    return {key.lower(): value for key, value in headers.items()}


def format_headers(headers: dict[str, str]) -> str:
    return "".join(f"{key}: {value}\n" for key, value in headers.items())


def error_code(response: CapturedResponse) -> str:
    if isinstance(response.json_body, dict):
        error = response.json_body.get("error")
        if isinstance(error, dict):
            return str(error.get("code", ""))
    return ""


def json_field(response: CapturedResponse, key: str) -> Any:
    if isinstance(response.json_body, dict):
        return response.json_body.get(key)
    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-dir", required=True)
    parser.add_argument("--gateway-url", required=True)
    parser.add_argument("--mode", required=True)
    parser.add_argument(
        "--scenario",
        action="append",
        choices=[
            "base",
            "timeout",
            "concurrency",
            "upstream_unavailable",
            "request_too_large",
            "route_disabled",
            "rate_limit",
            "unsupported_route",
            "extract_jobs_disabled",
            "job_status_disabled",
            "metrics_disabled",
        ],
        required=True,
    )
    parser.add_argument(
        "--runtime-config",
        action="append",
        default=[],
        help="Runtime config entry recorded in the manifest, formatted as KEY=VALUE.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    artifact_dir = Path(args.artifact_dir)
    artifact_dir.mkdir(parents=True, exist_ok=True)

    probe = Probe(args.gateway_url, artifact_dir)
    for scenario in args.scenario:
        getattr(probe, f"scenario_{scenario}")()

    runtime_config = {}
    for entry in args.runtime_config:
        if "=" not in entry:
            raise SystemExit(f"--runtime-config must be KEY=VALUE, got {entry!r}")
        key, value = entry.split("=", 1)
        runtime_config[key] = value

    return probe.write_manifest(args.mode, args.scenario, runtime_config)


if __name__ == "__main__":
    raise SystemExit(main())
