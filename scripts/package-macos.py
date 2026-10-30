#!/usr/bin/env python3
"""校验通用 macOS 应用，生成 ZIP、DMG、构建信息和校验清单。"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_macos', ROOT / 'scripts/build-macos.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


def validate_tag(tag, version):
    if tag != 'v' + version or not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('版本标签必须与 macos/version.json 完全匹配。')


def check_private_files(app):
    for path in Path(app).rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        name = path.name.lower()
        if (path.suffix.lower() in {'.pem', '.key', '.p12', '.pfx', '.sqlite', '.db', '.env'}
                or name in {'local.env', '.env'} or '-wal' in name or '-shm' in name
                or re.search(rb'-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----', path.read_bytes())):
            raise ValueError('应用包包含私有配置、密钥或运行数据：' + str(path.relative_to(app)))


def inspect_app(app, expected):
    app = Path(app).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier') != 'local.skillatlas.app'
            or info.get('CFBundleShortVersionString') != expected['version']
            or info.get('CFBundleVersion') != str(expected['build'])
            or info.get('CFBundleIconName') != 'AppIcon'):
        raise ValueError('应用身份、版本、构建号或图标与发布源码不一致。')
    check_private_files(app)
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    architectures = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).split()
    if set(architectures) != {'arm64', 'x86_64'}:
        raise ValueError('安装包必须同时包含 arm64 与 x86_64。')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
    resources = app / 'Contents/Resources'
    build.validate_client_resources(resources)
    if not (resources / 'AppIcon.icns').is_file() or not (resources / 'Assets.car').is_file():
        raise ValueError('应用图标资源缺失。')
    return {'version': expected['version'], 'build': expected['build'],
            'bundle_id': info['CFBundleIdentifier'], 'minimum_macos': info['LSMinimumSystemVersion'],
            'architectures': sorted(architectures), 'signature': 'ad-hoc', 'notarized': False,
            'executable_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
            'certificate_sha256': hashlib.sha256((resources / 'cert.der').read_bytes()).hexdigest()}


def verify_dmg(path, expected, executable_digest):
    subprocess.run(['hdiutil', 'verify', str(path)], check=True, capture_output=True)
    result = subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(path)],
                            check=True, capture_output=True)
    entities = plistlib.loads(result.stdout)['system-entities']
    mounts = [Path(e['mount-point']) for e in entities if 'mount-point' in e]
    if len(mounts) != 1:
        raise ValueError('安装镜像挂载结构不符合预期。')
    mount = mounts[0]
    try:
        info = inspect_app(mount / 'Skill Atlas.app', expected)
        if info['executable_sha256'] != executable_digest:
            raise ValueError('镜像内应用与原产物不一致。')
        if not (mount / 'Applications').is_symlink() or os.readlink(mount / 'Applications') != '/Applications':
            raise ValueError('镜像中缺少 Applications 安装快捷方式。')
    finally:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True, capture_output=True)


def package(app, output, tag=None, revision=None):
    expected = json.loads((ROOT / 'macos/version.json').read_text())
    if tag:
        validate_tag(tag, expected['version'])
    app, output = Path(app).resolve(), Path(output).resolve()
    if output == app or app in output.parents:
        raise ValueError('产物目录必须位于应用包之外。')
    metadata = inspect_app(app, expected)
    stem = f"Skill-Atlas-{expected['version']}-{expected['build']}-macos-universal"
    names = [stem + '.zip', stem + '.dmg', 'build-info.json', 'SHA256SUMS']
    output.mkdir(parents=True, exist_ok=True)
    if any((output / name).exists() for name in names):
        raise ValueError('同名安装包已经存在，请使用新的输出目录。')
    with tempfile.TemporaryDirectory(prefix='skillatlas-package-') as temporary:
        temporary = Path(temporary)
        stage = temporary / 'stage'
        stage.mkdir()
        staged_app = stage / 'Skill Atlas.app'
        shutil.copytree(app, staged_app, symlinks=True)
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(staged_app), str(output / names[0])], check=True)
        extracted = temporary / 'extracted'
        subprocess.run(['ditto', '-x', '-k', str(output / names[0]), str(extracted)], check=True)
        unpacked = inspect_app(extracted / 'Skill Atlas.app', expected)
        if unpacked['executable_sha256'] != metadata['executable_sha256']:
            raise ValueError('ZIP 解包后的应用与原产物不一致。')
        (stage / 'Applications').symlink_to('/Applications')
        subprocess.run(['hdiutil', 'create', '-volname', 'Skill Atlas', '-srcfolder', str(stage),
                        '-format', 'UDZO', str(output / names[1])], check=True, capture_output=True)
        verify_dmg(output / names[1], expected, metadata['executable_sha256'])
    metadata.update({'tag': tag, 'source_revision': revision or os.environ.get('GITHUB_SHA', 'local-uncommitted'),
                     'ci_run_url': (f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
                                    if 'GITHUB_REPOSITORY' in os.environ and 'GITHUB_RUN_ID' in os.environ else None),
                     'packages': names[:2]})
    (output / 'build-info.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    (output / 'SHA256SUMS').write_text(''.join(
        hashlib.sha256((output / name).read_bytes()).hexdigest() + '  ' + name + '\n' for name in names[:3]))
    print('安装包与解包、挂载校验通过：', output)
    for name in names:
        print(name, (output / name).stat().st_size, '字节')
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    parser.add_argument('--tag')
    parser.add_argument('--revision')
    args = parser.parse_args()
    package(args.app, args.output, args.tag, args.revision)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('安装包生成失败：', str(error) if not isinstance(error, subprocess.CalledProcessError)
              else '系统打包或校验工具返回错误。', file=sys.stderr)
        raise SystemExit(1)
