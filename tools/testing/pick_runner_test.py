"""P-31：Release 自托管 macOS runner 在线选择与回退，不请求真实 GitHub。"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.release.pick_runner import choose
from tools.utils.actions_api import ActionsApi

LABEL = 'remlark-macmini'
FALLBACK = 'macos-15'


def runner(name, status, *labels):
    """构造与 GitHub runners 接口相同结构的条目。"""
    return {'name': name, 'status': status, 'busy': False,
            'labels': [{'name': label} for label in ('self-hosted', 'macOS', *labels)]}


def fake_api(pages):
    """用固定分页响应替换网络请求，记录请求路径。"""
    api = ActionsApi('owner/repo', 'token')
    api.calls = []

    def request(path, method='GET'):
        """按页码返回预设列表。"""
        api.calls.append(path)
        page = int(path.rsplit('page=', 1)[1])
        return {'runners': pages[page - 1]}

    api.request = request
    return api


class PickRunnerTests(unittest.TestCase):
    """在三个系统以隔离 API 响应验证选择结果。"""

    def test_online_label_selects_self_hosted(self):
        """带标签且在线（包括忙碌）时返回标签，作为 runs-on 使用。"""
        busy = runner('mac-mini', 'online', LABEL, 'ARM64')
        busy['busy'] = True
        api = fake_api([[runner('other', 'online', 'gpu'), busy]])
        self.assertEqual(choose([('repository', api)], LABEL, FALLBACK), LABEL)
        self.assertEqual(api.calls, ['runners?per_page=100&page=1'])

    def test_offline_or_unlabeled_falls_back(self):
        """机器离线、或在线机器没有该标签时回退托管 runner。"""
        api = fake_api([[runner('mac-mini', 'offline', LABEL), runner('other', 'online', 'gpu')]])
        self.assertEqual(choose([('repository', api)], LABEL, FALLBACK), FALLBACK)
        self.assertEqual(choose([('repository', fake_api([[]]))], LABEL, FALLBACK), FALLBACK)

    def test_label_found_on_second_page(self):
        """超过 100 台时继续翻页，不能只看第一页。"""
        first = [runner(f'r{i}', 'online', 'other') for i in range(100)]
        api = fake_api([first, [runner('mac-mini', 'online', LABEL)]])
        self.assertEqual(choose([('repository', api)], LABEL, FALLBACK), LABEL)
        self.assertEqual(len(api.calls), 2)

    def test_api_failure_or_missing_token_falls_back(self):
        """权限不足、网络失败或未配置令牌都不能让发布失败。"""
        api = ActionsApi('owner/repo', 'token')

        def request(path, method='GET'):
            """模拟令牌权限不足。"""
            raise RuntimeError('HTTP Error 403: Forbidden')

        api.request = request
        self.assertEqual(choose([('repository', api), ('organization', api)], LABEL, FALLBACK), FALLBACK)
        self.assertEqual(choose([], LABEL, FALLBACK), FALLBACK)

    def test_organization_runner_after_repository_failure(self):
        """仓库接口无权限或无匹配时继续查组织接口，组织级 runner 在线即使用。"""
        denied = ActionsApi('owner/repo', 'token')

        def request(path, method='GET'):
            """模拟令牌只有组织权限。"""
            raise RuntimeError('HTTP Error 403: Forbidden')

        denied.request = request
        org = fake_api([[runner('mac-mini', 'online', LABEL)]])
        self.assertEqual(choose([('repository', denied), ('organization', org)], LABEL, FALLBACK), LABEL)
        empty = fake_api([[]])
        self.assertEqual(choose([('repository', empty), ('organization', org)], LABEL, FALLBACK), LABEL)
        self.assertEqual(org.base, 'https://api.github.com/repos/owner/repo/actions/')
        self.assertEqual(ActionsApi('owner', 'token', scope='orgs').base,
                         'https://api.github.com/orgs/owner/actions/')

    def test_command_writes_github_output(self):
        """命令行入口未配置令牌时写入回退值，不访问网络。"""
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'output'
            env = {key: value for key, value in os.environ.items() if key != 'RUNNER_STATUS_TOKEN'}
            env['GITHUB_REPOSITORY'] = 'owner/repo'
            result = subprocess.run(
                [sys.executable, str(ROOT / 'tools/release/pick_runner.py'), '--label', LABEL,
                 '--fallback', FALLBACK, '--output-name', 'macos', '--github-output', str(output)],
                env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(encoding='utf-8'), f'macos={FALLBACK}\n')


if __name__ == '__main__':
    unittest.main()
