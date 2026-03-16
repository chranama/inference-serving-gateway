package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/chranama/inference-serving-gateway/internal/config"
	"github.com/chranama/inference-serving-gateway/internal/httpapi"
	"github.com/chranama/inference-serving-gateway/internal/observability"
	"github.com/chranama/inference-serving-gateway/internal/upstream"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	logger, err := observability.NewLogger(cfg.LogLevel)
	if err != nil {
		slog.Error("failed to build logger", "error", err)
		os.Exit(1)
	}

	metrics, err := observability.NewMetrics()
	if err != nil {
		logger.Error("failed to create metrics", "error", err)
		os.Exit(1)
	}

	upstreamClient, err := upstream.NewClient(cfg.UpstreamBaseURL, metrics)
	if err != nil {
		logger.Error("failed to configure upstream client", "error", err)
		os.Exit(1)
	}

	handler := httpapi.NewHandler(cfg, logger, metrics, upstreamClient)

	server := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	logger.Info("gateway starting", "listen_addr", cfg.ListenAddr, "upstream_base_url", cfg.UpstreamBaseURL)

	shutdownCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		<-shutdownCtx.Done()

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		logger.Info("gateway shutting down")
		if err := server.Shutdown(ctx); err != nil {
			logger.Error("graceful shutdown failed", "error", err)
		}
	}()

	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Error("gateway server failed", "error", err)
		os.Exit(1)
	}
}
