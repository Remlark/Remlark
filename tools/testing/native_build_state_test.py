"""P-27：阶段断点、完整性、缓存分离及低成本工具链预检查回归，不构建产品。"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.native_build_state import artifacts, begin, cache_identity, cache_status, mark, ready


class NativeBuildStateTests(unittest.TestCase):
    """用隔离文件模拟安装成功、残缺、损坏与跨架构恢复，不调用原生编译器。"""

    def setUp(self):
        """每项用例提供含中文与空格的独立构建根目录。"""
        self.directory = tempfile.TemporaryDirectory(prefix='remlark state 中文 ')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def complete(self, output, platform, stage):
        """生成阶段全部必需夹具并提交完成记录。"""
        for name in artifacts(platform, stage):
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f'fixture {platform} {stage} {name}'.encode())
        mark(output, platform, stage)

    def test_all_platforms_require_complete_manifest(self):
        """三个平台每个阶段只有所有非空产物及完成记录匹配才通过。"""
        for platform in ['windows', 'macos', 'linux']:
            stages = ['openssl', 'ffmpeg', 'freerdp', 'rdp', 'crypto']
            if platform == 'windows':
                stages.append('zlib')
            for stage in stages:
                with self.subTest(platform=platform, stage=stage):
                    output = self.root / f'{platform}-{stage}'
                    self.assertFalse(ready(output, platform, stage))
                    self.complete(output, platform, stage)
                    self.assertTrue(ready(output, platform, stage))
                    first = output / artifacts(platform, stage)[0]
                    first.write_bytes(b'corrupted')
                    self.assertFalse(ready(output, platform, stage))

    def test_lone_library_and_unmarked_install_are_not_complete(self):
        """单个 libcrypto 或没有提交记录的完整文件集合不能伪装成功安装。"""
        output = self.root / 'windows-arm64'
        path = output / 'prefix/lib/libcrypto.lib'
        path.parent.mkdir(parents=True)
        path.write_bytes(b'partial')
        self.assertFalse(ready(output, 'windows', 'openssl'))
        with self.assertRaises(ValueError):
            mark(output, 'windows', 'openssl')
        for name in artifacts('windows', 'openssl'):
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'not committed')
        self.assertFalse(ready(output, 'windows', 'openssl'))

    def test_failed_remark_removes_old_success(self):
        """后续安装失败不能保留旧成功标记，空文件和缺失文件都拒绝。"""
        output = self.root / 'macos-arm64'
        self.complete(output, 'macos', 'ffmpeg')
        path = output / artifacts('macos', 'ffmpeg')[-1]
        path.write_bytes(b'')
        with self.assertRaises(ValueError):
            mark(output, 'macos', 'ffmpeg')
        self.assertFalse((output / '.completed/ffmpeg.json').exists())
        self.assertFalse(ready(output, 'macos', 'ffmpeg'))
        path.unlink()
        self.assertFalse(ready(output, 'macos', 'ffmpeg'))

    def test_rebuild_cannot_mix_old_and_new_outputs(self):
        """阶段重建先移除旧输出；其他已完成依赖继续可用，缺少新头文件不能借用旧文件。"""
        output = self.root / 'windows-arm64'
        self.complete(output, 'windows', 'openssl')
        self.complete(output, 'windows', 'ffmpeg')
        begin(output, 'windows', 'ffmpeg')
        self.assertTrue(ready(output, 'windows', 'openssl'))
        self.assertFalse(ready(output, 'windows', 'ffmpeg'))
        self.assertTrue(all(not (output / name).exists() for name in artifacts('windows', 'ffmpeg')))
        for name in artifacts('windows', 'ffmpeg')[:3]:
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'new library without headers')
        with self.assertRaises(ValueError):
            mark(output, 'windows', 'ffmpeg')

    def test_malformed_state_and_platform_mismatch(self):
        """损坏 JSON、错误目标平台及不完整文件列表不得恢复阶段。"""
        output = self.root / 'windows-arm64'
        self.complete(output, 'windows', 'openssl')
        marker = output / '.completed/openssl.json'
        for value in ['{broken', 'null', '[]', json.dumps({'platform': 'macos', 'files': {}})]:
            marker.write_text(value, encoding='utf-8')
            self.assertFalse(ready(output, 'windows', 'openssl'))

    def test_permission_error_is_not_an_incomplete_stage(self):
        """无法读取状态时必须报错，避免把本地权限错误当作需要重编译。"""
        with patch('pathlib.Path.read_text', side_effect=PermissionError('denied')):
            with self.assertRaises(PermissionError):
                ready(self.root, 'windows', 'openssl')

    def test_changed_build_recipe_is_not_reused(self):
        """版本/参数或 MSVC 配方变化后不能因旧文件仍存在就跳过构建。"""
        output = self.root / 'windows-arm64'
        self.complete(output, 'windows', 'openssl')
        with patch('tools.utils.native_build_state.recipe_signature', return_value='changed-recipe'):
            self.assertFalse(ready(output, 'windows', 'openssl'))

    def test_copied_other_arch_is_not_reused(self):
        """即使文件摘要一致，将 ARM64 阶段复制到 x64 目录也不得复用。"""
        source = self.root / 'windows-arm64'
        target = self.root / 'windows-x86_64'
        self.complete(source, 'windows', 'openssl')
        shutil.copytree(source, target)
        self.assertFalse(ready(target, 'windows', 'openssl'))

    def test_cache_identity_changes_for_workspace_or_compiler(self):
        """目录迁移或 MSVC 更新必须产生新键，避免命中不可更新的旧缓存后反复重编译。"""
        with patch.dict(os.environ, {'VCToolsVersion': '14.test-a'}):
            first = cache_identity(self.root, 'windows')
            self.assertEqual(first, cache_identity(self.root, 'windows'))
            self.assertNotEqual(first, cache_identity(self.root / 'moved', 'windows'))
        with patch.dict(os.environ, {'VCToolsVersion': '14.test-b'}):
            self.assertNotEqual(first, cache_identity(self.root, 'windows'))

    def test_partial_progress_is_saved_but_not_full_cache(self):
        """OpenSSL 完成且后续失败时只提供阶段进度，不能当完整原生缓存。"""
        output = self.root / 'windows-arm64'
        self.complete(output, 'windows', 'openssl')
        self.assertEqual(cache_status(self.root, 'windows', 'arm64'), (True, False))
        for stage in ['zlib', 'ffmpeg', 'freerdp', 'rdp', 'crypto']:
            self.complete(output, 'windows', stage)
        self.assertEqual(cache_status(self.root, 'windows', 'arm64'), (True, True))
        (output / 'remlark_crypto.dll').write_bytes(b'wrong')
        self.assertEqual(cache_status(self.root, 'windows', 'arm64'), (True, False))

    def test_universal_requires_both_arches_and_all_libraries(self):
        """macOS 通用缓存缺任一架构或 SSH 库时禁止标记完整。"""
        for arch in ['x86_64', 'arm64']:
            output = self.root / f'macos-{arch}'
            for stage in ['openssl', 'ffmpeg', 'freerdp', 'rdp', 'crypto']:
                self.complete(output, 'macos', stage)
            self.assertEqual(cache_status(self.root, 'macos', 'universal'), (True, arch == 'arm64'))
        (self.root / 'macos-arm64/.completed/crypto.json').unlink()
        self.assertEqual(cache_status(self.root, 'macos', 'universal'), (True, False))

    def test_linux_and_windows_arch_directory_mapping(self):
        """CI 的 x64/arm64 映射到生产 hook 对应目录，不串用平台或架构。"""
        for platform, arch, directory in [('linux', 'x64', 'linux-x86_64'),
                                           ('linux', 'arm64', 'linux-aarch64'),
                                           ('windows', 'x64', 'windows-x86_64')]:
            self.complete(self.root / directory, platform, 'openssl')
            self.assertEqual(cache_status(self.root, platform, arch), (True, False))

    def test_cli_states_and_github_output(self):
        """CLI 区分未完成和真实错误，缓存输出可被 GitHub Actions 读取。"""
        script = str(ROOT / 'tools/utils/native_build_state.py')
        args = [sys.executable, script, 'ready', str(self.root), 'windows', 'openssl']
        self.assertEqual(subprocess.run(args, capture_output=True).returncode, 1)
        args[2] = 'mark'
        self.assertEqual(subprocess.run(args, capture_output=True).returncode, 2)
        self.complete(self.root / 'windows-x86_64', 'windows', 'openssl')
        output = self.root / 'github-output'
        result = subprocess.run([sys.executable, script, 'cache-status', str(self.root), 'windows',
                                 '--arch', 'x64', '--github-output', str(output)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output.read_text(encoding='utf-8'), 'dependencies=true\ncomplete=false\n')

    @unittest.skipIf(sys.platform == 'win32', 'POSIX 执行器在 macOS/Linux 验证；Windows 另测 PowerShell')
    def test_invalid_arch_and_missing_tool_fail_before_download(self):
        """真实 POSIX 入口的非法目标和缺工具分支在任何下载或产品编译前终止。"""
        script = self.root / 'native/rdp/scripts/build.sh'
        script.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / 'native/rdp/scripts/build.sh', script)
        result = subprocess.run(['bash', str(script), 'invalid-architecture'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unsupported arch', result.stderr)
        tools = self.root / 'tools-bin'
        tools.mkdir()
        for name, source in [('dirname', shutil.which('dirname')), ('mkdir', shutil.which('mkdir')),
                             ('python3', sys.executable)]:
            (tools / name).symlink_to(source)
        for name, value in [('uname', 'Darwin'), ('getconf', '1')]:
            executable = tools / name
            executable.write_text(f'#!/bin/sh\necho {value}\n', encoding='utf-8')
            executable.chmod(0o755)
        env = dict(os.environ, PATH=str(tools))
        result = subprocess.run(['/bin/bash', str(script), 'arm64'], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing native build tool: cmake', result.stderr)
        self.assertFalse(list(self.root.glob('native/rdp/.deps/*.tar.gz')))

    @unittest.skipIf(sys.platform == 'win32', 'MSYS2 入口静态及 PowerShell 测试在 Windows 验证')
    def test_ffmpeg_language_check_has_standalone_preflight(self):
        """用替身编译器执行实际 shell 预检查，不启动 configure 或产品构建。"""
        tools = self.root / 'ffmpeg-tools'
        tools.mkdir()
        for name, text in [('cygpath', 'echo "$2"'), ('cl.exe', 'echo "Microsoft (R) C/C++ Compiler"; exit 2')]:
            executable = tools / name
            executable.write_text(f'#!/bin/sh\n{text}\n', encoding='utf-8')
            executable.chmod(0o755)
        env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'])
        script = str(ROOT / 'native/rdp/scripts/build_ffmpeg_msvc.sh')
        result = subprocess.run(['bash', script, '--check-toolchain'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        (tools / 'cl.exe').write_text('#!/bin/sh\necho localized; exit 2\n', encoding='utf-8')
        result = subprocess.run(['bash', script, '--check-toolchain'], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('English language pack', result.stderr)


if __name__ == '__main__':
    unittest.main()
