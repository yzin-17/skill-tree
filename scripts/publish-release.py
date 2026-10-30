#!/usr/bin/env python3
"""将已校验的本次 CI 安装包上传为草稿，完整核验后发布 GitHub Release。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def validate_assets(directory, tag, revision, repository, run_id):
    directory = Path(directory)
    expected = json.loads((ROOT / 'macos/version.json').read_text())
    if tag != 'v' + expected['version'] or not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('标签与当前源码版本不一致。')
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('缺少有效的 CI 源码提交。')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository) or not str(run_id).isdigit():
        raise ValueError('CI 仓库或运行编号无效。')
    metadata = json.loads((directory / 'build-info.json').read_text())
    stem = f"Skill-Atlas-{expected['version']}-{expected['build']}-macos-universal"
    packages = [stem + '.zip', stem + '.dmg']
    run_url = f'https://github.com/{repository}/actions/runs/{run_id}'
    if (metadata.get('version') != expected['version'] or metadata.get('build') != expected['build']
            or metadata.get('tag') != tag or metadata.get('source_revision') != revision
            or metadata.get('ci_run_url') != run_url or metadata.get('packages') != packages
            or set(metadata.get('architectures', [])) != {'arm64', 'x86_64'}
            or metadata.get('bundle_id') != 'local.skillatlas.app'
            or metadata.get('signature') != 'ad-hoc' or metadata.get('notarized') is not False):
        raise ValueError('资产版本、架构、签名或来源不属于当前 CI 运行。')
    checksums = {}
    for line in (directory / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9_.-]+)', line)
        if not match or match[2] in checksums:
            raise ValueError('校验清单格式无效或包含重复文件。')
        checksums[match[2]] = match[1]
    if set(checksums) != set(packages + ['build-info.json']):
        raise ValueError('校验清单必须完整覆盖安装包和构建信息。')
    assets = packages + ['build-info.json', 'SHA256SUMS']
    if {p.name for p in directory.iterdir()} != set(assets):
        raise ValueError('发布目录存在缺失或额外文件。')
    for name, digest in checksums.items():
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise ValueError('发布资产 SHA-256 不匹配：' + name)
    return metadata, assets


def gh(*arguments):
    result = subprocess.run(['gh', *arguments], capture_output=True, text=True)
    if result.returncode:
        # 认证材料不进入异常或工作流输出。
        raise RuntimeError('GitHub CLI 操作失败：' + arguments[0])
    return result.stdout


def get_release(repository, tag):
    result = subprocess.run(['gh', 'api', f'repos/{repository}/releases/tags/{tag}'],
                            capture_output=True, text=True)
    if result.returncode == 0:
        return json.loads(result.stdout)
    if 'HTTP 404' not in result.stderr and 'Not Found' not in result.stderr:
        raise RuntimeError('无法查询目标 Release，已停止发布。')
    # 按标签查询只返回已发布版本；草稿必须从有权限的 Release 列表查找。
    page = 1
    while True:
        entries = json.loads(gh('api', f'repos/{repository}/releases?per_page=100&page={page}'))
        for entry in entries:
            if entry['tag_name'] == tag:
                return entry
        if len(entries) < 100:
            return None
        page += 1


def release_notes(metadata, repository, marker):
    return f"""Skill Atlas {metadata['version']}（构建 {metadata['build']}）

macOS 原生个人成长工具，支持技能星图、任务结算、专注计时、经验等级和成长日志月历。本版包含白底珠光星形应用图标。

安装要求与使用：

- macOS {metadata['minimum_macos']} 及以上，通用安装包同时支持 Apple Silicon 与 Intel。
- 下载 DMG 后将 Skill Atlas 拖到 Applications；也可解压 ZIP 使用。
- 后端独立运行，可在登录页或设置中手动配置 HTTPS 地址；本版默认公共连接配置对应当前本机 Docker 后端。
- 本版采用 ad hoc 临时签名，尚未经过 Apple 公证；首次打开如被系统阻止，请在系统设置的隐私与安全性中处理。
- 将两个安装包、构建信息和 SHA256SUMS 放在同一目录，执行 `shasum -a 256 -c SHA256SUMS` 核对下载。

[源码提交](https://github.com/{repository}/commit/{metadata['source_revision']}) · [CI 构建记录]({metadata['ci_run_url']})

{marker}
"""


def publish(directory, tag, revision, repository, run_id):
    directory = Path(directory).resolve()
    metadata, assets = validate_assets(directory, tag, revision, repository, run_id)
    marker = f'<!-- skillatlas-ci:{revision}:{run_id} -->'
    release = get_release(repository, tag)
    if release is not None:
        if not release['draft']:
            raise ValueError('该版本已经正式发布，不会覆盖；请使用新的版本标签。')
        if marker not in (release.get('body') or '') or release.get('target_commitish') != revision:
            raise ValueError('已有草稿不属于本次 CI 运行，不会接管。')
    else:
        with tempfile.TemporaryDirectory(prefix='skillatlas-release-notes-') as temporary:
            notes = Path(temporary) / 'release-notes.md'
            notes.write_text(release_notes(metadata, repository, marker))
            gh('release', 'create', tag, '--repo', repository, '--verify-tag', '--draft',
               '--target', revision, '--title', f"Skill Atlas {metadata['version']}（构建 {metadata['build']}）",
               '--notes-file', str(notes))
    gh('release', 'upload', tag, '--repo', repository, '--clobber', *[str(directory / name) for name in assets])
    uploaded = get_release(repository, tag)
    if uploaded is None or not uploaded['draft']:
        raise ValueError('上传后草稿状态不符合预期。')
    remote_assets = uploaded.get('assets', [])
    if {asset['name'] for asset in remote_assets} != set(assets) or len(remote_assets) != len(assets):
        raise ValueError('草稿资产不完整，保持草稿状态。')
    needs_download = False
    for asset in remote_assets:
        local = directory / asset['name']
        if asset['size'] != local.stat().st_size:
            raise ValueError('草稿资产大小不匹配，保持草稿状态。')
        digest = asset.get('digest')
        if digest:
            if digest != 'sha256:' + hashlib.sha256(local.read_bytes()).hexdigest():
                raise ValueError('草稿资产摘要不匹配，保持草稿状态。')
        else:
            needs_download = True
    if needs_download:
        with tempfile.TemporaryDirectory(prefix='skillatlas-upload-verify-') as temporary:
            gh('release', 'download', tag, '--repo', repository, '--dir', temporary)
            for name in assets:
                if hashlib.sha256((Path(temporary) / name).read_bytes()).digest() != hashlib.sha256((directory / name).read_bytes()).digest():
                    raise ValueError('草稿下载校验失败，保持草稿状态。')
    with tempfile.TemporaryDirectory(prefix='skillatlas-final-notes-') as temporary:
        notes = Path(temporary) / 'release-notes.md'
        text = release_notes(metadata, repository, marker)
        publishing_run = os.environ.get('GITHUB_RUN_ID')
        if publishing_run and publishing_run != str(run_id):
            text += f'\n[接续发布记录](https://github.com/{repository}/actions/runs/{publishing_run})\n'
        notes.write_text(text)
        gh('release', 'edit', tag, '--repo', repository, '--draft=false', '--latest', '--notes-file', str(notes))
    final = get_release(repository, tag)
    if final is None or final['draft']:
        raise ValueError('正式发布状态未确认。')
    print('正式 Release 已发布：', final['html_url'])
    return final


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT / 'dist')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--source-revision')
    parser.add_argument('--source-run-id')
    args = parser.parse_args()
    publish(args.directory, args.tag, args.source_revision or os.environ['GITHUB_SHA'],
            os.environ['GITHUB_REPOSITORY'], args.source_run_id or os.environ['GITHUB_RUN_ID'])


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print('发布未完成：', error, file=sys.stderr)
        raise SystemExit(1)
