#!/usr/bin/env python3
"""CI 网络安装命令的有限重试：三平台共用，失败前清理半成品，最终返回原退出码。"""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import time


def log(message):
    """输出到标准错误，非 UTF-8 控制台也不能因日志编码失败而中止。"""
    try:
        print(message, file=sys.stderr, flush=True)
    except UnicodeEncodeError:
        encoding = getattr(sys.stderr, 'encoding', None) or 'ascii'
        print(message.encode(encoding, errors='backslashreplace').decode(encoding),
              file=sys.stderr, flush=True)


def remove_path(path):
    """删除上一轮留下的目录或文件；不存在视为已清理，删除失败直接上报。"""
    path = Path(path)
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def resolve_command(command):
    """Windows 上 choco 等可能是 .cmd/.bat，先按 PATH 解析为完整路径再启动。"""
    executable = shutil.which(command[0])
    return [executable or command[0]] + list(command[1:])


def run_with_retry(command, attempts=3, delay=10, clean=(), sleep=time.sleep, runner=subprocess.call):
    """最多执行 attempts 次，间隔指数退避；每次重试前删除 clean 路径，返回最后一次退出码。"""
    if attempts < 1 or delay < 0 or not command:
        raise ValueError('Invalid retry arguments')
    resolved = resolve_command(command)
    code = 1
    for attempt in range(1, attempts + 1):
        if attempt > 1:
            # 半克隆的仓库等残留会让下一次直接失败，必须先清掉。
            for path in clean:
                remove_path(path)
        log(f'==> run (attempt {attempt}/{attempts}): {" ".join(command)}')
        try:
            code = runner(resolved)
        except OSError as error:
            # 找不到命令属于配置错误，重试不会恢复，立即失败。
            log(f'==> cannot start command: {error}')
            return 127
        if code == 0:
            return 0
        log(f'==> command failed with exit code {code}')
        if attempt < attempts:
            wait = min(delay * 2 ** (attempt - 1), 120)
            log(f'==> retry in {wait} seconds')
            sleep(wait)
    return code


def main(argv=None):
    """命令行入口：retry_command.py [--attempts N] [--delay S] [--clean PATH]... -- 命令 参数..."""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='backslashreplace')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--attempts', type=int, default=3)
    parser.add_argument('--delay', type=float, default=10)
    parser.add_argument('--clean', action='append', default=[])
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('missing command')
    try:
        return run_with_retry(command, args.attempts, args.delay, args.clean)
    except ValueError as error:
        parser.error(str(error))


if __name__ == '__main__':
    sys.exit(main())
