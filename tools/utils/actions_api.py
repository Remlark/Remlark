#!/usr/bin/env python3
"""GitHub Actions REST 请求封装，供 Release 工作流中的各脚本共用。"""

import json
import urllib.request


class ActionsApi:
    """统一封装 GitHub REST 请求，令牌只在认证头使用。"""

    def __init__(self, repository, token):
        """从 Actions 环境接收当前仓库及最小权限令牌。"""
        self.base = f'https://api.github.com/repos/{repository}/actions/'
        self.token = token

    def request(self, path, method='GET'):
        """获取 JSON 或执行删除；请求失败直接抛出，由调用方决定报错还是回退。"""
        request = urllib.request.Request(self.base + path, method=method, headers={
            'Authorization': f'Bearer {self.token}',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
        })
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response) if method == 'GET' else None

    def paged(self, path, key):
        """按 100 条一页取完整列表，先快照再返回，避免调用方边改边翻页漏项。"""
        items = []
        page = 1
        separator = '&' if '?' in path else '?'
        while True:
            batch = self.request(f'{path}{separator}per_page=100&page={page}')[key]
            items.extend(batch)
            if len(batch) < 100:
                return items
            page += 1
