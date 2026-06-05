.PHONY: fmt test run build proof proof-host proof-compose proof-otel proof-kind-up proof-kind-status proof-kind proof-kind-down proof-isolated

fmt:
	find . -name '*.go' -not -path './vendor/*' -print0 | xargs -0 gofmt -w

test:
	go test ./...

run:
	@test -n "$$GATEWAY_UPSTREAM_BASE_URL" || (echo "Set GATEWAY_UPSTREAM_BASE_URL before running"; exit 1)
	go run ./cmd/gateway

build:
	go build ./cmd/gateway

proof: proof-compose

proof-host:
	proof/generate_mock_proof.sh

proof-compose:
	proof/generate_mock_compose_proof.sh

proof-otel:
	proof/generate_mock_compose_otel_proof.sh

proof-kind-up:
	proof/run_mock_kind_stack.sh up

proof-kind-status:
	proof/run_mock_kind_stack.sh status

proof-kind:
	proof/run_mock_kind_stack.sh proof

proof-kind-down:
	proof/run_mock_kind_stack.sh down

proof-isolated: proof-host proof-compose proof-otel
