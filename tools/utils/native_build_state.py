"""原生构建阶段完成记录：全部必需产物校验后才可复用或作为 CI 缓存保存。"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def recipe_signature(platform, stage):
    """将版本/编译参数、目标实现及 MSVC 版本纳入记录，拒绝复用旧配方产物。"""
    library = 'ssh_crypto' if stage == 'crypto' else 'rdp'
    suffix = 'ps1' if platform == 'windows' else 'sh'
    inputs = [ROOT / f'native/{library}/scripts/build.{suffix}']
    if stage == 'ffmpeg' and platform == 'windows':
        inputs.append(ROOT / 'native/rdp/scripts/build_ffmpeg_msvc.sh')
    if stage in ('rdp', 'crypto'):
        inputs += [ROOT / f'native/{library}/CMakeLists.txt']
        inputs += sorted((ROOT / f'native/{library}/src').rglob('*'))
    value = hashlib.sha256()
    for path in inputs:
        if path.is_file():
            value.update(str(path.relative_to(ROOT)).encode())
            value.update(path.read_bytes())
    value.update(platform.encode())
    if platform == 'windows':
        value.update(os.environ.get('VCToolsVersion', '').encode())
    return value.hexdigest()

def digest(path):
    """流式计算产物摘要，用于识别安装中断、空文件及后续损坏。"""
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def artifacts(platform, stage):
    """集中列出三个平台各阶段的必需库与头文件，避免以单个文件判断安装成功。"""
    windows = platform == 'windows'
    libraries = {
        'openssl': ['libcrypto', 'libssl'],
        'zlib': ['zlibstatic'],
        'ffmpeg': ['avcodec', 'swscale', 'avutil'],
        'freerdp': ['freerdp3', 'freerdp-client3', 'winpr3'],
    }
    headers = {
        'openssl': ['openssl/ssl.h', 'openssl/crypto.h'],
        'zlib': ['zlib.h', 'zconf.h'],
        'ffmpeg': ['libavcodec/avcodec.h', 'libswscale/swscale.h', 'libavutil/avutil.h'],
        'freerdp': ['freerdp3/freerdp/freerdp.h', 'winpr3/winpr/wtypes.h'],
    }
    if stage in ('rdp', 'crypto'):
        return [f'remlark_{stage}.dll' if windows else
                f'libremlark_{stage}.{"dylib" if platform == "macos" else "so"}']
    names = []
    for library in libraries[stage]:
        filename = f'{library}.lib' if windows else f'{library if library.startswith("lib") else "lib" + library}.a'
        names.append('prefix/lib/' + filename)
    names += ['prefix/include/' + name for name in headers[stage]]
    if stage == 'freerdp':
        names += ['prefix/remdesk-common.lib' if windows else 'prefix/lib/freerdp3/libremdesk-common.a']
    return names


def ready(output, platform, stage):
    """只有完整记录、预期文件集合与当前文件摘要一致才视为已完成。"""
    try:
        state = json.loads((output / '.completed' / f'{stage}.json').read_text(encoding='utf-8'))
        expected = artifacts(platform, stage)
        return (state['platform'] == platform and state['target'] == output.name
                and state['location'] == str(output.resolve())
                and state['recipe'] == recipe_signature(platform, stage)
                and set(state['files']) == set(expected)
                and all((output / name).is_file() and (output / name).stat().st_size > 0
                        and digest(output / name) == state['files'][name] for name in expected))
    except (FileNotFoundError, ValueError, KeyError, TypeError):
        return False


def mark(output, platform, stage):
    """检查全部产物后原子写入完成记录；失败前移除旧记录，禁止半安装被复用。"""
    folder = output / '.completed'
    folder.mkdir(parents=True, exist_ok=True)
    marker = folder / f'{stage}.json'
    marker.unlink(missing_ok=True)
    files = {}
    for name in artifacts(platform, stage):
        path = output / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f'Native stage {stage} is incomplete: {path}')
        files[name] = digest(path)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=folder, delete=False, mode='w', encoding='utf-8') as stream:
            temporary = Path(stream.name)
            json.dump({'platform': platform, 'target': output.name,
                       'location': str(output.resolve()),
                       'recipe': recipe_signature(platform, stage), 'files': files}, stream)
        temporary.replace(marker)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def begin(output, platform, stage):
    """重建前移除本阶段旧文件，避免半安装混入旧库或旧头文件后被误判为成功。"""
    (output / '.completed' / f'{stage}.json').unlink(missing_ok=True)
    for name in artifacts(platform, stage):
        (output / name).unlink(missing_ok=True)


def cache_status(root, platform, arch):
    """分别报告可保存的已完成依赖与完整双原生库；macOS 通用包要求两架构都完成。"""
    arches = ['x86_64', 'arm64'] if arch == 'universal' else [
        'x86_64' if arch == 'x64' else 'aarch64' if platform == 'linux' and arch == 'arm64' else arch]
    directories = [root / f'{platform}-{value}' for value in arches]
    dependencies = any(ready(folder, platform, stage) for folder in directories
                       for stage in ('openssl', 'ffmpeg', 'freerdp') + (('zlib',) if platform == 'windows' else ()))
    complete = all(ready(folder, platform, stage) for folder in directories
                   for stage in ('openssl', 'ffmpeg', 'freerdp', 'rdp', 'crypto')
                   + (('zlib',) if platform == 'windows' else ()))
    return dependencies, complete


def cache_identity(output, platform):
    """缓存同时绑定工作区、校验器版本及 MSVC，避免不可迁移的安装前缀反复命中。"""
    value = hashlib.sha256(Path(__file__).read_bytes())
    value.update(str(output.resolve()).encode())
    value.update(platform.encode())
    if platform == 'windows':
        value.update(os.environ.get('VCToolsVersion', '').encode())
    return value.hexdigest()[:24]


def main():
    """供三平台构建脚本与 Actions 读取状态，正常未完成返回 1，真实错误返回 2。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['ready', 'mark', 'begin', 'invalidate', 'cache-status', 'cache-identity'])
    parser.add_argument('output', type=Path)
    parser.add_argument('platform', choices=['windows', 'macos', 'linux'])
    parser.add_argument('stage', choices=['openssl', 'zlib', 'ffmpeg', 'freerdp', 'rdp', 'crypto'], nargs='?')
    parser.add_argument('--arch', choices=['x64', 'arm64', 'universal'])
    parser.add_argument('--github-output', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'cache-identity':
            if not args.github_output:
                parser.error('cache-identity requires --github-output')
            with args.github_output.open('a', encoding='utf-8') as stream:
                stream.write(f'identity={cache_identity(args.output, args.platform)}\n')
        elif args.command == 'cache-status':
            if not args.arch or not args.github_output:
                parser.error('cache-status requires --arch and --github-output')
            dependencies, complete = cache_status(args.output, args.platform, args.arch)
            with args.github_output.open('a', encoding='utf-8') as stream:
                stream.write(f'dependencies={str(dependencies).lower()}\ncomplete={str(complete).lower()}\n')
        elif not args.stage:
            parser.error('stage is required')
        elif args.command == 'ready':
            return 0 if ready(args.output, args.platform, args.stage) else 1
        elif args.command == 'mark':
            mark(args.output, args.platform, args.stage)
        elif args.command == 'begin':
            begin(args.output, args.platform, args.stage)
        else:
            (args.output / '.completed' / f'{args.stage}.json').unlink(missing_ok=True)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
