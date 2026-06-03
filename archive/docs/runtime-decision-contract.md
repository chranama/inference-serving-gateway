# Runtime Decision Contract

This document defines the Phase 2.2.9 runtime contract for the integrated:

- `inference-serving-gateway`
- `llm-extraction-platform`

Primary planning reference:

- `/Users/chranama/career/job-search/audit/2026-03-25__llm-platform-gateway-infra-obs-improvement-plan.md`

Backend quality reference:

- `/Users/chranama/career/llm-extraction-platform/docs/runtime-quality-scorecard.md`

Related contracts:

- [Trace Identity Contract](trace-identity-contract.md)
- [OpenTelemetry Contract](opentelemetry-contract.md)
- [Integrated Metrics Map](integrated-metrics-map.md)
- [/Users/chranama/career/llm-extraction-platform/docs/opentelemetry-contract.md](/Users/chranama/career/llm-extraction-platform/docs/opentelemetry-contract.md)

## Purpose

Phase 2.2.9 exists to make later cloud, failure, and operator work answerable to explicit runtime decisions rather than to "more observability" in the abstract.

This contract defines:

- which runtime signals matter most
- which windows they should be read over
- which labels are acceptable
- which signals are allowed to drive admission, rollback, or runtime-choice decisions
- which people those signals are meant to help

This is a bounded operator contract for a reviewer-friendly AI runtime system.
It is not a public SLA or a claim of full production operations maturity.

## Current Bounded Usage Scope

The current system already has one real customer/account boundary:

- authenticated API keys

For Phase 2.2.9, the bounded usage-scope seed is therefore:

- `api_key`-backed usage buckets in reports, runbooks, and admin usage surfaces

Current concrete usage surfaces already present:

- `GET /v1/me/usage`
- `GET /v1/admin/usage`
- inference logs keyed by `api_key`
- quota state on API-key records

Important rule:

- raw `api_key` values are acceptable in DB-backed admin/report surfaces
- raw `api_key` values are not acceptable default Prometheus labels

If a lower-cardinality usage label is needed later, it should be something bounded such as:

- role
- usage bucket
- project or workspace once those exist

## Personas And Decisions

| Persona | Main question | Primary signals |
| --- | --- | --- |
| Platform operator | Is the rollout healthy enough to keep, or should I roll back or tear down? | sync success rate, sync p95 latency, async completion-before-timeout rate, gateway edge errors |
| Internal application team | Which runtime path is safer for my workflow, and when is repair worth the latency/cost? | contract pass rate, malformed-output rate, repair attempt/success rate, policy rejection rate |
| Platform owner or engineering manager | Is the system controlling shared spend, fairness, and noisy-neighbor risk well enough? | request volume by usage scope, rough request cost, quota or admission rejects, error-budget burn |

Every later operator surface should make at least one of these decisions easier.

## Contract Windows

Use three windows consistently:

- live operator window:
  - `5m`
  - for p95 or p99 latency checks, edge-error spikes, and quick health calls
- rollout or rollback window:
  - `1h`
  - for bounded post-deploy judgment
- proof-artifact window:
  - one saved sync run and one saved async run
  - for reviewer-visible evidence packs and incident notes

If a signal cannot yet be expressed as a live metric, it should still be made visible in the proof-artifact window through traces, job records, or runbook notes.

## Label Strategy

Prometheus labels must stay low-cardinality enough to remain inspectable.

Allowed default metric labels in this system:

- `route`
- `method`
- `status`
- `result`
- `code`
- `model_id`
- `schema_id` for the bounded extract demo
- `cached`
- `outcome`
- `stage` when the stage set is explicitly bounded

Do not use these as default Prometheus labels:

- `request_id`
- `trace_id`
- `job_id`
- raw `api_key`
- raw prompt text
- raw output text
- unbounded prompt or workflow version identifiers
- policy snapshot blobs

Those belong in:

- logs
- traces
- replay manifests
- runbook or proof artifacts

## Raw Signal Contract

### Gateway signals

| Signal | Unit | Current source | Default labels | Main use |
| --- | --- | --- | --- | --- |
| `gateway_requests_total` | requests | Prometheus counter | `route`, `method`, `status` | request volume, sync or async availability baseline |
| `gateway_request_duration_seconds` | seconds | Prometheus histogram | `route`, `method` | p50, p95, p99 latency at the edge |
| `gateway_upstream_requests_total` | requests | Prometheus counter | `route`, `method`, `result` | upstream health and backend reachability |
| `gateway_upstream_request_duration_seconds` | seconds | Prometheus histogram | `route`, `method`, `result` | upstream latency contribution |
| `gateway_edge_errors_total` | errors | Prometheus counter | `code` | admission, rejection, and edge-owned failure spikes |

### Backend signals

| Signal | Unit | Current source | Default labels | Main use |
| --- | --- | --- | --- | --- |
| `llm_api_request_total` | requests | Prometheus counter | `route`, `model_id`, `cached`, `status_code` | backend request volume and outcome baseline |
| `llm_api_request_latency_seconds` | seconds | Prometheus histogram | `route`, `model_id`, `cached`, `status_code` | backend p50, p95, p99 latency |
| `llm_extraction_requests_total` | requests | Prometheus counter | `schema_id`, `model_id` | extract workload volume |
| `llm_extraction_validation_failures_total` | validation failures | Prometheus counter | `schema_id`, `model_id`, `stage` | malformed-output and contract-validity pressure |
| `llm_extraction_repair_total` | repair decisions | Prometheus counter | `schema_id`, `model_id`, `outcome` | repair attempt rate and repair success rate |
| `llm_guard_trips_total` | guard trips | Prometheus counter | `kind`, `route` | runtime shedding and local protection behavior |

### Report and inspection surfaces

| Surface | Unit | Current source | Main use |
| --- | --- | --- | --- |
| trace detail and trace-event timelines | per trace | backend admin trace surfaces and saved proof artifacts | async completion, lifecycle joins, route or stage diagnosis |
| `/v1/admin/logs` | per execution | backend admin execution-log surface | rough request cost inputs, prompt or output audit, runtime failure classification |
| `/v1/me/usage` and `/v1/admin/usage` | per usage scope | backend admin usage endpoints | request counts, token totals, quota context, per-scope metering |
| job-status timestamps | per async job | async status response and DB-backed job state | completion-before-timeout reasoning |

## Decision Use Rules

| Decision type | Allowed signals | Not allowed as primary trigger |
| --- | --- | --- |
| Admission or throttling | `gateway_edge_errors_total`, later quota or admission counters, runtime guard signals | ad hoc per-trace anecdotes, raw prompt or output examples |
| Runtime choice, repair, prompt, or policy iteration | contract pass rate, malformed-output rate, repair attempt and success rate, policy rejection rate, rough cost per request | a single successful demo response |
| Rollback or teardown | sync success rate, contract-valid rate, async completion-before-timeout rate, p95 latency, edge-error spike | one isolated log line without corroborating metric or trace evidence |

Special rule for fallback:

- do not invent a "fallback invocation" production signal until the bounded extraction path actually has a first-class runtime fallback path
- until then, fallback remains a reserved signal for later runtime-comparison work

## SLI And SLO Seeds

These are first-slice operating seeds for a bounded proof environment.

| SLI | Current source | Seed target | Response when broken |
| --- | --- | --- | --- |
| Sync extract success rate | `gateway_requests_total` on the sync extract route, backed by one completed backend trace | `>= 99%` over the `1h` rollout window and `100%` on canonical smoke | roll back or tear down the latest deploy candidate |
| Sync extract p95 latency | `gateway_request_duration_seconds` plus backend `llm_api_request_latency_seconds` for the same bounded profile | `<= 2.0s` over `5m` on the observability-proof profile | escalate if sustained; roll back if introduced by the current change |
| Contract-valid extract rate | `llm_extraction_requests_total` vs `llm_extraction_validation_failures_total`, backed by trace or job outcome checks | `>= 98%` over the `1h` rollout window | freeze route, prompt, or policy changes and revert the latest risky change |
| Async submit acceptance rate | gateway async-submit request counts plus `gateway_edge_errors_total` | `>= 99%` over the `1h` rollout window | inspect admission, config, and upstream reachability before continuing rollout |
| Async completion-before-timeout rate | trace timelines and async job timestamps today; first-class metric later if needed | `>= 95%` over the `1h` rollout window | escalate and block rollout; tear down if the bounded dev slice becomes misleading |

These seeds are intentionally modest:

- they are strong enough to justify rollback or escalation decisions
- they are narrow enough to defend in an interview
- they do not pretend the current system has a mature public SRE program

## Rollback And Escalation Seeds

Immediate rollback or teardown is justified when:

- the canonical sync smoke request fails
- the canonical async submit or poll proof fails
- sync success rate or contract-valid rate drops below the seed target after the current change

Escalate and freeze further rollout when:

- sync p95 latency exceeds `2x` the recent bounded baseline for `15m`
- async completion-before-timeout drops below seed even if requests are still being accepted
- edge rejections spike for a proof key that should be allowed
- rough request cost jumps materially without an intentional model, prompt, or policy change

For the first cloud slice, manual rollback or teardown is acceptable.
Automation can come later.

## Why Quotas, Metering, And Alerting Exist

Quotas or admission controls exist to:

- stop one usage scope from consuming bounded shared capacity
- keep noisy-neighbor behavior visible
- make abuse or accidental traffic spikes legible

Metering exists to:

- tie request volume back to a real usage scope
- estimate rough per-request or per-run cost
- support platform-owner discussions about spend and fairness

Alerts and SLOs exist to:

- support release and rollback calls
- separate "system unhealthy" from "one interesting trace was weird"
- keep the runtime story grounded in operator judgment rather than dashboard aesthetics

## Related Docs

- [Integrated Metrics Map](integrated-metrics-map.md)
- [Trace Identity Contract](trace-identity-contract.md)
- [AWS Deployment Contract](aws-deployment-contract.md)
- [/Users/chranama/career/llm-extraction-platform/docs/runtime-quality-scorecard.md](/Users/chranama/career/llm-extraction-platform/docs/runtime-quality-scorecard.md)
