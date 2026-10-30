#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / '.runtime'
ENV_FILE = RUNTIME / 'local.env'

def run(args, **kwargs):
    return subprocess.run(args, check=True, cwd=ROOT, **kwargs)

def load_environment():
    return dict(line.split('=', 1) for line in ENV_FILE.read_text().splitlines() if line and not line.startswith('#'))

def prepare(renew_certificate=False):
    RUNTIME.mkdir(mode=0o700, exist_ok=True)
    RUNTIME.chmod(0o700)
    if not ENV_FILE.exists():
        existing = subprocess.run(['docker', 'volume', 'inspect', 'skillatlas-postgres-v1'], capture_output=True)
        if existing.returncode == 0:
            raise SystemExit('已有数据库卷而本地凭据缺失；请恢复原 .runtime/local.env，不会重置数据。')
        for port in [8447, 55437]:
            with socket.socket() as sock:
                try: sock.bind(('127.0.0.1', port))
                except OSError: raise SystemExit(f'本机端口 {port} 已占用；未停止其他服务。')
        password = secrets.token_hex(24)
        values = {'POSTGRES_ADMIN_PASSWORD': secrets.token_hex(24), 'APP_DATABASE_PASSWORD': password,
                  'APP_DATABASE_URL': f'postgres://skillatlas_app:{password}@postgres:5432/skillatlas?sslmode=disable',
                  'LOCAL_DATABASE_URL': f'postgres://skillatlas_app:{password}@127.0.0.1:55437/skillatlas?sslmode=disable',
                  'API_PORT': '8447', 'DATABASE_PORT': '55437', 'LOCAL_UID': str(os.getuid()), 'LOCAL_GID': str(os.getgid())}
        ENV_FILE.write_text(''.join(f'{key}={value}\n' for key, value in values.items()))
        ENV_FILE.chmod(0o600)
    tls = RUNTIME / 'tls'
    tls.mkdir(mode=0o700, exist_ok=True)
    if renew_certificate or not (tls / 'cert.pem').exists():
        run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
             '-days', '365', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
             '-addext', 'extendedKeyUsage=serverAuth', '-addext', 'keyUsage=digitalSignature', '-addext', 'basicConstraints=critical,CA:FALSE',
             '-keyout', str(tls / 'key.pem'), '-out', str(tls / 'cert.pem')], capture_output=True)
        (tls / 'key.pem').chmod(0o600)
    run(['openssl', 'x509', '-in', str(tls / 'cert.pem'), '-outform', 'DER', '-out', str(tls / 'cert.der')], capture_output=True)
    env = load_environment()
    (RUNTIME / 'client-config.json').write_text(json.dumps({'base_url': 'https://localhost:' + env['API_PORT'],
        'certificate_sha256': hashlib.sha256((tls / 'cert.der').read_bytes()).hexdigest()}, indent=2) + '\n')
    return env

def compose(*args):
    return ['docker', 'compose', '--env-file', str(ENV_FILE), '-f', str(ROOT / 'dev/compose.yaml'), *args]

def database():
    env = prepare()
    run(compose('up', '-d', '--wait', '--wait-timeout', '90', 'postgres'))
    password = env['APP_DATABASE_PASSWORD']
    if not all(c in '0123456789abcdef' for c in password): raise SystemExit('本地凭据格式无效')
    sql = f"DO $body$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='skillatlas_app') THEN CREATE ROLE skillatlas_app LOGIN PASSWORD '{password}'; END IF; END $body$;\n"
    sql += 'GRANT CONNECT, CREATE ON DATABASE skillatlas TO skillatlas_app;\nGRANT USAGE, CREATE ON SCHEMA public TO skillatlas_app;\n'
    run(compose('exec', '-T', 'postgres', 'psql', '-v', 'ON_ERROR_STOP=1', '-U', 'skillatlas_admin', '-d', 'skillatlas'), input=sql, text=True, capture_output=True)
    return env

def health():
    env = load_environment()
    context = ssl.create_default_context(cafile=str(RUNTIME / 'tls/cert.pem'))
    with urllib.request.urlopen('https://localhost:' + env['API_PORT'] + '/health', context=context, timeout=5) as response:
        print(response.read().decode().strip())

def main():
    parser = argparse.ArgumentParser(description='Skill Atlas 本机开发与运行工具')
    parser.add_argument('action', choices=['prepare', 'renew-certificate', 'db', 'up', 'down', 'status', 'health', 'test'])
    parser.add_argument('packages', nargs='*')
    args = parser.parse_args()
    if args.action == 'prepare': prepare(); print('本机配置已准备，凭据未输出。')
    elif args.action == 'renew-certificate': prepare(renew_certificate=True); print('证书已更新；重启 API 并重新构建应用以更新固定公钥。')
    elif args.action == 'db': database()
    elif args.action == 'up': database(); run(compose('up', '-d', '--build', '--wait', '--wait-timeout', '90', 'api')); health()
    elif args.action == 'down': run(compose('down'))
    elif args.action == 'status': run(compose('ps'))
    elif args.action == 'health': health()
    elif args.action == 'test':
        env = database(); process_env = os.environ.copy(); process_env['TEST_DATABASE_URL'] = env['LOCAL_DATABASE_URL']
        go = ROOT / '.tools/go/bin/go'
        subprocess.run([str(go), 'test', '-count=1', *(args.packages or ['./...'])], cwd=ROOT / 'server', env=process_env, check=True)

if __name__ == '__main__':
    try: main()
    except subprocess.CalledProcessError as error:
        print(f'命令执行失败（退出码 {error.returncode}）；本地凭据未输出。', file=sys.stderr)
        sys.exit(error.returncode)
