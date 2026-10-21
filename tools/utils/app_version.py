#!/usr/bin/env python3
"""从根目录 VERSION 读取唯一版本，供 Flutter、安装包和发布脚本共同使用。"""

import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def read_version(root=ROOT):
    """校验版本与构建号，并生成三个桌面平台需要的版本表示。"""
    try:
        text = (root / 'VERSION').read_text(encoding='utf-8-sig').strip()
    except OSError as error:
        raise SystemExit(f'Cannot read VERSION: {error}') from error
    match = re.fullmatch(
        r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
        r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+(0|[1-9][0-9]*))?', text)
    if not match:
        raise SystemExit('Invalid VERSION: expected X.Y.Z[-prerelease][+build-number]')
    major, minor, patch, prerelease, number = match.groups()
    number = number or '1'
    # Windows 文件资源版本的四段数字均为 16 位，提前校验以免各平台出现不同结果。
    if any(int(part) > 65535 for part in (major, minor, patch, number)):
        raise SystemExit('Invalid VERSION: numeric components must be at most 65535')
    base = f'{major}.{minor}.{patch}'
    name = base + (f'-{prerelease}' if prerelease else '')
    return {
        'name': name, 'build_name': base, 'build_number': number,
        'full': f'{name}+{number}', 'resource': f'{base}.{number}',
        'debian': base + (f'~{prerelease}' if prerelease else ''),
    }


def run_flutter(arguments):
    """通过参数列表调用 Flutter，为编译和开发运行统一注入 VERSION。"""
    if not arguments or arguments[0] not in ('build', 'run'):
        raise SystemExit('Usage: app_version.py flutter <build|run> [Flutter arguments]')
    # 拒绝覆盖版本参数，保证操作系统元数据、Dart 上报与安装包来自同一版本。
    reserved = ('--build-name', '--build-number')
    if any(arg.split('=', 1)[0] in reserved or 'REMLARK_VERSION=' in arg for arg in arguments):
        raise SystemExit('Version arguments are managed by VERSION')
    version = read_version()
    executable = shutil.which('flutter')
    if not executable:
        raise SystemExit('Flutter not found. Add the Flutter SDK bin directory to PATH.')
    # Flutter run 没有 build-name / build-number 参数，开发运行只注入 Dart 版本。
    metadata = [] if arguments[0] == 'run' else [
        f'--build-name={version["build_name"]}',
        f'--build-number={version["build_number"]}',
    ]
    return subprocess.run([
        executable, *arguments, *metadata,
        f'--dart-define=REMLARK_VERSION={version["full"]}',
    ], cwd=ROOT).returncode


def main():
    """提供跨平台 JSON 查询和带版本的 Flutter 编译 / 运行入口。"""
    if sys.argv[1:] == ['json']:
        print(json.dumps(read_version()))
        return 0
    if sys.argv[1:2] == ['flutter']:
        return run_flutter(sys.argv[2:])
    raise SystemExit('Usage: app_version.py json | flutter <build|run> [arguments]')


if __name__ == '__main__':
    sys.exit(main())
