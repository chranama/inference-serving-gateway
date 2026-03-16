package health

import "context"

// Checker reports readiness.
type Checker interface {
	Check(ctx context.Context) error
}

// CheckerFunc adapts a function into a Checker.
type CheckerFunc func(ctx context.Context) error

// Check implements Checker.
func (f CheckerFunc) Check(ctx context.Context) error {
	return f(ctx)
}

// ReadyClient is the minimal upstream client contract needed for readiness.
type ReadyClient interface {
	CheckReady(ctx context.Context) error
}

// NewUpstreamChecker returns a readiness checker backed by the upstream client's readyz endpoint.
func NewUpstreamChecker(client ReadyClient) Checker {
	return CheckerFunc(func(ctx context.Context) error {
		return client.CheckReady(ctx)
	})
}
