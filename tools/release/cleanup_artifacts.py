#!/usr/bin/env python3
"""Release 发布成功后删除本次运行的临时产物，不改动 Release 附件、缓存和其他运行。"""

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


def cleanup(api, run_id):
    """只删除当前运行的中转包；历史运行（含失败待重跑的）保留，由保留期或手动删除。"""
    artifacts = []
    page = 1
    # 先分页快照再删除，避免边删边翻页漏掉后续条目。
    while True:
        batch = api.request(f'runs/{run_id}/artifacts?per_page=100&page={page}')['artifacts']
        artifacts.extend(batch)
        if len(batch) < 100:
            break
        page += 1

    deleted_bytes = 0
    for artifact in artifacts:
        if not artifact['name'].startswith(('packages-', 'logs-')):
            continue
        api.request(f'artifacts/{artifact["id"]}', method='DELETE')
        deleted_bytes += artifact['size_in_bytes']
        print(f'Deleted Actions artifact: {artifact["name"]} ({artifact["size_in_bytes"]} bytes)')
    print(f'Deleted {deleted_bytes} bytes of temporary Actions artifacts')
    return deleted_bytes


def main():
    """仅使用工作流注入的 GitHub 上下文清理当前运行。"""
    api = ActionsApi(os.environ['GITHUB_REPOSITORY'], os.environ['GH_TOKEN'])
    cleanup(api, int(os.environ['GITHUB_RUN_ID']))


if __name__ == '__main__':
    main()
