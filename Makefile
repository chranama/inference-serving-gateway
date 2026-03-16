.PHONY: fmt test run build

fmt:
	find . -name '*.go' -not -path './vendor/*' -print0 | xargs -0 gofmt -w

test:
	go test ./...

run:
	@test -n "$$GATEWAY_UPSTREAM_BASE_URL" || (echo "Set GATEWAY_UPSTREAM_BASE_URL before running"; exit 1)
	go run ./cmd/gateway

build:
	go build ./cmd/gateway

