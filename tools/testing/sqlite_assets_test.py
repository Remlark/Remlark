"""P-33：sqlite3 预编译库预取的三平台命名、缓存布局、来源回退与哈希校验，不访问网络。"""

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils import sqlite_assets
from tools.utils.sqlite_assets import (api_source, asset_name, browser_source, cache_path,
                                       main, normalize_archs, parse_asset_hashes, prefetch,
                                       sqlite3_package_root)

LIBRARY = b'\x7fELF fake sqlite3 library'
# GitHub releases/download 入口返回的 504 网关错误页（与 CI 中的实际内容一致）。
GATEWAY_ERROR = (b"<html><body><h1>504 Gateway Time-out</h1>\nThe server didn't respond "
                 b"in time.\n</body></html>\n")
TAG = 'sqlite3-9.9.9'


def write_project(root, library_hash, relative=False):
    """生成带 package_config 与 asset_hashes.dart 的最小项目，sqlite3 包放在含空格中文路径。"""
    package = Path(root) / '依赖 cache' / 'sqlite3-9.9.9'
    hook = package / 'lib' / 'src' / 'hook'
    hook.mkdir(parents=True)
    names = ['libsqlite3.x64.linux.so', 'libsqlite3.arm64.linux.so',
             'libsqlite3.x64.macos.dylib', 'libsqlite3.arm64.macos.dylib',
             'sqlite3.x64.windows.dll', 'sqlite3.arm64.windows.dll']
    entries = '\n'.join(f"  '{name}': '{library_hash}'," for name in names)
    (hook / 'asset_hashes.dart').write_text(
        f"const String? releaseTag = '{TAG}';\n\nconst Map<String, String> "
        f"assetNameToSha256Hash = {{\n{entries}\n}};\n", encoding='utf-8')
    project = Path(root) / 'app'
    (project / '.dart_tool').mkdir(parents=True)
    uri = '../../依赖 cache/sqlite3-9.9.9' if relative else package.resolve().as_uri()
    (project / '.dart_tool' / 'package_config.json').write_text(json.dumps({
        'configVersion': 2,
        'packages': [{'name': 'other', 'rootUri': 'file:///nowhere'},
                     {'name': 'sqlite3', 'rootUri': uri}],
    }), encoding='utf-8')
    return project


class SqliteAssetsTests(unittest.TestCase):
    """三平台用替身网络验证预取行为。"""

    def setUp(self):
        """每个用例使用独立临时目录。"""
        self.temporary = tempfile.TemporaryDirectory()
        self.root = self.temporary.name
        self.expected = hashlib.sha256(LIBRARY).hexdigest()

    def tearDown(self):
        """清理临时目录。"""
        self.temporary.cleanup()

    def test_asset_and_cache_names_match_hook(self):
        """附件名、缓存文件名与 download-<哈希前 8 位> 目录与钩子一致。"""
        self.assertEqual(asset_name('linux', 'x64'), 'libsqlite3.x64.linux.so')
        self.assertEqual(asset_name('macos', 'arm64'), 'libsqlite3.arm64.macos.dylib')
        self.assertEqual(asset_name('windows', 'arm64'), 'sqlite3.arm64.windows.dll')
        digest = 'b17729184e5a2818055ecbddd5ed6642521bfe6e56aafa472330e483c0e2e0d2'
        for os_name, file_name in [('linux', 'libsqlite3.so'), ('macos', 'libsqlite3.dylib'),
                                   ('windows', 'sqlite3.dll')]:
            path = cache_path('p', os_name, digest)
            self.assertEqual(path.parts[-6:], ('hooks_runner', 'shared', 'sqlite3', 'build',
                                               'download-b1772918', file_name))

    def test_arch_aliases_and_universal(self):
        """各系统 machine 写法统一，universal 展开为双架构，未知架构报错。"""
        for machine in ['x86_64', 'AMD64', 'x64']:
            self.assertEqual(normalize_archs(machine), ['x64'])
        for machine in ['aarch64', 'ARM64', 'arm64']:
            self.assertEqual(normalize_archs(machine), ['arm64'])
        self.assertEqual(normalize_archs('universal'), ['x64', 'arm64'])
        with self.assertRaises(ValueError):
            normalize_archs('mips')

    def test_package_root_from_file_and_relative_uri(self):
        """package_config 的 file:// 与相对 rootUri 都能定位到含中文空格的包目录。"""
        for relative in (False, True):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as root:
                project = write_project(root, self.expected, relative)
                package = sqlite3_package_root(project)
                self.assertTrue((package / 'lib' / 'src' / 'hook' / 'asset_hashes.dart').is_file())

    def test_parse_rejects_unknown_format(self):
        """哈希文件格式变化时明确报错，而不是静默跳过。"""
        tag, hashes = parse_asset_hashes(
            f"const String? releaseTag = 'x';\n  'a.so': '{self.expected}',")
        self.assertEqual((tag, hashes), ('x', {'a.so': self.expected}))
        with self.assertRaises(ValueError):
            parse_asset_hashes('const nothing = 1;')

    def test_gateway_error_falls_back_and_caches_verified_file(self):
        """首个来源返回网关错误页时不写缓存，回退到下一来源并写入校验过的库。"""
        # CI 报出的“实际哈希”正是该错误页的哈希。
        self.assertEqual(hashlib.sha256(GATEWAY_ERROR).hexdigest(),
                         'bef140a1a96994029153dca8c00b1750b9a5a764fb9db2dc68d7bb40e8a29e8a')
        project = write_project(self.root, self.expected)
        calls = []

        def broken(tag, name, get=None, token=None):
            """模拟 releases/download 的 504 错误页。"""
            calls.append(('broken', tag, name))
            return GATEWAY_ERROR

        def working(tag, name, get=None, token=None):
            """模拟可用的 API 来源。"""
            calls.append(('working', tag, name))
            return LIBRARY

        target = prefetch(project, 'linux', 'x64',
                          sources=(('broken', broken), ('working', working)))
        self.assertEqual(calls, [('broken', TAG, 'libsqlite3.x64.linux.so'),
                                 ('working', TAG, 'libsqlite3.x64.linux.so')])
        self.assertEqual(target.read_bytes(), LIBRARY)
        self.assertEqual(target.parent.name, f'download-{self.expected[:8]}')
        self.assertEqual(sorted(p.name for p in target.parent.iterdir()), ['libsqlite3.so'])
        # 再次运行直接复用，不访问网络。
        prefetch(project, 'linux', 'x64', sources=(('fail', self.fail_source),))

    def test_all_sources_fail_leaves_no_file(self):
        """全部来源失败时抛出含各来源原因的异常，不留下缓存或临时文件。"""
        project = write_project(self.root, self.expected)
        with self.assertRaises(RuntimeError) as raised:
            prefetch(project, 'windows', 'x64',
                     sources=(('error page', lambda *a, **k: GATEWAY_ERROR),
                              ('fail', self.fail_source)))
        self.assertIn('error page', str(raised.exception))
        self.assertIn('fail', str(raised.exception))
        target = cache_path(project, 'windows', self.expected)
        self.assertFalse(target.exists())
        self.assertEqual(list(target.parent.iterdir()), [])

    def test_corrupt_cache_is_replaced(self):
        """缓存中残留的错误页被重新下载覆盖。"""
        project = write_project(self.root, self.expected)
        target = cache_path(project, 'macos', self.expected)
        target.parent.mkdir(parents=True)
        target.write_bytes(GATEWAY_ERROR)
        prefetch(project, 'macos', 'arm64', sources=(('ok', lambda *a, **k: LIBRARY),))
        self.assertEqual(target.read_bytes(), LIBRARY)

    def test_api_source_keeps_token_off_redirect(self):
        """API 来源按名称找附件，令牌只发给 api.github.com，跳转地址不带令牌。"""
        requests = []

        def get(url, headers=None, follow=True):
            """替身 HTTP：记录请求并按地址返回元数据、跳转与文件。"""
            requests.append((url, dict(headers or {}), follow))
            if url.endswith(f'/releases/tags/{TAG}'):
                return json.dumps({'assets': [
                    {'name': 'other', 'url': 'https://api.github.com/assets/1'},
                    {'name': 'libsqlite3.x64.linux.so', 'url': 'https://api.github.com/assets/2'},
                ]}).encode()
            if url == 'https://api.github.com/assets/2':
                return ('redirect', 'https://objects.example/signed')
            return LIBRARY

        self.assertEqual(api_source(TAG, 'libsqlite3.x64.linux.so', get=get, token='t'), LIBRARY)
        self.assertEqual(requests[1][1]['Accept'], 'application/octet-stream')
        self.assertFalse(requests[1][2])
        self.assertEqual(requests[0][1]['Authorization'], 'Bearer t')
        self.assertEqual(requests[2], ('https://objects.example/signed', {}, True))
        with self.assertRaises(ValueError):
            api_source(TAG, 'missing.so', get=get)

    def test_browser_source_url(self):
        """回退来源与钩子默认 url_pattern 相同。"""
        urls = []
        browser_source(TAG, 'sqlite3.x64.windows.dll',
                       get=lambda url, headers=None, follow=True: urls.append(url) or LIBRARY)
        self.assertEqual(urls, [f'https://github.com/simolus3/sqlite3.dart/releases/download/'
                                f'{TAG}/sqlite3.x64.windows.dll'])

    def test_cli_exit_codes(self):
        """命令行：universal 预取双架构返回 0，来源全部失败返回 1，非法架构为参数错误。"""
        project = write_project(self.root, self.expected)
        with mock.patch.object(sqlite_assets, 'SOURCES', (('ok', lambda *a, **k: LIBRARY),)):
            self.assertEqual(main([str(project), '--os', 'macos', '--arch', 'universal']), 0)
        self.assertTrue(cache_path(project, 'macos', self.expected).is_file())
        with mock.patch.object(sqlite_assets, 'SOURCES', (('fail', self.fail_source),)):
            self.assertEqual(main([str(project), '--os', 'linux', '--arch', 'arm64']), 1)
        with self.assertRaises(SystemExit):
            main([str(project), '--arch', 'mips'])

    @staticmethod
    def fail_source(tag, name, get=None, token=None):
        """总是失败的来源。"""
        raise OSError('network down')


if __name__ == '__main__':
    unittest.main()
