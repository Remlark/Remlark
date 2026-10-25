"""P-28：CI Flutter SDK 安装位置、自托管缓存复用与半成品清理，不访问网络。"""

from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.flutter_sdk import install, marker_path, sdk_location


class FakeClone:
    """记录克隆命令并在目标目录生成 bin，模拟成功或失败。"""

    def __init__(self, code=0):
        """code 为模拟的最终退出码。"""
        self.code = code
        self.calls = []

    def __call__(self, command, clean=()):
        """与 run_with_retry 相同签名。"""
        self.calls.append((command, list(clean)))
        if self.code == 0:
            (Path(command[-1]) / 'bin').mkdir(parents=True)
        return self.code


class FlutterSdkTests(unittest.TestCase):
    """三平台以临时目录验证安装决策。"""

    def environment(self, root, self_hosted):
        """构造 Actions 环境变量。"""
        return {'RUNNER_TEMP': str(root / 'temp'), 'RUNNER_TOOL_CACHE': str(root / 'tool'),
                'RUNNER_ENVIRONMENT': 'self-hosted' if self_hosted else 'github-hosted'}

    def test_hosted_runner_clones_to_temp_every_time(self):
        """托管 runner 沿用临时目录，每次重新克隆，不写缓存标记。"""
        with tempfile.TemporaryDirectory() as directory:
            env = self.environment(Path(directory), False)
            clone = FakeClone()
            target = install('3.47.7', env, clone)
            self.assertEqual(target, Path(directory) / 'temp' / 'flutter')
            self.assertEqual(clone.calls[0][0][:6], ['git', 'clone', '--depth', '1', '--branch', '3.47.7'])
            self.assertEqual(clone.calls[0][1], [target])
            self.assertFalse(marker_path(target).exists())
            install('3.47.7', env, clone)
            self.assertEqual(len(clone.calls), 2)

    def test_self_hosted_reuses_complete_cache(self):
        """自托管首次克隆后写标记，后续任务直接复用，不再访问网络。"""
        with tempfile.TemporaryDirectory() as directory:
            env = self.environment(Path(directory), True)
            clone = FakeClone()
            target = install('3.47.7', env, clone)
            self.assertEqual(target, Path(directory) / 'tool' / 'flutter' / '3.47.7')
            self.assertEqual(marker_path(target).read_text(encoding='utf-8'), '3.47.7\n')
            self.assertEqual(install('3.47.7', env, clone), target)
            self.assertEqual(len(clone.calls), 1)

    def test_partial_cache_and_old_versions_are_replaced(self):
        """无标记的半成品重新克隆；升级版本后删除旧版本及其标记。"""
        with tempfile.TemporaryDirectory() as directory:
            env = self.environment(Path(directory), True)
            partial, _ = sdk_location(env, '3.47.7')
            (partial / 'bin').mkdir(parents=True)
            (partial / 'stale').write_text('x')
            clone = FakeClone()
            install('3.47.7', env, clone)
            self.assertEqual(len(clone.calls), 1)
            self.assertFalse((partial / 'stale').exists())
            upgraded = install('3.48.0', env, clone)
            self.assertEqual(sorted(p.name for p in upgraded.parent.iterdir()), ['3.48.0', '3.48.0.complete'])

    def test_failed_clone_leaves_no_marker(self):
        """克隆最终失败时传递退出码且不写标记，下次会重新安装。"""
        with tempfile.TemporaryDirectory() as directory:
            env = self.environment(Path(directory), True)
            with self.assertRaises(SystemExit) as raised:
                install('3.47.7', env, FakeClone(code=128))
            self.assertEqual(raised.exception.code, 128)
            target, _ = sdk_location(env, '3.47.7')
            self.assertFalse(marker_path(target).exists())


if __name__ == '__main__':
    unittest.main()
