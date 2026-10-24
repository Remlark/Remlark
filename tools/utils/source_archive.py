"""原生依赖源码下载：校验完整 gzip/tar、重试与镜像回退，成功后原子替换。"""

import argparse
import gzip
import hashlib
import http.client
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import posixpath
import shutil
import tarfile
import tempfile
import subprocess
import sys
import time
import urllib.error
import urllib.request
import urllib.parse
import zlib

INVALID_ARCHIVE = (EOFError, ValueError, gzip.BadGzipFile, tarfile.TarError, zlib.error)
RETRYABLE = INVALID_ARCHIVE + (urllib.error.URLError, http.client.HTTPException,
                              ConnectionError, TimeoutError)


def log(message):
    """诊断日志无法用控制台代码页表示时转义，不能因此中止有效源码准备。"""
    try:
        print(message, flush=True)
    except UnicodeEncodeError:
        encoding = getattr(sys.stdout, 'encoding', None) or 'ascii'
        print(message.encode(encoding, errors='backslashreplace').decode(encoding), flush=True)


def file_digest(path):
    """流式计算摘要，避免把大源码包完整载入内存。"""
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def check_root(root):
    """源码根目录必须为单个相对目录名，禁止平台路径语义导致发布到其他位置。"""
    if (root in ('.', '..') or PurePosixPath(root).parts != (root,)
            or PurePosixPath(root).is_absolute() or PureWindowsPath(root).drive or '\\' in root):
        raise ValueError('Invalid source root')


def validate_archive(path, root, sha256=None):
    """验证校验和、完整 gzip CRC 及源码根目录，拒绝错误页或截断下载。"""
    check_root(root)
    if sha256:
        if file_digest(path) != sha256.lower():
            raise ValueError('SHA-256 mismatch')
    # 读至结尾检查 gzip 尾部 CRC；只读 tar 头不能发现末尾截断。
    with gzip.open(path, 'rb') as stream:
        while stream.read(1024 * 1024):
            pass
    with tarfile.open(path, 'r:gz') as archive:
        members = archive.getmembers()
        if not members:
            raise ValueError('Empty source archive')
        for member in members:
            if '\\' in member.name or PureWindowsPath(member.name).drive:
                raise ValueError('Invalid source archive path')
            parts = PurePosixPath(member.name).parts
            if not parts or parts[0] != root or '..' in parts:
                raise ValueError('Unexpected source archive root')
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise ValueError('Unsupported source archive entry')
            if member.issym() or member.islnk():
                if '\\' in member.linkname or PureWindowsPath(member.linkname).drive:
                    raise ValueError('Source archive link escapes root')
                target = (PurePosixPath(member.name).parent / member.linkname
                          if member.issym() else PurePosixPath(member.linkname))
                normalized = PurePosixPath(posixpath.normpath(str(target)))
                if not normalized.parts or normalized.parts[0] != root:
                    raise ValueError('Source archive link escapes root')


def download_archive(destination, urls, root, sha256=None, attempts=3):
    """每个来源有限次重试，验证通过才发布目标文件，不覆盖已有的有效下载。"""
    destination = Path(destination)
    # 参数错误不是网络瞬断，立即失败，不能反复请求错误地址。
    check_root(root)
    if attempts < 1:
        raise ValueError('Invalid source download arguments')
    if not urls or any(urllib.parse.urlparse(url).scheme not in ('http', 'https', 'file')
                       or (urllib.parse.urlparse(url).scheme != 'file' and not urllib.parse.urlparse(url).netloc)
                       for url in urls):
        raise ValueError('Invalid source URL')
    if sha256 and (len(sha256) != 64 or any(c not in '0123456789abcdefABCDEF' for c in sha256)):
        raise ValueError('Invalid SHA-256 value')
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file():
        try:
            validate_archive(destination, root, sha256)
            log(f'==> reuse verified archive {destination}')
            return
        except INVALID_ARCHIVE:
            pass
    failures = []
    for url in urls:
        for attempt in range(1, attempts + 1):
            log(f'==> download {url} (attempt {attempt}/{attempts})')
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(dir=destination.parent, suffix='.part', delete=False) as output:
                    temporary = Path(output.name)
                    request = urllib.request.Request(url, headers={
                        'Accept-Encoding': 'identity', 'User-Agent': 'Remlark-native-build',
                    })
                    with urllib.request.urlopen(request, timeout=60) as response:
                        deadline = time.monotonic() + 180
                        # read1 及时返回已到达的数据，持续慢速响应也受总时长预算约束。
                        read = getattr(response, 'read1', response.read)
                        while True:
                            if time.monotonic() >= deadline:
                                raise TimeoutError('Source download exceeded 180 seconds')
                            chunk = read(64 * 1024)
                            if time.monotonic() >= deadline:
                                raise TimeoutError('Source download exceeded 180 seconds')
                            if not chunk:
                                break
                            output.write(chunk)
                validate_archive(temporary, root, sha256)
                temporary.replace(destination)
                return
            except RETRYABLE as error:
                failures.append(f'{url}: {error}')
                log(f'==> source download rejected: {error}')
                # 永久 HTTP 错误直接尝试镜像，不在同一个 404/403 上消耗重试。
                if isinstance(error, urllib.error.HTTPError) and error.code not in (408, 429) and error.code < 500:
                    break
                if attempt < attempts:
                    time.sleep(min(2 ** attempt, 8))
            finally:
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
    raise RuntimeError('Cannot download valid source archive:\n' + '\n'.join(failures))


def source_ready(directory, root, required, sha256=None):
    """仅复用完整解压后写入完成记录且关键源码仍存在的目录。"""
    try:
        state = json.loads((directory / '.remlark-source.json').read_text(encoding='utf-8'))
        return (state['root'] == root and state['sha256'] == sha256
                and state['required'] == required
                and all((directory / name).is_file() and (directory / name).stat().st_size > 0
                        for name in required))
    except (FileNotFoundError, ValueError, KeyError, TypeError):
        return False


def prepare_source(destination, urls, root, required, sha256=None, tar='tar', attempts=3):
    """先在独立目录解压并验证，再替换源码；中断不会留下可被复用的半成品。"""
    check_root(root)
    if not required or any(PurePosixPath(name).is_absolute() or PureWindowsPath(name).drive
                           or '\\' in name or '..' in PurePosixPath(name).parts
                           for name in required):
        raise ValueError('Invalid required source paths')
    directory = destination.parent / root
    if source_ready(directory, root, required, sha256):
        return
    download_archive(destination, urls, root, sha256, attempts)
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix='.source-') as temporary:
        staging = Path(temporary)
        # Windows bsdtar 把参数转成 ANSI 代码页，中文路径会变成 ??；
        # 工作目录用 Unicode 传入，tar 只接收 ASCII 的相对文件名。
        # FFmpeg/FreeRDP 源码文件多，ARM runner 加上杀毒扫描时解压可能超过 2 分钟，上限 10 分钟。
        subprocess.run([tar, '-xzf', destination.name, '-C', staging.name],
                       cwd=destination.parent, check=True, timeout=600)
        prepared = staging / root
        if not all((prepared / name).is_file() and (prepared / name).stat().st_size > 0
                   for name in required):
            raise ValueError('Extracted source is incomplete')
        state = {'root': root, 'required': required, 'sha256': sha256}
        (prepared / '.remlark-source.json').write_text(json.dumps(state), encoding='utf-8')
        backup = staging / 'previous-source'
        if directory.exists():
            directory.replace(backup)
        try:
            prepared.replace(directory)
        except OSError:
            if backup.exists():
                backup.replace(directory)
            raise


def main():
    """为 PowerShell 和 POSIX 构建脚本提供相同参数接口，失败返回非零退出码。"""
    # Windows 非 UTF-8 控制台也必须能打印中文路径，日志编码不能让有效下载失败。
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='backslashreplace')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('urls', nargs='+')
    parser.add_argument('--root', required=True)
    parser.add_argument('--sha256')
    parser.add_argument('--extract', action='store_true')
    parser.add_argument('--required', action='append', default=[])
    parser.add_argument('--tar', default='tar')
    parser.add_argument('--attempts', type=int, default=3)
    args = parser.parse_args()
    try:
        if args.attempts < 1:
            raise ValueError('attempts must be positive')
        if args.extract:
            if not args.required:
                raise ValueError('Source extraction requires --required files')
            prepare_source(args.destination, args.urls, args.root, args.required,
                           args.sha256, args.tar, args.attempts)
        else:
            download_archive(args.destination, args.urls, args.root, args.sha256, args.attempts)
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
