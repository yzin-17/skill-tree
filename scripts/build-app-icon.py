#!/usr/bin/env python3
"""将应用图标母版转换为 macOS 的标准尺寸资源。"""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'macos/Resources'
CATALOG = RESOURCES / 'Assets.xcassets'
ICONS = CATALOG / 'AppIcon.appiconset'
MASTER = RESOURCES / 'AppIcon-master.png'


def write_json(path, value):
    text = json.dumps(value, indent=2) + '\n'
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


def generate():
    if not MASTER.is_file():
        raise FileNotFoundError('应用图标母版缺失：' + str(MASTER))
    ICONS.mkdir(parents=True, exist_ok=True)
    info = {'author': 'xcode', 'version': 1}
    write_json(CATALOG / 'Contents.json', {'info': info})
    images = []
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            filename = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
            target = ICONS / filename
            pixels = str(size * scale)
            if not target.exists() or target.stat().st_mtime_ns < MASTER.stat().st_mtime_ns:
                subprocess.run(['sips', '-z', pixels, pixels, str(MASTER), '--out', str(target)],
                               check=True, stdout=subprocess.DEVNULL)
            images.append({'idiom': 'mac', 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': filename})
    write_json(ICONS / 'Contents.json', {'images': images, 'info': info})
    print('应用图标资源：', ICONS)


if __name__ == '__main__':
    generate()
