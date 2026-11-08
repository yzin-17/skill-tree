package config

import "testing"

func TestRequiresDatabaseAndTLS(t *testing.T) {
	t.Setenv("TLS_TERMINATED_BY_PROXY", "")
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

func TestProxyTLSRequiresExplicitUnambiguousConfiguration(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://localhost/skillatlas")
	t.Setenv("TLS_CERT", "")
	t.Setenv("TLS_KEY", "")
	t.Setenv("TLS_TERMINATED_BY_PROXY", "true")
	c, err := Load()
	if err != nil || !c.TLSByProxy {
		t.Fatalf("代理模式未启用：%v", err)
	}
	t.Setenv("TLS_CERT", "cert.pem")
	if _, err := Load(); err == nil {
		t.Fatal("混合配置未被拒绝")
	}
	t.Setenv("TLS_CERT", "")
	t.Setenv("TLS_TERMINATED_BY_PROXY", "1")
	if _, err := Load(); err == nil {
		t.Fatal("歧义开关未被拒绝")
	}
	t.Setenv("TLS_TERMINATED_BY_PROXY", "false")
	if _, err := Load(); err == nil {
		t.Fatal("默认模式未要求 TLS")
	}
}
