#!/usr/bin/env python3
"""同步服务端的三平台双架构打包、原生库校验及解包启动验证。"""

import argparse
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.app_version import read_version

# 同一份发布接口描述三个平台的可执行文件、SQLite 库和归档格式。
TARGETS = {
    'macos': ('server', 'libsqlite3.dylib', 'gztar'),
    'linux': ('server', 'libsqlite3.so', 'gztar'),
    'windows': ('server.exe', 'sqlite3.dll', 'zip'),
}


def binary_arch(path, target):
    """读取原生文件头，防止将错误平台或架构的主程序/SQLite 库上传。"""
    with path.open('rb') as stream:
        header = stream.read(64)
        if target == 'macos' and header[:4] == b'\xcf\xfa\xed\xfe':
            machine = struct.unpack_from('<I', header, 4)[0]
            return {0x01000007: 'x64', 0x0100000C: 'arm64'}.get(machine)
        if target == 'linux' and header[:6] == b'\x7fELF\x02\x01':
            machine = struct.unpack_from('<H', header, 18)[0]
            return {62: 'x64', 183: 'arm64'}.get(machine)
        if target == 'windows' and header[:2] == b'MZ' and len(header) == 64:
            stream.seek(struct.unpack_from('<I', header, 60)[0])
            pe = stream.read(6)
            if pe[:4] == b'PE\0\0' and len(pe) == 6:
                return {0x8664: 'x64', 0xAA64: 'arm64'}.get(struct.unpack_from('<H', pe, 4)[0])
    return None


def package(root, target, arch):
    """校验完整 bundle，按 VERSION、系统和架构命名，保留 bin/lib 相对布局。"""
    executable, library, archive_format = TARGETS[target]
    bundle = root / 'dist/Remlark-sync-server/bundle'
    for path in (bundle / 'bin' / executable, bundle / 'lib' / library):
        if not path.is_file() or path.stat().st_size < 64:
            raise ValueError(f'missing or empty server asset: {path}')
        if binary_arch(path, target) != arch:
            raise ValueError(f'wrong platform or architecture: {path}; expected {target}-{arch}')
    base = root / 'dist' / f'Remlark-sync-server-{read_version(root)["name"]}-{target}-{arch}'
    return Path(shutil.make_archive(str(base), archive_format, root_dir=bundle.parent, base_dir='bundle'))


def smoke(archive, target):
    """在独立目录解压并启动发布包，真实读写 SQLite，确保包不依赖构建目录。"""
    with tempfile.TemporaryDirectory(prefix='remlark server 中文 ') as directory:
        stage = Path(directory)
        shutil.unpack_archive(str(archive), stage)
        executable = stage / 'bundle/bin' / TARGETS[target][0]
        # Windows zip 不携带 POSIX 执行位；POSIX tar 包应原样保留，不在这里补权限。
        log_path = stage / 'server.log'
        with log_path.open('w', encoding='utf-8') as log:
            process = subprocess.Popen(
                [str(executable), '--host', '127.0.0.1', '--port', '0',
                 '--token', 'ci-smoke', '--db', str(stage / 'data/sync.sqlite')],
                cwd=stage, stdout=log, stderr=subprocess.STDOUT,
            )
            try:
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    output = log_path.read_text(encoding='utf-8')
                    match = re.search(r'http://127\.0\.0\.1:(\d+)', output)
                    if match:
                        break
                    if process.poll() is not None:
                        raise RuntimeError(f'server exited: {output}')
                    time.sleep(0.1)
                else:
                    raise RuntimeError(f'server startup timed out: {output}')

                base = f'http://127.0.0.1:{match[1]}/api/v1/items'

                def request(url, method='GET', body=None):
                    """通过回环地址访问真实发布进程，不使用外部代理。"""
                    data = json.dumps(body).encode() if body is not None else None
                    req = urllib.request.Request(url, data=data, method=method, headers={
                        'Authorization': 'Bearer ci-smoke', 'Content-Type': 'application/json',
                    })
                    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                    with opener.open(req, timeout=15) as response:
                        return json.load(response)

                if request(base) != {'items': []}:
                    raise RuntimeError('new database is not empty')
                request(base + '/ci-host', 'PUT', {'updatedAt': 1, 'payload': 'ci-cipher'})
                result = request(base + '/batch-get', 'POST', {'uuids': ['ci-host']})
                if result['items'][0]['payload'] != 'ci-cipher':
                    raise RuntimeError('SQLite round trip failed')
            finally:
                if process.poll() is None:
                    process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def main():
    """提供 CI 与本地一致的打包入口，冒烟验证失败时立即退出。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=TARGETS)
    parser.add_argument('arch', choices=('x64', 'arm64'))
    parser.add_argument('--smoke', action='store_true')
    args = parser.parse_args()
    archive = package(ROOT, args.platform, args.arch)
    if args.smoke:
        smoke(archive, args.platform)
    print(archive)


if __name__ == '__main__':
    main()
