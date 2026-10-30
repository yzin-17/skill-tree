package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"flag"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata"

	"skillatlas/internal/config"
	"skillatlas/internal/httpapi"
	"skillatlas/internal/storage"
)

func main() {
	healthcheck := flag.Bool("healthcheck", false, "检查本机 HTTPS 健康状态")
	flag.Parse()
	c, err := config.Load()
	if err != nil {
		slog.Error(err.Error())
		os.Exit(1)
	}
	if *healthcheck {
		cert, err := os.ReadFile(c.TLSCert)
		if err != nil {
			os.Exit(1)
		}
		roots := x509.NewCertPool()
		if !roots.AppendCertsFromPEM(cert) {
			os.Exit(1)
		}
		client := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}}}
		_, port, err := net.SplitHostPort(c.Address)
		if err != nil {
			os.Exit(1)
		}
		response, err := client.Get("https://" + net.JoinHostPort("localhost", port) + "/health")
		if err != nil {
			os.Exit(1)
		}
		response.Body.Close()
		if response.StatusCode != 200 {
			os.Exit(1)
		}
		return
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	startup, cancel := context.WithTimeout(ctx, 20*time.Second)
	pool, err := storage.Open(startup, c.DatabaseURL)
	if err != nil {
		slog.Error("数据库启动失败")
		os.Exit(1)
	}
	defer pool.Close()
	if err = storage.Migrate(startup, pool); err != nil {
		slog.Error("数据库迁移失败", "error", err)
		os.Exit(1)
	}
	cancel()
	server := &http.Server{Addr: c.Address, Handler: httpapi.New(pool), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, TLSConfig: &tls.Config{MinVersion: tls.VersionTLS12}}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		server.Shutdown(shutdown)
	}()
	slog.Info("Skill Atlas HTTPS 已启动", "version", httpapi.Version)
	if err = server.ListenAndServeTLS(c.TLSCert, c.TLSKey); err != nil && err != http.ErrServerClosed {
		slog.Error("HTTPS 服务退出")
		os.Exit(1)
	}
}
