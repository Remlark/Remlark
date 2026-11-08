#!/usr/bin/env python3
"""CI 安装固定版本的 Flutter SDK：自托管 runner 缓存到工具目录跨任务复用，托管 runner 每次克隆到临时目录。"""

import argparse
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.retry_command import log, remove_path, run_with_retry

FLUTTER_REPOSITORY = 'https://github.com/flutter/flutter.git'


def sdk_location(environment, version):
    """返回 (SDK 目录, 是否持久缓存)；自托管机器的 RUNNER_TEMP 每个任务都会清空，改用工具缓存目录。"""
    tool_cache = environment.get('RUNNER_TOOL_CACHE')
    if environment.get('RUNNER_ENVIRONMENT') == 'self-hosted' and tool_cache:
        return Path(tool_cache) / 'flutter' / version, True
    return Path(environment['RUNNER_TEMP']) / 'flutter', False


def marker_path(directory):
    """完成标记放在 SDK 目录旁，不在 Flutter 仓库内留下未跟踪文件。"""
    return directory.with_name(directory.name + '.complete')


def is_ready(directory, version):
    """只有克隆完整且标记版本一致才复用，避免中断留下的半成品或版本混用。"""
    marker = marker_path(directory)
    return (marker.is_file() and marker.read_text(encoding='utf-8').strip() == version
            and (directory / 'bin').is_dir())


def prune_other_versions(directory):
    """持久缓存只保留当前版本，旧版本 SDK 及其引擎缓存会占用数 GB。"""
    for sibling in directory.parent.iterdir():
        if sibling.name in (directory.name, marker_path(directory).name):
            continue
        log(f'==> remove cached Flutter: {sibling}')
        remove_path(sibling)


def install(version, environment, runner=run_with_retry):
    """安装或复用 SDK 并返回目录；克隆最终失败时抛出 SystemExit 传递退出码。"""
    directory, persistent = sdk_location(environment, version)
    if persistent:
        directory.parent.mkdir(parents=True, exist_ok=True)
        prune_other_versions(directory)
        if is_ready(directory, version):
            log(f'==> reuse cached Flutter {version}: {directory}')
            return directory
    # 无标记的目录可能是上次中断的半成品，必须先清理再克隆。
    remove_path(marker_path(directory))
    remove_path(directory)
    code = runner(['git', 'clone', '--depth', '1', '--branch', version, FLUTTER_REPOSITORY, str(directory)],
                  clean=[directory])
    if code != 0:
        raise SystemExit(code)
    if persistent:
        marker_path(directory).write_text(version + '\n', encoding='utf-8')
    return directory


def main(argv=None):
    """命令行入口：安装后把 bin 目录追加到 GITHUB_PATH。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--github-path', type=Path, required=True)
    args = parser.parse_args(argv)
    directory = install(args.version, os.environ)
    with args.github_path.open('a', encoding='utf-8') as stream:
        stream.write(str(directory / 'bin') + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
