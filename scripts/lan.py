#!/usr/bin/env python3
"""配置局域网私有 CA 入口，保留原有本机后端与客户端。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

import local

ROOT = local.ROOT
CA_FILE = local.RUNTIME / 'lan' / 'root.crt'
CA_SOURCE = '/data/caddy/pki/authorities/local/root.crt'
SHARE = ROOT / 'dist' / 'lan-setup'


def validate_host(value):
    value = value.lower().rstrip('.')
    if len(value) > 253 or '.' not in value or any(
        not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label)
        for label in value.split('.')
    ):
        raise ValueError('请使用有效的主机名，例如 skillatlas.local。')
    try:
        socket.inet_aton(value)
    except OSError:
        return value
    raise ValueError('请使用稳定的主机名，而非 IP 地址。')


def validate_port(value):
    port = int(value)
    if not 1024 <= port <= 65535:
        raise ValueError('局域网端口必须在 1024–65535 之间。')
    return str(port)


def settings(host=None, port=None, save=False, enabled=None, ca_port=None):
    if not local.ENV_FILE.exists():
        raise ValueError('请先运行 python3 scripts/local.py up，准备本机后端。')
    env = local.load_environment()
    hostname = host or env.get('LAN_HOST')
    if not hostname:
        if sys.platform != 'darwin':
            raise ValueError('请通过 --host 指定局域网可解析的主机名。')
        hostname = subprocess.check_output(['scutil', '--get', 'LocalHostName'], text=True).strip() + '.local'
    env['LAN_HOST'] = validate_host(hostname)
    env['LAN_PORT'] = validate_port(port or env.get('LAN_PORT', '8448'))
    env['CA_PORT'] = validate_port(ca_port or env.get('CA_PORT', '8081'))
    env['LAN_SITE_FILE'] = ('Caddyfile.lan' if enabled else 'Caddyfile.lan-disabled') if enabled is not None else env.get('LAN_SITE_FILE', 'Caddyfile.lan-disabled')
    if env['LAN_SITE_FILE'] not in {'Caddyfile.lan', 'Caddyfile.lan-disabled'}:
        raise ValueError('局域网站点配置无效。')
    if env['LAN_PORT'] in {env.get('API_PORT', '8447'), env.get('DATABASE_PORT', '55437')}:
        raise ValueError('局域网入口必须使用与本机 API、数据库不同的端口。')
    if env['CA_PORT'] in {env['LAN_PORT'], env.get('API_PORT', '8447'), env.get('DATABASE_PORT', '55437')}:
        raise ValueError('根证书下载必须使用独立的空闲端口。')
    if save:
        keys = ['LAN_HOST', 'LAN_PORT', 'CA_PORT', 'LAN_SITE_FILE']
        lines = [line for line in local.ENV_FILE.read_text().splitlines()
                 if not line.startswith(tuple(key + '=' for key in keys))]
        lines += [f'{key}={env[key]}' for key in keys]
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=local.ENV_FILE.parent, delete=False) as output:
                temporary = Path(output.name)
                output.write('\n'.join(lines) + '\n')
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, local.ENV_FILE)
        finally:
            if temporary is not None: temporary.unlink(missing_ok=True)
    return env


def compose(*args):
    return local.compose(*args)


def address(env):
    return f"https://{env['LAN_HOST']}:{env['LAN_PORT']}"


def ca_address(env):
    return f"http://{env['LAN_HOST']}:{env['CA_PORT']}/root.crt"


def export_ca(env):
    # 首次启动可能仍在生成根 CA；只读取公开根证书，不复制私钥。
    result = None
    for attempt in range(10):
        result = subprocess.run(compose('exec', '-T', 'lan-proxy', 'cat', CA_SOURCE),
                                cwd=ROOT, env={**os.environ, **env}, capture_output=True)
        if result.returncode == 0:
            break
        if attempt < 9:
            time.sleep(1)
    if result.returncode != 0:
        raise ValueError('尚未取得公开根证书；请检查 python3 scripts/lan.py status。')
    pem = result.stdout.decode('ascii')
    ssl.PEM_cert_to_DER_cert(pem)
    CA_FILE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    CA_FILE.write_text(pem)
    public = CA_FILE.parent / 'public'
    public.mkdir(mode=0o755, parents=True, exist_ok=True)
    public.chmod(0o755)
    (public / 'root.crt').write_text(pem)
    local.publish_root(pem, env)
    SHARE.mkdir(parents=True, exist_ok=True)
    (SHARE / 'root.crt').write_text(pem)
    (SHARE / '安装信任.command').write_text('''#!/bin/zsh
set -eu
setup_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
/usr/bin/security add-trusted-cert -r trustRoot -p ssl -k "$HOME/Library/Keychains/login.keychain-db" "$setup_dir/root.crt"
echo '根证书已加入当前用户的 SSL 信任。请在 Skill Atlas 中保存说明文件里的后端地址，并检查连接。'
''')
    (SHARE / '安装信任.command').chmod(0o755)
    fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest()
    (SHARE / '接入说明.txt').write_text(f'''Skill Atlas 局域网接入
生成日期：{time.strftime('%Y-%m-%d')}；适用于 macOS。

后端地址：{address(env)}
根证书下载：{ca_address(env)}
根证书 SHA-256：{fingerprint}

1. 将整个 lan-setup 文件夹复制到另一台 Mac，或只传递 root.crt 与此说明。
2. 确认根证书指纹与服务端提供的一致。只导入你信任的服务端提供的证书。
3. 在终端执行下列命令（将路径替换为接收到的 root.crt 路径）：
   security add-trusted-cert -r trustRoot -p ssl -k "$HOME/Library/Keychains/login.keychain-db" /完整路径/root.crt
   也可以双击“安装信任.command”；系统可能要求确认或认证。
4. 在 Skill Atlas 登录页“后端地址…”或设置“编辑地址”中填写上述地址，检查连接并保存。
5. 使用原有账号登录。地址切换会采用独立的本机缓存与会话，不会自动沿用 localhost 的登录状态。

需要两台设备位于可互通并支持 mDNS 的局域网；请关闭访客网络的设备隔离。
无需安装新的 Skill Atlas，也无需传递 CA 私钥。
旧版客户端本机入口若曾使用默认 localhost，请一次性改用 https://127.0.0.1:{env['API_PORT']}；以后证书续期不必更换客户端。
''')
    with zipfile.ZipFile(SHARE.with_suffix('.zip'), 'w', zipfile.ZIP_DEFLATED) as bundle:
        for name in ['root.crt', '安装信任.command', '接入说明.txt']:
            bundle.write(SHARE / name, arcname='lan-setup/' + name)
    print(f'公开根证书：{CA_FILE}\n下载地址：{ca_address(env)}\n接入文件夹：{SHARE}\n根证书 SHA-256：{fingerprint}')


def health(env):
    if not CA_FILE.exists():
        raise ValueError('缺少公开根证书；请先运行 python3 scripts/lan.py export-ca。')
    context = ssl.create_default_context(cafile=str(CA_FILE))
    # 只检查局域网直连，避免系统 HTTP 代理将 .local 请求转出局域网。
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                         urllib.request.HTTPSHandler(context=context))
    with opener.open(address(env) + '/health', timeout=10) as response:
        envelope = json.load(response)
    value = envelope.get('data', {}) if isinstance(envelope, dict) else {}
    if not isinstance(value, dict) or any(value.get(key) != expected for key, expected in
           [('service', 'Skill Atlas'), ('status', 'ok'), ('database', 'ready')]):
        raise ValueError('该入口未返回可用的 Skill Atlas 健康状态。')
    print(f"局域网 HTTPS 验证通过：{address(env)}；数据库就绪。")


def trust_ca():
    if sys.platform != 'darwin' or not CA_FILE.exists():
        raise ValueError('该命令需要 macOS 和已经导出的根证书。')
    subprocess.run(['security', 'add-trusted-cert', '-r', 'trustRoot', '-p', 'ssl', '-k',
                    str(Path.home() / 'Library/Keychains/login.keychain-db'), str(CA_FILE)],
                   check=True, timeout=30)
    print('已将根 CA 加入当前用户的 SSL 信任。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['up', 'down', 'status', 'health', 'export-ca', 'trust-ca'])
    parser.add_argument('--host', help='稳定且可解析的局域网主机名，默认采用本机 .local 名称')
    parser.add_argument('--port', help='局域网 HTTPS 端口，默认 8448')
    parser.add_argument('--ca-port', help='公开根证书 HTTP 下载端口，默认 8081')
    args = parser.parse_args()
    if args.action != 'up' and (args.host or args.port or args.ca_port):
        parser.error('--host、--port 和 --ca-port 仅用于 up；其他命令使用保存的配置。')
    env = settings(args.host, args.port, ca_port=args.ca_port)
    if args.action == 'up':
        env = settings(args.host, args.port, save=True, enabled=True, ca_port=args.ca_port)
        local.up()
        health(env)
    elif args.action == 'down':
        env = settings(save=True, enabled=False)
        local.run(compose('up', '-d', '--no-deps', '--force-recreate', '--wait', 'lan-proxy'), env={**os.environ, **env})
        local.health()
        print('局域网 HTTPS 和证书下载入口已关闭，本机 HTTPS 入口继续运行。')
    elif args.action == 'status':
        local.run(compose('ps', 'lan-proxy'), env={**os.environ, **env})
        print(f'局域网地址：{address(env)}')
        print(f"局域网启用：{env['LAN_SITE_FILE'] == 'Caddyfile.lan'}；根证书下载：{ca_address(env)}")
    elif args.action == 'health': health(env)
    elif args.action == 'export-ca': export_ca(env)
    elif args.action == 'trust-ca': trust_ca()


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, urllib.error.URLError, subprocess.SubprocessError) as error:
        # 不输出可能包含凭据的命令参数或完整环境。
        print(f'局域网配置失败：{type(error).__name__}；请检查服务状态、根证书和系统认证提示。', file=sys.stderr)
        if isinstance(error, ValueError): print(str(error), file=sys.stderr)
        sys.exit(1)
