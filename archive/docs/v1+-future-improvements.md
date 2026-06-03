# v1+ Future Improvements

This document captures the highest-signal next steps for `inference-serving-gateway` after `v1.0.0`.

The goal is not to turn the project into a giant platform all at once.
The goal is to extend it in ways that most clearly support an `AI Platform Engineer` positioning:

- shared platform ownership
- runtime policy and control
- observability and operational clarity
- multi-tenant serving concerns
- rollout and reliability discipline

## Guiding Principle

Prefer improvements that make the gateway look more like:

- a reusable AI serving edge platform

and less like:

- a thin proxy for one backend

## Highest-Signal Future Improvements

## 1. Edge Auth and Tenancy

Add:

- gateway-side API-key validation
- tenant identity
- tenant-scoped route permissions
- tenant-scoped quotas and rate limits
- audit-friendly auth and usage logs

Why this matters:

- this is one of the clearest signs of platform ownership
- it moves the project from request forwarding toward shared infrastructure
- it demonstrates responsibility for multi-tenant serving boundaries

Best proof artifacts:

- a tenant policy config example
- a live proof showing two tenants with different limits or route access
- an audit log example for a blocked or over-quota request

Notes:

- this is intentionally deferred beyond `v1`
- if implemented, it should stay clearly separated from backend extraction semantics

## 2. Policy-Driven Routing and Rollouts

Add:

- multiple upstream backends
- health-aware routing
- canary and weighted routing
- failover between upstreams
- optional shadow traffic for safe evaluation

Why this matters:

- it makes the gateway feel like runtime infrastructure rather than a single-backend adapter
- it shows operational judgment around rollout safety
- it is very legible AI platform work

Best proof artifacts:

- a routing policy file
- a canary rollout demo
- a failover proof showing degraded upstream handling without client contract breakage

## 3. First-Class Observability

Add:

- OpenTelemetry traces
- stronger edge-to-backend correlation
- example dashboards
- SLOs and alert-friendly metrics
- a short debugging or incident walkthrough

Why this matters:

- observability is one of the strongest parts of the `AI Platform Engineer` identity
- it shows you can make serving systems operable, not just functional
- it turns request/trace continuity into a real operations story

Best proof artifacts:

- dashboard screenshots
- a trace walkthrough from gateway edge to backend completion
- an SLO/runbook doc

## 4. Async Reliability Semantics

Add:

- idempotency keys
- stronger cancellation behavior
- retry policy and retry classification
- dead-letter or failed-job handling
- clearer terminal-state guarantees

Why this matters:

- async lifecycle correctness is high-signal platform engineering
- it demonstrates that the system is designed for real workload behavior, not only happy paths

Best proof artifacts:

- a retry and failure-handling proof
- an idempotent resubmission demo
- a concise job lifecycle state diagram

## 5. Cost and Budget Controls

Add:

- token and cost estimation at the edge
- per-tenant budget enforcement
- admission decisions based on cost policy
- usage accounting surfaces

Why this matters:

- AI platform work is partly about economics, not only infrastructure
- this is especially strong positioning for LLM serving systems

Best proof artifacts:

- budget policy examples
- usage summary or accounting output
- a proof showing a request blocked by budget policy

## 6. Deployment and Operations Packaging

Add:

- a Helm chart
- production-minded Kubernetes manifests
- rollout guidance
- secrets and config patterns
- autoscaling notes

Why this matters:

- it makes the project easier to read as deployable infrastructure
- it signals that you can own the path from local proof to service operations

Best proof artifacts:

- Helm chart scaffold
- deployment notes
- rollout checklist

## 7. Capability-Aware Upstream Registry

Add:

- explicit upstream registry
- routing by capability or contract
- policy-based upstream selection
- clearer metadata around what each upstream supports

Why this matters:

- it makes the gateway feel more like an AI runtime layer
- it avoids overfitting the project to one backend

Best proof artifacts:

- upstream registry config
- capability-based routing example
- proof showing contract-preserving routing choice

## Suggested Roadmap

If only a few post-`v1` improvements are implemented, the highest-leverage order is:

1. edge auth and tenancy
2. policy-driven routing and rollouts
3. first-class observability

That sequence gives the strongest signal for:

- platform boundaries
- shared service ownership
- operational maturity

## Lower-Priority Ideas

These may still be useful, but are weaker for the specific `AI Platform Engineer` positioning goal:

- a large admin UI before stronger runtime policy exists
- many provider integrations without a coherent routing story
- moving extraction or business logic out of the backend
- app-level product features that belong in backend services, not the gateway

## Success Standard For v1+

Future work should ideally produce at least one of these:

- a stronger platform boundary
- a stronger operational story
- a stronger multi-tenant/runtime-control story
- a stronger deployment/readiness story

If a feature does not make one of those clearer, it is probably lower priority for this project.
