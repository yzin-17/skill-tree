package config

import "testing"

func TestRequiresDatabaseAndTLS(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	if _, err := Load(); err == nil {
		t.Fatal("missing database accepted")
	}
	t.Setenv("DATABASE_URL", "postgres://localhost/skillatlas")
	t.Setenv("TLS_CERT", "")
	t.Setenv("TLS_KEY", "")
	if _, err := Load(); err == nil {
		t.Fatal("missing TLS accepted")
	}
	t.Setenv("TLS_CERT", "cert.pem")
	t.Setenv("TLS_KEY", "key.pem")
	if _, err := Load(); err != nil {
		t.Fatal(err)
	}
}
