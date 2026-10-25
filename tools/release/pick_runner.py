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


def choose(apis, label, fallback):
    """依次查询仓库级与组织级 runner，任一处在线即使用；全部失败或离线时回退托管 runner。

    apis 为 (范围名称, ActionsApi) 列表；为空表示未配置令牌。单个范围查询失败（如个人账号
    没有组织接口、令牌缺少组织权限）只记警告并继续，选择本身不能让发布失败。
    """
    if not apis:
        print(f'::notice::RUNNER_STATUS_TOKEN not set, using {fallback}')
        return fallback
    for scope, api in apis:
        try:
            runners = api.paged('runners', 'runners')
        except Exception as error:  # noqa: BLE001 网络、权限等任何错误都按该范围无可用 runner 处理
            print(f'::warning::Cannot query {scope} runners ({error})')
            continue
        name = online_runner(runners, label)
        if name is not None:
            print(f'::notice::Using self-hosted {scope} runner {name} ({label})')
            return label
    print(f'::notice::No online runner labeled {label}, using {fallback}')
    return fallback


def main():
    """读取 Actions 环境，把选中的 runs-on 值写入 GITHUB_OUTPUT。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True, help='自托管 runner 的自定义标签')
    parser.add_argument('--fallback', required=True, help='自托管不可用时使用的托管 runner')
    parser.add_argument('--output-name', required=True, help='写入 GITHUB_OUTPUT 的键名')
    parser.add_argument('--github-output', type=Path, required=True)
    args = parser.parse_args()
    token = os.environ.get('RUNNER_STATUS_TOKEN', '')
    repository = os.environ['GITHUB_REPOSITORY']
    apis = []
    if token:
        # 仓库接口不包含组织级 runner，组织仓库需再查组织接口；个人账号的组织接口返回 404 后忽略
        apis = [('repository', ActionsApi(repository, token)),
                ('organization', ActionsApi(repository.split('/')[0], token, scope='orgs'))]
    selected = choose(apis, args.label, args.fallback)
    with args.github_output.open('a', encoding='utf-8') as stream:
        stream.write(f'{args.output_name}={selected}\n')


if __name__ == '__main__':
    main()
