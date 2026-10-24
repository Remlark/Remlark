"""P-22：三平台构建保护，验证路径判定、检查失败保护和真实运行进程。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils import app_version
from tools.utils import build_guard as guard
from tools.utils.build_guard.inspector import GuardError, ProcessInspector, run_query
from tools.utils.build_guard.macos import MacosInspector
from tools.utils.build_guard.linux import LinuxInspector
from tools.utils.build_guard.windows import WindowsInspector


class FixedInspector(ProcessInspector):
    """给公共保护逻辑提供固定的进程列表，覆盖非当前宿主平台。"""

    def __init__(self, rows):
        """保存隔离测试数据，不访问系统进程。"""
        self.rows = rows

    def executables(self):
        """按统一接口返回进程列表。"""
        return self.rows


class BuildGuardTests(unittest.TestCase):
    """每个平台均执行同一批纯逻辑用例及当前平台的真实进程验证。"""

    def test_desktop_targets(self):
        """三个构建目标和不同 run 参数均走保护，移动平台不误触发。"""
        for platform in guard.PLATFORMS:
            for arguments in [['build', platform], ['run', '-d', platform],
                              ['run', f'--device-id={platform}'], ['run', f'-d={platform}']]:
                self.assertEqual(guard.target_platform(arguments), platform)
        self.assertEqual(guard.target_platform(['run']), guard.current_platform())
        self.assertIsNone(guard.target_platform(['build', 'apk']))
        self.assertIsNone(guard.target_platform(['run', '-d', 'android-device']))

    def test_platform_paths_and_unrelated_apps(self):
        """匹配当前检出目录的全部架构/模式，排除已安装应用、独立副本和前缀碰撞。"""
        with tempfile.TemporaryDirectory(prefix='remlark guard 中文 ') as directory:
            root = Path(directory)
            for platform, tail in [('macos', 'Build/Products/Debug/remlark.app/Contents/MacOS/remlark'),
                                   ('linux', 'arm64/release/bundle/remlark')]:
                running = str(root / 'build' / platform / tail)
                independent = str(root / 'build/validation/copy' / 'remlark')
                others = ['/Applications/remlark.app/Contents/MacOS/remlark', '/opt/remlark/remlark',
                          str(root / 'build' / (platform + '-other') / 'remlark'), independent]
                matches = guard.conflicting_processes(root, platform, [(99, running)] + list(enumerate(others)))
                self.assertEqual(matches, [(99, running)])
                with self.assertRaisesRegex(GuardError, 'PID 99'):
                    guard.assert_safe(root, platform, FixedInspector([(99, running)]), root / 'build')
                guard.assert_safe(root, platform, FixedInspector(list(enumerate(others))), root / 'build')
        rows = [(1, r'C:\工程\Remlark\build\WINDOWS\x64\runner\Debug\REMLARK.EXE'),
                (2, r'C:\工程\Remlark\build\windows-other\remlark.exe'),
                (3, r'C:\Program Files\Remlark\remlark.exe')]
        self.assertEqual(guard.conflicting_processes(r'C:\工程\Remlark', 'windows', rows), rows[:1])

    def test_custom_build_and_symlink_paths(self):
        """自定义输出与符号链接均不能绕过路径检查。"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = root / 'custom output'
            running = build / 'macos/Debug/remlark'
            self.assertEqual(guard.conflicting_processes(root, 'all', [(4, str(running))], build), [(4, str(running))])
            if sys.platform != 'win32':
                build.mkdir()
                alias = root / 'alias'
                alias.symlink_to(build, target_is_directory=True)
                self.assertEqual(guard.conflicting_processes(root, 'macos', [(4, str(alias / 'macos/Debug/remlark'))], build), [(4, str(alias / 'macos/Debug/remlark'))])

    def test_macos_process_output(self):
        """macOS ps 结果包含空格与中文时仍保留完整路径，坏结果拒绝构建。"""
        path = '/Users/test/代码/my project/build/macos/Debug/remlark'
        with patch.dict(os.environ, {'LC_ALL': 'C'}):
            with patch('tools.utils.build_guard.macos.run_query', return_value=f'  123 {path}\n  12 /bin/sleep\n') as query:
                self.assertEqual(MacosInspector().executables(), [(123, path)])
                self.assertEqual(query.call_args.kwargs['environment']['LC_ALL'], 'en_US.UTF-8')
                self.assertEqual(os.environ['LC_ALL'], 'C')
        with patch('tools.utils.build_guard.macos.run_query', return_value='bad output'):
            with self.assertRaises(GuardError):
                MacosInspector().executables()

    def test_linux_deleted_and_exited_processes(self):
        """Linux 去掉 deleted 标记仍能识别被替换的应用，并处理枚举后退出。"""
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            for pid in ['123', '456', '789']:
                (proc / pid).mkdir()
            def readlink(path):
                """按 PID 提供结果，不依赖文件系统的枚举顺序。"""
                pid = path.parent.name
                if pid == '789':
                    raise FileNotFoundError()
                return '/project/build/linux/x64/debug/bundle/remlark (deleted)' if pid == '123' else '/usr/bin/python3'

            with patch('tools.utils.build_guard.linux.os.readlink', side_effect=readlink):
                self.assertEqual(LinuxInspector(proc).executables(), [
                    (123, '/project/build/linux/x64/debug/bundle/remlark')])

    def test_linux_unreadable_application(self):
        """Linux 同名应用的路径无法读取时停止，而非误报无运行实例。"""
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            (proc / '123').mkdir()
            (proc / '123/comm').write_text('remlark')
            with patch('tools.utils.build_guard.linux.os.readlink', side_effect=PermissionError()):
                with self.assertRaises(GuardError):
                    LinuxInspector(proc).executables()

    def test_windows_process_output(self):
        """Windows 单条、多条、空列表与无法读取路径的结果都有确定行为。"""
        row = {'ProcessId': 42, 'ExecutablePath': r'C:\测试目录\remlark.exe'}
        for data in [row, [row]]:
            with patch('tools.utils.build_guard.windows.run_query', return_value=json.dumps(data)):
                self.assertEqual(WindowsInspector().executables(), [(42, row['ExecutablePath'])])
        for data in ['', '[]']:
            with patch('tools.utils.build_guard.windows.run_query', return_value=data):
                self.assertEqual(WindowsInspector().executables(), [])
        for data in ['null', 'bad', '[{"ProcessId":42,"ExecutablePath":null}]']:
            with patch('tools.utils.build_guard.windows.run_query', return_value=data):
                with self.assertRaises(GuardError):
                    WindowsInspector().executables()

    def test_query_errors_stop_build(self):
        """命令失败和超时都不得被当成没有运行实例，不泄漏查询输出。"""
        environment = dict(os.environ, LC_ALL='en_US.UTF-8')
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, 'result', '')) as query:
            self.assertEqual(run_query(['probe'], environment=environment), 'result')
            self.assertEqual(query.call_args.kwargs['env'], environment)
        for error in [FileNotFoundError(), subprocess.TimeoutExpired('ps', 10)]:
            with patch('subprocess.run', side_effect=error):
                with self.assertRaises(GuardError):
                    run_query(['probe'])
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 1, 'private', 'private')):
            with self.assertRaisesRegex(GuardError, 'build cancelled') as raised:
                run_query(['probe'])
            self.assertNotIn('private', str(raised.exception))

    def test_wrapper_stops_before_flutter(self):
        """构建保护失败时不查找或启动 Flutter，避免先覆盖文件再报错。"""
        with patch.object(app_version, 'read_version', return_value={}), \
                patch.object(app_version, 'assert_safe', side_effect=GuardError('blocked')) as checked, \
                patch.object(app_version.shutil, 'which') as lookup:
            for target in guard.PLATFORMS:
                with self.assertRaises(GuardError):
                    app_version.run_flutter(['build', target])
            self.assertEqual(checked.call_count, 3)
            lookup.assert_not_called()

    def test_configured_build_directory(self):
        """只读 Flutter 配置中的自定义目录，未知或非法配置拒绝构建。"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / '.flutter_settings'
            with patch('tools.utils.build_guard.Path.home', return_value=root), patch.dict(os.environ, {'APPDATA': str(root)}):
                config.write_text(json.dumps({'build-dir': 'build with spaces'}))
                self.assertEqual(guard.configured_build_directory(root), root / 'build with spaces')
                config.write_text('{broken')
                with self.assertRaises(GuardError):
                    guard.configured_build_directory(root)

    def test_real_current_platform_process(self):
        """启动本平台的隔离可执行文件，验证存活时拒绝、退出后允许；不接触用户应用。"""
        platform = guard.current_platform()
        with tempfile.TemporaryDirectory(prefix='remlark live 中文 ') as directory:
            root = Path(directory)
            target = root / 'build' / platform / ('remlark.exe' if platform == 'windows' else 'remlark')
            target.parent.mkdir(parents=True)
            ready = root / 'ready'
            env = os.environ.copy()
            if platform == 'macos':
                # 在本机编译普通程序，避免 ARM64 杀死被复制并重签的 Apple 系统二进制。
                source = ROOT / 'test/platform/fixtures/build_guard_probe.c'
                subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-Werror',
                                str(source), '-o', str(target)],
                               check=True, capture_output=True, timeout=30)
                arguments = [str(target), str(ready)]
            else:
                # Linux 的 sleep 可能来自多入口 coreutils，改名后不能启动；Windows 同样复用 Python。
                shutil.copy2(sys.executable, target)
                env['PYTHONHOME'] = sys.base_prefix
                if platform == 'windows':
                    env['PATH'] = str(Path(sys.executable).parent) + os.pathsep + env.get('PATH', '')
                arguments = [str(target), '-c',
                             'import pathlib,sys,time; '
                             'pathlib.Path(sys.argv[1]).write_text("ready", encoding="utf-8"); '
                             'time.sleep(30)', str(ready)]
            process = subprocess.Popen(arguments, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            try:
                # 三平台等待实际启动就绪，避免固定延迟受 runner 负载影响。
                deadline = time.monotonic() + 10
                while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertIsNone(process.poll(), process.stderr.read() if process.poll() is not None else '')
                self.assertTrue(ready.exists(), f'测试进程未在 10 秒内就绪：{target}')
                # 三平台均检查默认及 C locale，确保中文路径不因调用方语言环境漏检。
                for overrides in [{}, {'LC_ALL': 'C'}]:
                    with patch.dict(os.environ, overrides):
                        with self.assertRaisesRegex(GuardError, f'PID {process.pid}'):
                            guard.assert_safe(root, platform, build_directory=root / 'build')
                self.assertIsNone(process.poll(), '保护不得终止进程')
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
                process.stderr.close()
            guard.assert_safe(root, platform, build_directory=root / 'build')

    def test_build_and_clean_entry_points(self):
        """清理、Windows 启动和三平台统一构建入口均保留保护。"""
        makefile = (ROOT / 'Makefile').read_text(encoding='utf-8')
        self.assertIn('guard all\n\tflutter clean', makefile)
        windows = (ROOT / 'windows/run.ps1').read_text(encoding='utf-8-sig')
        self.assertLess(windows.index('guard windows'), windows.index('flutter pub get'))
        for platform in guard.PLATFORMS:
            self.assertIn(f'app_version.py flutter build {platform}', makefile)


if __name__ == '__main__':
    unittest.main()
