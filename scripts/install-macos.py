#!/usr/bin/env python3
"""构建并安装本机 .app，更新前保留可恢复的旧应用；不更改用户数据。"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = 'local.skillatlas.app'

def metadata(app):
    with (app / 'Contents/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise RuntimeError('目标路径包含其他应用，已停止安装。')
    return info

def verify(app):
    info = metadata(app)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise RuntimeError('应用可执行文件无效。')
    for forbidden in ['key.pem', 'local.env', 'server.key']:
        if any(app.rglob(forbidden)):
            raise RuntimeError('应用包中发现私有服务配置，已停止安装。')
    return info, hashlib.sha256(executable.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true', help='安装已经构建的 Release 产物')
    parser.add_argument('--source', type=Path, help='恢复指定的同一应用备份；跳过构建并校验签名')
    parser.add_argument('--destination', type=Path, default=Path.home() / 'Applications/Skill Atlas.app', help='安装位置')
    args = parser.parse_args()
    if not args.skip_build and args.source is None:
        subprocess.run([sys.executable, str(ROOT / 'scripts/build-macos.py'), '--release'], check=True)
    source = args.source.expanduser().absolute() if args.source else ROOT / '.runtime/DerivedData/Build/Products/Release/SkillAtlas.app'
    info, digest = verify(source)
    destination = args.destination.expanduser().absolute()
    if destination.resolve() == source.resolve():
        raise RuntimeError('安装位置不能与构建源目录相同。')
    if destination.suffix != '.app' or destination.is_symlink():
        raise RuntimeError('安装目标须为普通 .app 路径。')
    if destination.exists(): metadata(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    suffix = datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
    staging = destination.parent / ('.SkillAtlas-install-' + suffix + '.app')
    backup = destination.parent / ('.SkillAtlas-backup-' + suffix + '.app')
    moved = False
    try:
        shutil.copytree(source, staging, symlinks=True)
        verify(staging)
        if destination.exists(): destination.rename(backup); moved = True
        staging.rename(destination)
        # 安装目录时间用于系统图标缓存失效，不能沿用构建产物的旧时间。
        os.utime(destination, None)
        installed, installed_digest = verify(destination)
        if digest != installed_digest: raise RuntimeError('安装后的应用校验不一致。')
    except Exception:
        if staging.exists(): shutil.rmtree(staging)
        if moved:
            if destination.exists(): destination.rename(destination.parent / ('.SkillAtlas-failed-' + suffix + '.app'))
            backup.rename(destination)
        raise
    report = {
        'date': datetime.datetime.now().astimezone().isoformat(),
        'path': str(destination), 'version': installed['CFBundleShortVersionString'],
        'build': installed['CFBundleVersion'], 'bundle_id': BUNDLE_ID,
        'minimum_system': installed.get('LSMinimumSystemVersion'),
        'executable_sha256': digest, 'signature': 'ad hoc',
        'backup': str(backup) if moved else None, 'ui_launch_verified': False,
    }
    output = ROOT / '.runtime/acceptance'; output.mkdir(parents=True, exist_ok=True)
    (output / ('macos-install-' + suffix + '.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('已安装：', destination)
    print('版本：', info['CFBundleShortVersionString'], '构建：', info['CFBundleVersion'])
    if moved: print('更新前应用已保留：', backup)
    print('已验证应用包签名与可执行文件；实际启动及交互需另行验收。')

if __name__ == '__main__':
    try: main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print('安装未完成：', error, file=sys.stderr)
        raise SystemExit(1)
