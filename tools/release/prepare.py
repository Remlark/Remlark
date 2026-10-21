#!/usr/bin/env python3
"""统一 Release 的版本校验、macOS 安装镜像与发布附件清单。"""

import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def version():
    """从应用声明中读取版本，保留预发布后缀但不把构建号放入标签。"""
    return re.search(r'^version:\s*(\S+)', (ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)[1].split('+')[0]


def validate_tag():
    """拒绝版本与标签不一致或非版本标签，避免发布名称与安装器版本不同。"""
    expected = f'v{version()}'
    if os.environ.get('RELEASE_TAG') != expected:
        raise SystemExit(f'RELEASE_TAG must equal {expected}')


def macos():
    """检查主程序与两项 FFI 库均包含双架构，再生成拖入 Applications 的 DMG。"""
    app = ROOT / 'build/macos/Build/Products/Release/remlark.app'
    binaries = [app / 'Contents/MacOS/remlark']
    for name in ('rdp', 'crypto'):
        matches = list(app.rglob(f'*remlark_{name}*'))
        binaries.extend(path for path in matches if path.is_file())
        if not matches:
            raise SystemExit(f'missing native library: {name}')
    for binary in binaries:
        subprocess.run(['lipo', '-verify_arch', 'x86_64', 'arm64', str(binary)], check=True)
    output = ROOT / 'dist' / f'remlark-{version()}-macos-universal.dmg'
    with tempfile.TemporaryDirectory(prefix='remlark-dmg-') as stage:
        subprocess.run(['ditto', str(app), f'{stage}/remlark.app'], check=True)
        Path(stage, 'Applications').symlink_to('/Applications')
        subprocess.run(['hdiutil', 'create', '-volname', 'Remlark', '-srcfolder', stage,
                        '-ov', '-format', 'UDZO', str(output)], check=True)


def manifest():
    """在发布前检查所有平台附件齐全，并对实际字节生成 SHA-256 校验文件。"""
    validate_tag()
    dist = ROOT / 'dist'
    required = [f'remlark-{version()}-macos-universal.dmg', 'remlark-macos.zip']
    for arch, deb_arch in [('x64', 'amd64'), ('arm64', 'arm64')]:
        required.extend([f'remlark-{version()}-windows-{arch}-setup.exe',
                         f'remlark-windows-{arch}.zip',
                         f'remlark-{version()}-linux-{deb_arch}.deb',
                         f'remlark-linux-{arch}.tar.gz'])
    lines = []
    for name in sorted(required):
        path = dist / name
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f'missing or empty release asset: {name}')
        with path.open('rb') as payload:
            digest = hashlib.file_digest(payload, 'sha256').hexdigest()
        lines.append(f'{digest}  {name}\n')
    (dist / 'SHA256SUMS').write_text(''.join(lines), encoding='utf-8')


if __name__ == '__main__':
    {'validate': validate_tag, 'macos': macos, 'manifest': manifest}[sys.argv[1]]()
