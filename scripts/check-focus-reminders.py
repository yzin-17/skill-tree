#!/usr/bin/env python3
"""在隔离偏好与临时数据库中验证原生专注提醒及菜单栏数字宽度。"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT / 'macos'


def main():
    sources = sorted(
        path for directory in ('App', 'Core', 'Features')
        for path in (MAC / directory).rglob('*.swift')
        if path.name != 'SkillAtlasApp.swift'
    )
    with tempfile.TemporaryDirectory(prefix='skillatlas-focus-reminders-') as temporary:
        executable = Path(temporary) / 'FocusReminderRuntime'
        subprocess.run([
            'xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-lsqlite3',
            '-o', str(executable), *map(str, sources),
            str(MAC / 'Diagnostics/FocusReminderRuntime.swift'),
        ], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == '__main__':
    main()
