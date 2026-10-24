"""P-24：Actions 存储清理范围、分页与失败保护，不请求真实 GitHub。"""

from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.release.cleanup_artifacts import cleanup


class ArtifactCleanupTests(unittest.TestCase):
    """在三个系统以隔离 API 响应验证远端删除范围。"""

    def test_pagination_and_protected_artifacts(self):
        """删除当前及历史临时包，保留并行任务、其他工作流和其他用途的产物。"""
        artifacts = [
            {'id': 1, 'name': 'packages-macos-universal', 'workflow_run': {'id': 1}, 'size_in_bytes': 10},
            {'id': 2, 'name': 'packages-server-linux-arm64', 'workflow_run': {'id': 2}, 'size_in_bytes': 20},
            {'id': 3, 'name': 'logs-windows-x64', 'workflow_run': {'id': 2}, 'size_in_bytes': 30},
            {'id': 4, 'name': 'packages-linux-x64', 'workflow_run': {'id': 3}, 'size_in_bytes': 40},
            {'id': 5, 'name': 'packages-other', 'workflow_run': {'id': 4}, 'size_in_bytes': 50},
            {'id': 6, 'name': 'unmanaged-backup', 'workflow_run': {'id': 2}, 'size_in_bytes': 60},
            {'id': 7, 'name': 'packages-orphan', 'size_in_bytes': 70},
        ]
        artifacts.extend({'id': i, 'name': 'unmanaged', 'size_in_bytes': 1} for i in range(8, 101))
        artifacts.append({'id': 101, 'name': 'packages-windows-arm64', 'workflow_run': {'id': 2}, 'size_in_bytes': 40})
        responses = {
            'runs/1': {'workflow_id': 9, 'status': 'in_progress'},
            'runs/2': {'workflow_id': 9, 'status': 'completed'},
            'runs/3': {'workflow_id': 9, 'status': 'in_progress'},
            'runs/4': {'workflow_id': 10, 'status': 'completed'},
            'artifacts?per_page=100&page=1': {'artifacts': artifacts[:100]},
            'artifacts?per_page=100&page=2': {'artifacts': artifacts[100:]},
        }
        calls = []

        def request(path, method='GET'):
            """记录 API 顺序，删除会修改列表，以检查分页快照避免漏项。"""
            calls.append((path, method))
            if method == 'DELETE':
                artifacts[:] = [item for item in artifacts if item['id'] != int(path.split('/')[1])]
                return None
            return responses[path]

        self.assertEqual(cleanup(Mock(request=request), 1), 100)
        self.assertEqual([path for path, method in calls if method == 'DELETE'],
                         ['artifacts/1', 'artifacts/2', 'artifacts/3', 'artifacts/101'])
        self.assertLess(calls.index(('artifacts?per_page=100&page=2', 'GET')),
                        calls.index(('artifacts/1', 'DELETE')))
        self.assertEqual(calls.count(('runs/2', 'GET')), 1)

    def test_api_failure_is_not_hidden(self):
        """权限或网络失败必须上报，不把清理失败当作成功。"""
        api = Mock()
        api.request.side_effect = RuntimeError('GitHub API unavailable')
        with self.assertRaisesRegex(RuntimeError, 'unavailable'):
            cleanup(api, 1)


if __name__ == '__main__':
    unittest.main()
