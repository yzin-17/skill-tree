#!/usr/bin/env python3
"""在发布前核对原 CI、标签提交、成功作业及未过期产物。"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def api(path):
    result = subprocess.run(['gh', 'api', path], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('无法读取发布来源，已停止发布。')
    return json.loads(result.stdout)


def validate_source(run, jobs, artifacts, tag_sha, repository):
    if (run.get('repository', {}).get('full_name') != repository or run.get('event') != 'push'
            or run.get('path', '').split('@')[0] != '.github/workflows/release.yml'
            or not re.fullmatch(r'v\d+\.\d+\.\d+', run.get('head_branch', ''))
            or not re.fullmatch(r'[0-9a-f]{40}', run.get('head_sha', ''))
            or run['head_sha'] != tag_sha):
        raise ValueError('原 CI 的仓库、工作流、标签或提交不符合发布来源要求。')
    for name in ['源码与后端测试', 'macOS 通用安装包']:
        matches = [job for job in jobs if job['name'] == name]
        if len(matches) != 1 or matches[0]['conclusion'] != 'success':
            raise ValueError('原 CI 的必要测试或打包作业尚未成功。')
    matches = [artifact for artifact in artifacts if artifact['name'] == 'SkillAtlas-macos-universal']
    if (len(matches) != 1 or matches[0].get('expired') is not False
            or matches[0].get('workflow_run', {}).get('head_sha') != run['head_sha']):
        raise ValueError('原 CI 的有效安装包产物缺失或来源不符。')
    return {'sha': run['head_sha'], 'tag': run['head_branch'], 'run_id': str(run['id'])}


def main():
    repository = os.environ['GITHUB_REPOSITORY']
    run_id = os.environ.get('SOURCE_RUN_ID') or os.environ['GITHUB_RUN_ID']
    if not run_id.isdigit() or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('来源运行编号或仓库无效。')
    prefix = f'repos/{repository}'
    run = api(f'{prefix}/actions/runs/{run_id}')
    tag = run.get('head_branch', '')
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('原运行不是版本标签构建。')
    reference = api(f'{prefix}/git/ref/tags/{tag}')['object']
    for _ in range(5):
        if reference['type'] == 'commit':
            break
        if reference['type'] != 'tag':
            raise ValueError('标签未指向提交。')
        reference = api(f"{prefix}/git/tags/{reference['sha']}")['object']
    else:
        raise ValueError('标签引用层级无效。')
    jobs = api(f'{prefix}/actions/runs/{run_id}/jobs?filter=latest&per_page=100')['jobs']
    artifacts = api(f'{prefix}/actions/runs/{run_id}/artifacts?per_page=100')['artifacts']
    source = validate_source(run, jobs, artifacts, reference['sha'], repository)
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        for key, value in source.items():
            output.write(f'{key}={value}\n')
    print('已验证发布来源：', source['tag'], source['sha'], 'CI', source['run_id'])


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print('发布来源未通过：', error, file=sys.stderr)
        raise SystemExit(1)
