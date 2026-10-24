"""P-23：三平台服务端六路打包，检查架构、防漏库与归档布局。"""

from pathlib import Path
import shutil
import stat
import struct
import sys
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.release.server_bundle import TARGETS, package


def binary(target, arch):
    """构造最小原生头以覆盖六种目标，不执行其他系统的代码。"""
    header = bytearray(128)
    if target == 'macos':
        header[:4] = b'\xcf\xfa\xed\xfe'
        struct.pack_into('<I', header, 4, 0x01000007 if arch == 'x64' else 0x0100000C)
    elif target == 'linux':
        header[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<H', header, 18, 62 if arch == 'x64' else 183)
    else:
        header[:2] = b'MZ'
        struct.pack_into('<I', header, 60, 64)
        header[64:68] = b'PE\0\0'
        struct.pack_into('<H', header, 68, 0x8664 if arch == 'x64' else 0xAA64)
    return header


class ServerBundleTests(unittest.TestCase):
    """每台 CI 主机均检查全部平台与架构的打包规则。"""

    def setUp(self):
        """使用含空格与中文的独立目录，不访问已有构建产物。"""
        self.temp = tempfile.TemporaryDirectory(prefix='server 打包 ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'VERSION').write_text('1.2.3+4\n', encoding='utf-8')

    def fixture(self, target, arch):
        """创建目标主程序、SQLite 库和附属资源。"""
        bundle = self.root / 'dist/remlark-sync-server/bundle'
        shutil.rmtree(bundle, ignore_errors=True)
        executable, library, _ = TARGETS[target]
        paths = [bundle / 'bin' / executable, bundle / 'lib' / library]
        for path in paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(binary(target, arch))
            path.chmod(0o755)
        (bundle / 'lib/extra-resource.txt').write_text('resource', encoding='utf-8')
        return paths

    def test_six_archives_keep_complete_bundle(self):
        """核对独立文件名、解压后布局及 POSIX 主程序执行权限。"""
        archives = set()
        for target in TARGETS:
            for arch in ('x64', 'arm64'):
                with self.subTest(target=target, arch=arch):
                    paths = self.fixture(target, arch)
                    archive = package(self.root, target, arch)
                    archives.add(archive.name)
                    extension = 'zip' if target == 'windows' else 'tar.gz'
                    self.assertEqual(archive.name, f'remlark-sync-server-1.2.3-{target}-{arch}.{extension}')
                    if target != 'windows':
                        with tarfile.open(archive) as tar:
                            mode = tar.getmember(f'bundle/bin/{paths[0].name}').mode
                            # Windows 文件系统不支持为合成 POSIX 夹具设置执行位；验证原值保留。
                            self.assertEqual(mode & stat.S_IXUSR, paths[0].stat().st_mode & stat.S_IXUSR)
                    else:
                        with zipfile.ZipFile(archive) as zipped:
                            self.assertIn('bundle/bin/server.exe', zipped.namelist())
                    stage = self.root / f'extracted-{target}-{arch}'
                    shutil.unpack_archive(str(archive), stage)
                    for path in paths:
                        self.assertEqual((stage / 'bundle' / path.relative_to(paths[0].parents[1])).read_bytes(), path.read_bytes())
                    self.assertEqual((stage / 'bundle/lib/extra-resource.txt').read_text(), 'resource')
        self.assertEqual(len(archives), 6)

    def test_missing_empty_wrong_platform_and_wrong_arch_fail(self):
        """主程序和 SQLite 均独立检查，缺失、空文件和混用架构时拒绝发布。"""
        for target in TARGETS:
            for arch in ('x64', 'arm64'):
                for index in (0, 1):
                    for fault in ('missing', 'empty', 'arch', 'platform'):
                        with self.subTest(target=target, arch=arch, index=index, fault=fault):
                            path = self.fixture(target, arch)[index]
                            if fault == 'missing':
                                path.unlink()
                            elif fault == 'empty':
                                path.write_bytes(b'')
                            elif fault == 'arch':
                                path.write_bytes(binary(target, 'arm64' if arch == 'x64' else 'x64'))
                            else:
                                path.write_bytes(binary('linux' if target != 'linux' else 'windows', arch))
                            with self.assertRaises(ValueError):
                                package(self.root, target, arch)


if __name__ == '__main__':
    unittest.main()
