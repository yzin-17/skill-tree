#!/usr/bin/env python3
"""检查项目文档日期、相对链接及任务依赖，输出简短结果。"""
from pathlib import Path
import re
import sys
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
FILES = [ROOT / 'README.md', *sorted((ROOT / 'docs').rglob('*.md'))]

def anchors(text):
    result = set(re.findall(r'<a\s+id="([^"]+)"', text))
    for title in re.findall(r'^#+\s+(.+)$', text, re.M):
        value = re.sub(r'[^\w\-\s\u4e00-\u9fff]', '', title.lower()).replace(' ', '-')
        result.add(value)
    return result

def main():
    errors = []; links = 0; graph = {}; leaves = 0
    for file in FILES:
        text = file.read_text()
        if '首次创建：' not in text[:700] or '最近更新：' not in text[:700]: errors.append(f'{file.relative_to(ROOT)} 缺少日期页头')
        for target in re.findall(r'(?<!!)\[[^\]]+\]\(([^)]+)\)', text):
            target = target.strip('<>')
            if re.match(r'^[a-zA-Z]+:', target): continue
            path, _, anchor = urllib.parse.unquote(target).partition('#')
            destination = (file.parent / path).resolve() if path else file
            links += 1
            if not destination.exists(): errors.append(f'{file.relative_to(ROOT)} 链接缺失：{target}')
            elif anchor and destination.suffix == '.md' and anchor not in anchors(destination.read_text()): errors.append(f'{file.relative_to(ROOT)} 锚点缺失：{target}')
        if '/tasks/' in str(file):
            for match in re.finditer(r'<a id="([^"]+)"></a>\s*\n(- \[[ x]\][\s\S]*?)(?=\n<a id=|\Z)', text):
                key = str(file.resolve()) + '#' + match[1]; graph[key] = []; leaves += 1
                dependency = re.search(r'^  - 启动依赖：(.+)$', match[2], re.M)
                if dependency:
                    for target in re.findall(r'\[[^\]]+\]\(([^)]+)\)', dependency[1]):
                        path, _, anchor = target.partition('#')
                        if anchor: graph[key].append(str((file.parent / path).resolve() if path else file.resolve()) + '#' + anchor)
    active = set(); visited = set()
    def visit(key):
        if key in active: errors.append('任务依赖成环：' + key); return
        if key in visited: return
        active.add(key)
        for child in graph.get(key, []): visit(child)
        active.remove(key); visited.add(key)
    for key in graph: visit(key)
    if errors:
        print('\n'.join(errors)); return 1
    print(f'通过：{len(FILES)} 份文档日期、{links} 个本地链接、{leaves} 个任务叶/门禁；依赖无环。')
    return 0

if __name__ == '__main__': sys.exit(main())
