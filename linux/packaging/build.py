#!/usr/bin/env python3
"""将完整 Flutter Linux Release 打包为便携 tar.gz 与 Debian 系统安装包。"""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.app_version import read_version


def validate_bundle(bundle):
    """发布前确认引擎、AOT、原生库及桌面资源齐全，避免分发功能降级的包。"""
    required = [
        'remlark', 'lib/libflutter_linux_gtk.so', 'lib/libapp.so',
        'lib/libremlark_rdp.so', 'lib/libremlark_crypto.so',
        'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin',
        'share/applications/com.remlark.remlark.desktop', 'install-desktop.py',
        'share/icons/hicolor/256x256/apps/com.remlark.remlark.png',
    ]
    for name in required:
        if not (bundle / name).is_file():
            raise SystemExit(f'Linux bundle 缺少必需文件：{name}')
    if not list((bundle / 'lib').glob('*sqlite3*.so')):
        raise SystemExit('Linux bundle 缺少 sqlite3 原生库')


def package(bundle, output, arch):
    """使用临时目录暂存 Debian 包，并从实际 ELF 依赖生成 Depends。"""
    validate_bundle(bundle)
    version = read_version(ROOT)
    app_version = version['name']
    deb_version = version['debian']
    deb_arch = {'x64': 'amd64', 'arm64': 'arm64'}[arch]
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='remlark-linux-') as temporary:
        stage = Path(temporary)
        # Debian 包的根目录应可遍历，不能沿用临时目录默认的 700 权限。
        stage.chmod(0o755)
        app = stage / 'opt/remlark'
        shutil.copytree(bundle, app, symlinks=True)
        (stage / 'usr/bin').mkdir(parents=True)
        (stage / 'usr/bin/remlark').symlink_to('/opt/remlark/remlark')
        shutil.copytree(app / 'share', stage / 'usr/share')
        # dpkg-shlibdeps 读取源包元数据；只忽略随应用分发、没有系统包归属的私有库。
        debian = stage / 'debian'
        debian.mkdir()
        (debian / 'control').write_text('Source: remlark\n\nPackage: remlark\nArchitecture: any\nDescription: Remlark desktop workspace\n')
        control = stage / 'DEBIAN'
        control.mkdir()
        elfs = [app / 'remlark', *sorted((app / 'lib').glob('*.so'))]
        result = subprocess.run([
            'dpkg-shlibdeps', '--ignore-missing-info', '-O', f'-l{app / "lib"}',
            *[f'-e{file}' for file in elfs],
        ], cwd=stage, check=True, text=True, stdout=subprocess.PIPE)
        depends = next(line.split('=', 1)[1] for line in result.stdout.splitlines() if line.startswith('shlibs:Depends='))
        shutil.rmtree(debian)
        size = sum(file.stat().st_size for file in app.rglob('*') if file.is_file()) // 1024
        (control / 'control').write_text(
            f'Package: remlark\nVersion: {deb_version}\nArchitecture: {deb_arch}\n'
            'Maintainer: Remlark Developers\nSection: net\nPriority: optional\n'
            f'Installed-Size: {size}\nDepends: {depends}\n'
            'Description: Remote terminal and desktop workspace\n'
            ' SSH, SFTP, RDP, VNC and AI workspace.\n', encoding='utf-8')
        # 不继承开发机 umask 产生的组写权限，保留程序和安装脚本的可执行位。
        for path in stage.rglob('*'):
            if not path.is_symlink():
                path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
        subprocess.run(['dpkg-deb', '--root-owner-group', '--build', str(stage),
                        str(output / f'remlark-{app_version}-linux-{deb_arch}.deb')], check=True)
    with tarfile.open(output / f'remlark-linux-{arch}.tar.gz', 'w:gz') as archive:
        archive.add(bundle, arcname='bundle')


def main():
    """解析与 Flutter 一致的目标架构，支持已有 Release 的独立打包。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['x64', 'arm64'], default='x64')
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    bundle = args.bundle or ROOT / f'build/linux/{args.arch}/release/bundle'
    package(bundle.resolve(), args.output.resolve(), args.arch)


if __name__ == '__main__':
    main()
