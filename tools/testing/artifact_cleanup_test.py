"""P-24：Actions 存储清理范围、分页与失败保护，不请求真实 GitHub。"""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.release.cleanup_artifacts import cleanup
from tools.utils.actions_api import ActionsApi


class ArtifactCleanupTests(unittest.TestCase):
    """在三个系统以隔离 API 响应验证远端删除范围。"""

    def test_only_current_run_is_cleaned(self):
        """分页快照后只删除当前运行的临时包，保留非托管文件，不查询或删除历史运行。"""
        artifacts = [
            {'id': 1, 'name': 'packages-macos-universal', 'size_in_bytes': 10},
            {'id': 2, 'name': 'packages-server-linux-arm64', 'size_in_bytes': 20},
            {'id': 3, 'name': 'logs-windows-x64', 'size_in_bytes': 30},
            {'id': 4, 'name': 'unmanaged-backup', 'size_in_bytes': 60},
        ]
        artifacts.extend({'id': i, 'name': 'unmanaged', 'size_in_bytes': 1} for i in range(5, 101))
        artifacts.append({'id': 101, 'name': 'packages-windows-arm64', 'size_in_bytes': 40})
        responses = {
            'runs/7/artifacts?per_page=100&page=1': {'artifacts': artifacts[:100]},
            'runs/7/artifacts?per_page=100&page=2': {'artifacts': artifacts[100:]},
        }
        calls = []

        def request(path, method='GET'):
            """记录 API 顺序，删除会修改列表，以检查分页快照避免漏项。"""
            calls.append((path, method))
            if method == 'DELETE':
                artifacts[:] = [item for item in artifacts if item['id'] != int(path.split('/')[1])]
                return None
            return responses[path]

        api = ActionsApi('owner/repo', 'token')
        api.request = request
        self.assertEqual(cleanup(api, 7), 100)
        self.assertEqual([path for path, method in calls if method == 'DELETE'],
                         ['artifacts/1', 'artifacts/2', 'artifacts/3', 'artifacts/101'])
        self.assertLess(calls.index(('runs/7/artifacts?per_page=100&page=2', 'GET')),
                        calls.index(('artifacts/1', 'DELETE')))
        # 不访问仓库级 artifacts 列表，失败待重跑的历史运行不可能被误删。
        self.assertTrue(all(path.startswith(('runs/7/', 'artifacts/')) for path, _ in calls))
        self.assertFalse(any(path.startswith('artifacts?') for path, _ in calls))

    def test_api_failure_is_not_hidden(self):
        """权限或网络失败必须上报，不把清理失败当作成功。"""
        def request(path, method='GET'):
            """模拟权限不足或网络中断。"""
            raise RuntimeError('GitHub API unavailable')

        api = ActionsApi('owner/repo', 'token')
        api.request = request
        with self.assertRaisesRegex(RuntimeError, 'unavailable'):
            cleanup(api, 1)


if __name__ == '__main__':
    unittest.main()
