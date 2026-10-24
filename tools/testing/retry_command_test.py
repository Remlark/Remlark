"""P-28：CI 网络安装命令的有限重试、半成品清理与退出码传递，不访问网络。"""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.retry_command import run_with_retry

SCRIPT = ROOT / 'tools' / 'utils' / 'retry_command.py'


class RetryCommandTests(unittest.TestCase):
    """三平台用替身执行器及真实子进程验证重试行为。"""

    def test_retry_until_success_with_backoff_and_clean(self):
        """失败后指数退避并删除半成品目录，成功即停止。"""
        with tempfile.TemporaryDirectory() as temporary:
            partial = Path(temporary) / 'flutter'
            codes = iter([1, 2, 0])
            waits = []

            def runner(command):
                """每次运行前留下半成品，模拟克隆中断。"""
                self.assertFalse(partial.exists())
                partial.mkdir()
                (partial / 'half').write_text('x')
                return next(codes)

            # 每次重试前由工具删除上一轮半成品，runner 内断言目录已不存在。
            self.assertEqual(run_with_retry(['git', 'clone'], 3, 5, [partial], waits.append, runner), 0)
            self.assertEqual(waits, [5, 10])
            self.assertTrue(partial.exists())

    def test_first_attempt_keeps_existing_path(self):
        """首次执行前不清理，避免误删调用方已有内容。"""
        with tempfile.TemporaryDirectory() as temporary:
            existing = Path(temporary) / 'keep'
            existing.write_text('x')
            self.assertEqual(run_with_retry(['true'], 3, 0, [existing], lambda _: None, lambda _: 0), 0)
            self.assertTrue(existing.exists())

    def test_last_exit_code_is_returned(self):
        """全部失败时返回最后一次退出码，供 PowerShell 的 LASTEXITCODE 判断。"""
        codes = iter([4, 9])
        self.assertEqual(run_with_retry(['choco'], 2, 0, (), lambda _: None, lambda _: next(codes)), 9)

    def test_missing_command_fails_without_retry(self):
        """命令不存在是配置错误，立即返回 127。"""
        calls = []

        def runner(command):
            """记录调用次数并模拟启动失败。"""
            calls.append(command)
            raise FileNotFoundError('missing')

        self.assertEqual(run_with_retry(['missing-tool'], 3, 0, (), lambda _: None, runner), 127)
        self.assertEqual(len(calls), 1)

    def test_invalid_arguments(self):
        """非法次数、负间隔和空命令直接拒绝。"""
        for args in ((['x'], 0, 1), (['x'], 1, -1), ([], 1, 1)):
            with self.assertRaises(ValueError):
                run_with_retry(*args)

    def test_cli_real_process_and_option_passthrough(self):
        """真实子进程：保留目标命令自身的 --选项 和含空格参数，无论是否带 --。"""
        probe = 'import sys; print(sys.argv[1:]); sys.exit(0 if sys.argv[1:] == ["--yes", "/A:C:\\\\x y"] else 5)'
        for separator in (['--'], []):
            result = subprocess.run([sys.executable, str(SCRIPT), '--attempts', '2', '--delay', '0',
                                     *separator, sys.executable, '-c', probe, '--yes', '/A:C:\\x y'],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('attempt 1/2', result.stderr)
        failed = subprocess.run([sys.executable, str(SCRIPT), '--attempts', '2', '--delay', '0',
                                 '--', sys.executable, '-c', 'import sys; sys.exit(3)'],
                                capture_output=True, text=True)
        self.assertEqual(failed.returncode, 3)
        self.assertIn('attempt 2/2', failed.stderr)


if __name__ == '__main__':
    unittest.main()
