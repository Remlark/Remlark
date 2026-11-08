#!/usr/bin/env python3
"""预取 sqlite3 构建钩子的预编译库：三平台共用，按钩子缓存布局放入共享输出目录。

sqlite3 钩子从 github.com/.../releases/download 下载预编译库，但不检查 HTTP 状态；
该入口返回 5xx 时，错误页会被当作库文件并报“哈希不符”。钩子在共享输出目录已有
哈希正确的文件时直接复用，因此这里先经 GitHub API 资产接口（失败再回退普通下载地址）
取得文件、校验哈希后放入缓存，钩子便不再访问故障入口。
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import sys
from urllib.parse import unquote, urlparse
import urllib.error
import urllib.request
from urllib.request import url2pathname

REPOSITORY = 'simolus3/sqlite3.dart'
API_RELEASE = 'https://api.github.com/repos/{repo}/releases/tags/{tag}'
BROWSER_DOWNLOAD = 'https://github.com/{repo}/releases/download/{tag}/{name}'
USER_AGENT = 'Remlark CI sqlite3 asset prefetch'
TIMEOUT = 60

# 钩子使用的系统名与 Dart 的 Architecture 名称。
OS_NAMES = ('linux', 'macos', 'windows')
ARCH_ALIASES = {
    'x86_64': 'x64', 'amd64': 'x64', 'x64': 'x64',
    'aarch64': 'arm64', 'arm64': 'arm64',
}


def log(message):
    """输出到标准错误，非 UTF-8 控制台也不因编码失败中止。"""
    try:
        print(message, file=sys.stderr, flush=True)
    except UnicodeEncodeError:
        encoding = getattr(sys.stderr, 'encoding', None) or 'ascii'
        print(message.encode(encoding, errors='backslashreplace').decode(encoding),
              file=sys.stderr, flush=True)


def host_os():
    """当前宿主对应的钩子系统名。"""
    if sys.platform == 'darwin':
        return 'macos'
    if sys.platform.startswith('win'):
        return 'windows'
    return 'linux'


def normalize_archs(machine):
    """把 platform.machine() 或矩阵架构统一为钩子架构名列表；universal 为 macOS 双架构。"""
    if machine.lower() == 'universal':
        return ['x64', 'arm64']
    arch = ARCH_ALIASES.get(machine.lower())
    if arch is None:
        raise ValueError(f'Unsupported architecture: {machine}')
    return [arch]


def asset_name(os_name, arch):
    """GitHub Release 中预编译库的附件名，与钩子 sourceFilename 一致。"""
    return {
        'linux': f'libsqlite3.{arch}.linux.so',
        'macos': f'libsqlite3.{arch}.macos.dylib',
        'windows': f'sqlite3.{arch}.windows.dll',
    }[os_name]


def library_file_name(os_name):
    """钩子在缓存目录中保存的文件名（与 libraryFileName 一致）。"""
    return {'linux': 'libsqlite3.so', 'macos': 'libsqlite3.dylib',
            'windows': 'sqlite3.dll'}[os_name]


def uri_to_path(uri, base):
    """把 package_config 中的 rootUri（file:// 或相对路径）转为本地路径。"""
    parsed = urlparse(uri)
    if parsed.scheme == 'file':
        # Windows 上 file:///C:/x 需要 url2pathname 去掉前导斜杠。
        return Path(url2pathname(unquote(parsed.path)))
    return (Path(base) / unquote(uri)).resolve()


def sqlite3_package_root(project):
    """从 .dart_tool/package_config.json 定位锁定版本的 sqlite3 包目录。"""
    config_dir = Path(project) / '.dart_tool'
    config = json.loads((config_dir / 'package_config.json').read_text(encoding='utf-8'))
    for package in config['packages']:
        if package['name'] == 'sqlite3':
            return uri_to_path(package['rootUri'], config_dir)
    raise ValueError(f'sqlite3 is not a dependency of {project}')


def parse_asset_hashes(text):
    """解析钩子的 asset_hashes.dart，返回 (releaseTag, {附件名: sha256})。"""
    tag = re.search(r"releaseTag\s*=\s*'([^']+)'", text)
    hashes = dict(re.findall(r"'([^']+)':\s*'([0-9a-f]{64})'", text))
    if tag is None or not hashes:
        raise ValueError('Cannot parse sqlite3 asset hashes')
    return tag.group(1), hashes


def cache_path(project, os_name, expected_hash):
    """钩子共享输出目录中的目标文件：download-<哈希前 8 位>/<库文件名>。"""
    return (Path(project) / '.dart_tool' / 'hooks_runner' / 'shared' / 'sqlite3'
            / 'build' / f'download-{expected_hash[:8]}' / library_file_name(os_name))


def sha256_file(path):
    """计算文件 SHA-256。"""
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """资产接口带令牌请求时不自动跳转，避免把令牌发给对象存储。"""

    def redirect_request(self, *args, **kwargs):
        """返回 None 让 urllib 把 3xx 作为 HTTPError 抛出。"""
        return None


def http_get(url, headers=None, follow=True):
    """GET 请求：非 2xx 抛出异常；follow=False 时 3xx 返回 ('redirect', 地址)。"""
    request = urllib.request.Request(url, headers={'User-Agent': USER_AGENT, **(headers or {})})
    opener = urllib.request.build_opener() if follow else urllib.request.build_opener(_NoRedirect)
    try:
        with opener.open(request, timeout=TIMEOUT) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        if not follow and error.code in (301, 302, 303, 307, 308):
            return ('redirect', error.headers['Location'])
        raise


def api_source(tag, name, get=http_get, token=None):
    """经 GitHub API 查找附件并下载；令牌只用于 api.github.com，跳转后不携带。"""
    auth = {'Authorization': f'Bearer {token}'} if token else {}
    release = json.loads(get(API_RELEASE.format(repo=REPOSITORY, tag=tag),
                             {'Accept': 'application/vnd.github+json', **auth}))
    asset = next((item for item in release.get('assets', []) if item['name'] == name), None)
    if asset is None:
        raise ValueError(f'{name} is missing from release {tag}')
    result = get(asset['url'], {'Accept': 'application/octet-stream', **auth}, follow=False)
    if isinstance(result, tuple):
        return get(result[1])
    return result


def browser_source(tag, name, get=http_get, token=None):
    """钩子默认使用的普通下载地址，作为回退。"""
    return get(BROWSER_DOWNLOAD.format(repo=REPOSITORY, tag=tag, name=name))


SOURCES = (('GitHub API', api_source), ('release download', browser_source))


def prefetch(project, os_name, arch, get=http_get, token=None, sources=None):
    """确保缓存中有哈希正确的库：已存在则跳过，否则依次尝试各来源（默认 SOURCES），全部失败抛出异常。"""
    sources = SOURCES if sources is None else sources
    tag, hashes = parse_asset_hashes(
        (sqlite3_package_root(project) / 'lib' / 'src' / 'hook' / 'asset_hashes.dart')
        .read_text(encoding='utf-8'))
    name = asset_name(os_name, arch)
    expected = hashes.get(name)
    if expected is None:
        raise ValueError(f'No known hash for {name} in {tag}')
    target = cache_path(project, os_name, expected)
    if target.is_file() and sha256_file(target) == expected:
        log(f'==> {name} already cached at {target}')
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + '.prefetch')
    errors = []
    for label, source in sources:
        try:
            data = source(tag, name, get=get, token=token)
            actual = hashlib.sha256(data).hexdigest()
            if actual != expected:
                # 网关错误页等内容哈希不同，不能写入缓存。
                raise ValueError(f'sha256 {actual} ({len(data)} bytes), expected {expected}')
            temporary.write_bytes(data)
            os.replace(temporary, target)
            log(f'==> {name} from {label} -> {target}')
            return target
        except Exception as error:  # noqa: BLE001 - 记录后尝试下一个来源
            errors.append(f'{label}: {error}')
            log(f'==> {name} via {label} failed: {error}')
        finally:
            if temporary.exists():
                temporary.unlink()
    raise RuntimeError(f'Cannot fetch {name}: ' + '; '.join(errors))


def main(argv=None):
    """命令行入口：sqlite_assets.py 项目目录 [--os 系统] [--arch 架构|universal]...（需先 pub get）。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project')
    parser.add_argument('--os', choices=OS_NAMES, default=host_os())
    parser.add_argument('--arch', action='append', default=[])
    args = parser.parse_args(argv)
    try:
        archs = [arch for value in (args.arch or [platform.machine()])
                 for arch in normalize_archs(value)]
    except ValueError as error:
        parser.error(str(error))
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    try:
        for arch in archs:
            prefetch(args.project, args.os, arch, token=token)
    except Exception as error:  # noqa: BLE001 - 命令行统一以退出码上报
        log(f'==> {error}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
