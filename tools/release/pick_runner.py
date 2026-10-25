#!/usr/bin/env python3
"""Release 开始前选择 macOS runner：自托管机器在线时使用它，否则回退 GitHub 托管 runner。"""

import argparse
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.actions_api import ActionsApi


def online_runner(runners, label):
    """返回带指定标签且在线的自托管 runner 名称；忙碌的也算在线，任务会排队等它。"""
    for runner in runners:
        labels = {item['name'] for item in runner.get('labels', [])}
        if label in labels and runner.get('status') == 'online':
            return runner['name']
    return None


def choose(api, label, fallback):
    """查询失败、没有令牌或机器离线都回退托管 runner，选择本身不能让发布失败。"""
    if api is None:
        print(f'::notice::RUNNER_STATUS_TOKEN not set, using {fallback}')
        return fallback
    try:
        runners = api.paged('runners', 'runners')
    except Exception as error:  # noqa: BLE001 网络、权限等任何错误都按离线处理
        print(f'::warning::Cannot query self-hosted runners ({error}), using {fallback}')
        return fallback
    name = online_runner(runners, label)
    if name is None:
        print(f'::notice::No online runner labeled {label}, using {fallback}')
        return fallback
    print(f'::notice::Using self-hosted runner {name} ({label})')
    return label


def main():
    """读取 Actions 环境，把选中的 runs-on 值写入 GITHUB_OUTPUT。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True, help='自托管 runner 的自定义标签')
    parser.add_argument('--fallback', required=True, help='自托管不可用时使用的托管 runner')
    parser.add_argument('--output-name', required=True, help='写入 GITHUB_OUTPUT 的键名')
    parser.add_argument('--github-output', type=Path, required=True)
    args = parser.parse_args()
    token = os.environ.get('RUNNER_STATUS_TOKEN', '')
    api = ActionsApi(os.environ['GITHUB_REPOSITORY'], token) if token else None
    selected = choose(api, args.label, args.fallback)
    with args.github_output.open('a', encoding='utf-8') as stream:
        stream.write(f'{args.output_name}={selected}\n')


if __name__ == '__main__':
    main()
