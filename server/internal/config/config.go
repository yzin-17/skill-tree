package config

import (
	"errors"
	"net/url"
	"os"
)

type Config struct {
	DatabaseURL string
	Address     string
	TLSCert     string
	TLSKey      string
	TLSByProxy  bool
}

func Load() (Config, error) {
	c := Config{DatabaseURL: os.Getenv("DATABASE_URL"), Address: os.Getenv("LISTEN_ADDR"), TLSCert: os.Getenv("TLS_CERT"), TLSKey: os.Getenv("TLS_KEY")}
	if c.Address == "" {
		c.Address = ":8447"
	}
	u, err := url.Parse(c.DatabaseURL)
	if err != nil || u.Host == "" || (u.Scheme != "postgres" && u.Scheme != "postgresql") {
		return c, errors.New("DATABASE_URL 必须是有效的 PostgreSQL 连接地址")
	}
	switch os.Getenv("TLS_TERMINATED_BY_PROXY") {
	case "", "false":
	case "true":
		c.TLSByProxy = true
	default:
		return c, errors.New("TLS_TERMINATED_BY_PROXY 必须为 true 或 false")
	}
	if c.TLSByProxy {
		if c.TLSCert != "" || c.TLSKey != "" {
			return c, errors.New("代理终止 TLS 时不能同时配置 TLS_CERT 或 TLS_KEY")
		}
	} else if c.TLSCert == "" || c.TLSKey == "" {
		return c, errors.New("必须配置 TLS_CERT 和 TLS_KEY")
	}
	return c, nil
}
