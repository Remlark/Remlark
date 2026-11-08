#!/usr/bin/env python3
"""Release 发布成功后删除本次运行的临时产物，不改动 Release 附件、缓存和其他运行。"""

import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.actions_api import ActionsApi


def cleanup(api, run_id):
    """只删除当前运行的中转包；历史运行（含失败待重跑的）保留，由保留期或手动删除。"""
    # 先分页快照再删除，避免边删边翻页漏掉后续条目。
    artifacts = api.paged(f'runs/{run_id}/artifacts', 'artifacts')

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
