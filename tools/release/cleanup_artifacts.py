#!/usr/bin/env python3
"""删除本发布工作流的临时产物，不改动 Release 附件、缓存和其他工作流。"""

import json
import os
import urllib.request


class ActionsApi:
    """统一封装 GitHub REST 请求，令牌只在认证头使用。"""

    def __init__(self, repository, token):
        """从 Actions 环境接收当前仓库及最小权限令牌。"""
        self.base = f'https://api.github.com/repos/{repository}/actions/'
        self.token = token

    def request(self, path, method='GET'):
        """获取 JSON 或执行删除；请求失败时让任务报错，避免假报清理成功。"""
        request = urllib.request.Request(self.base + path, method=method, headers={
            'Authorization': f'Bearer {self.token}',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
        })
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response) if method == 'GET' else None


def cleanup(api, current_run_id):
    """先分页快照再删除，保护并行运行、其他工作流和非本流程管理的文件。"""
    current = api.request(f'runs/{current_run_id}')
    runs = {int(current_run_id): current}
    artifacts = []
    page = 1
    while True:
        batch = api.request(f'artifacts?per_page=100&page={page}')['artifacts']
        artifacts.extend(batch)
        if len(batch) < 100:
            break
        page += 1

    deleted_bytes = 0
    for artifact in artifacts:
        if not artifact['name'].startswith(('packages-', 'logs-')):
            continue
        run_id = artifact.get('workflow_run', {}).get('id')
        if run_id is None:
            continue
        if run_id not in runs:
            runs[run_id] = api.request(f'runs/{run_id}')
        run = runs[run_id]
        if run['workflow_id'] != current['workflow_id']:
            continue
        # 当前运行的所有构建和发布任务已结束；历史运行必须整体完成才允许清理。
        if run_id != int(current_run_id) and run['status'] != 'completed':
            continue
        api.request(f'artifacts/{artifact["id"]}', method='DELETE')
        deleted_bytes += artifact['size_in_bytes']
        print(f'Deleted Actions artifact: {artifact["name"]} ({artifact["size_in_bytes"]} bytes)')
    print(f'Deleted {deleted_bytes} bytes of temporary Actions artifacts')
    return deleted_bytes


def main():
    """仅使用工作流注入的 GitHub 上下文执行清理。"""
    api = ActionsApi(os.environ['GITHUB_REPOSITORY'], os.environ['GH_TOKEN'])
    cleanup(api, int(os.environ['GITHUB_RUN_ID']))


if __name__ == '__main__':
    main()
