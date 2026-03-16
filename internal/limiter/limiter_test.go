package limiter

import "testing"

func TestConcurrencyLimiterAcquireRelease(t *testing.T) {
	limit := NewConcurrencyLimiter(1)
	if limit == nil {
		t.Fatal("NewConcurrencyLimiter returned nil")
	}

	if !limit.TryAcquire() {
		t.Fatal("first acquire should succeed")
	}
	if limit.TryAcquire() {
		t.Fatal("second acquire should fail while slot is held")
	}

	limit.Release()

	if !limit.TryAcquire() {
		t.Fatal("acquire should succeed after release")
	}
}

func TestNewRateLimiterDisabledByDefault(t *testing.T) {
	if got := NewRateLimiter(0, 0); got != nil {
		t.Fatal("NewRateLimiter(0, 0) should disable rate limiting")
	}
}
