package limiter

import "golang.org/x/time/rate"

// ConcurrencyLimiter enforces a global in-flight request cap.
type ConcurrencyLimiter struct {
	tokens chan struct{}
}

// NewConcurrencyLimiter creates a concurrency limiter. A non-positive limit disables it.
func NewConcurrencyLimiter(limit int) *ConcurrencyLimiter {
	if limit <= 0 {
		return nil
	}
	return &ConcurrencyLimiter{
		tokens: make(chan struct{}, limit),
	}
}

// TryAcquire attempts to reserve one slot.
func (l *ConcurrencyLimiter) TryAcquire() bool {
	if l == nil {
		return true
	}
	select {
	case l.tokens <- struct{}{}:
		return true
	default:
		return false
	}
}

// Release releases a previously acquired slot.
func (l *ConcurrencyLimiter) Release() {
	if l == nil {
		return
	}
	select {
	case <-l.tokens:
	default:
	}
}

// NewRateLimiter creates an optional token-bucket rate limiter.
func NewRateLimiter(rps float64, burst int) *rate.Limiter {
	if rps <= 0 {
		return nil
	}
	if burst <= 0 {
		burst = 1
	}
	return rate.NewLimiter(rate.Limit(rps), burst)
}
