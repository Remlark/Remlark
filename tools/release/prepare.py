#!/usr/bin/env python3
"""统一 Release 的版本校验、macOS 安装镜像与发布附件清单。"""

import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.app_version import read_version


def version():
    """从 VERSION 读取发布版本，构建号不进入标签与安装包文件名。"""
    return read_version(ROOT)['name']


def validate_tag():
    """拒绝版本与标签不一致或非版本标签，避免发布名称与安装器版本不同。"""
    expected = f'v{version()}'
    if os.environ.get('RELEASE_TAG') != expected:
        raise SystemExit(f'RELEASE_TAG must equal {expected}')


def macos():
    """检查主程序与两项 FFI 库均包含双架构，再生成拖入 Applications 的 DMG。"""
    app = ROOT / 'build/macos/Build/Products/Release/remlark.app'
    # 防止修改 VERSION 后直接复用旧应用打包，导致文件名与系统版本不一致。
    expected = read_version(ROOT)
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if (info.get('CFBundleShortVersionString') != expected['build_name'] or
            str(info.get('CFBundleVersion')) != expected['build_number']):
        raise SystemExit('macOS application version does not match VERSION; run make mac first')
    binaries = [app / 'Contents/MacOS/remlark']
    for name in ('rdp', 'crypto'):
        matches = list(app.rglob(f'*remlark_{name}*'))
        binaries.extend(path for path in matches if path.is_file())
        if not matches:
            raise SystemExit(f'missing native library: {name}')
    for binary in binaries:
        subprocess.run(['lipo', str(binary), '-verify_arch', 'x86_64', 'arm64'], check=True)
    # CI 在 make mac 后重签 App，重新生成 zip，确保两个附件包含同一份签名。
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    archive = dist / 'remlark-macos.zip'
    archive.unlink(missing_ok=True)
    subprocess.run(['ditto', '-c', '-k', '--keepParent', str(app), str(archive)], check=True)
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
        for target in ('macos', 'windows', 'linux'):
            extension = 'zip' if target == 'windows' else 'tar.gz'
            required.append(f'remlark-sync-server-{version()}-{target}-{arch}.{extension}')
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
