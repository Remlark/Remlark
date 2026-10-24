"""P-26：源码下载异常响应、镜像、完整性与原子落盘回归，不访问公网。"""

import contextlib
import gzip
import hashlib
import http.client
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.utils.source_archive import download_archive, prepare_source


def archive_bytes(root='zlib-1.3.1'):
    """生成包含版本目录及源码文件的真实 gzip/tar 测试包。"""
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w:gz') as archive:
        member = tarfile.TarInfo(f'{root}/source.c')
        member.size = 4
        archive.addfile(member, io.BytesIO(b'code'))
    return output.getvalue()


class SourceArchiveTests(unittest.TestCase):
    """所有平台执行相同下载实现及不同来源/失败阶段的真实归档校验。"""

    def setUp(self):
        """为每个用例隔离含中文空格的目录及下载输出。"""
        self.directory = tempfile.TemporaryDirectory(prefix='remlark source 中文 ')
        self.addCleanup(self.directory.cleanup)
        self.target = Path(self.directory.name) / 'source.tar.gz'
        self.valid = archive_bytes()
        self.digest = hashlib.sha256(self.valid).hexdigest()

    def fetch(self, responses, urls=None, attempts=2, digest=None):
        """替换网络传输，保留实际写入、gzip CRC、tar 和 SHA 校验。"""
        with patch('urllib.request.urlopen', side_effect=responses) as request, \
                patch('time.sleep'), \
                contextlib.redirect_stdout(io.StringIO()):
            download_archive(self.target, urls or ['https://primary/source'],
                             'zlib-1.3.1', digest, attempts)
        return request

    def test_valid_archive_and_headers(self):
        """有效源码包通过 SHA 校验；禁止 HTTP 层自动解压且指定网络超时。"""
        request = self.fetch([io.BytesIO(self.valid)], digest=self.digest)
        self.assertEqual(self.target.read_bytes(), self.valid)
        self.assertEqual(request.call_args.args[0].get_header('Accept-encoding'), 'identity')
        self.assertEqual(request.call_args.kwargs['timeout'], 60)
        self.assertFalse(list(self.target.parent.glob('*.part')))

    def test_html_response_retries(self):
        """HTTP 成功但内容为错误页时重试，不将 HTML 发布为源码包。"""
        request = self.fetch([io.BytesIO(b'<html>unavailable</html>'), io.BytesIO(self.valid)])
        self.assertEqual(request.call_count, 2)
        self.assertEqual(self.target.read_bytes(), self.valid)

    def test_truncated_gzip_retries(self):
        """压缩头有效但尾部截断的文件不得通过校验。"""
        self.fetch([io.BytesIO(self.valid[:-8]), io.BytesIO(self.valid)])
        self.assertEqual(self.target.read_bytes(), self.valid)

    def test_crc_corruption_retries(self):
        """gzip CRC 被修改时拒绝，即使 tar 内部头仍然有效。"""
        corrupt = bytearray(self.valid)
        corrupt[-8] ^= 1
        self.fetch([io.BytesIO(corrupt), io.BytesIO(self.valid)])
        self.assertEqual(self.target.read_bytes(), self.valid)

    def test_mirror_after_primary_failure(self):
        """主来源重试耗尽后切换备用来源并验证同一固定哈希。"""
        request = self.fetch([
            urllib.error.URLError('offline'), io.BytesIO(b'not gzip'), io.BytesIO(self.valid),
        ], urls=['https://primary/source', 'https://mirror/source'], digest=self.digest)
        self.assertEqual([call.args[0].full_url for call in request.call_args_list],
                         ['https://primary/source', 'https://primary/source', 'https://mirror/source'])

    def test_http_and_incomplete_transfer_retry(self):
        """HTTP 错误和传输中断均进入重试，不直接到解压阶段。"""
        for error in [urllib.error.HTTPError('https://primary', 503, 'Unavailable', {}, None),
                      http.client.IncompleteRead(b'partial', 100)]:
            with self.subTest(error=type(error).__name__):
                self.target.unlink(missing_ok=True)
                self.fetch([error, io.BytesIO(self.valid)])

    def test_checksum_mismatch_preserves_previous_file(self):
        """错误校验和耗尽重试后保留原文件，并清除全部临时文件。"""
        self.target.write_bytes(b'previous')
        with self.assertRaisesRegex(RuntimeError, 'SHA-256 mismatch'):
            self.fetch([io.BytesIO(self.valid), io.BytesIO(self.valid)], digest='0' * 64)
        self.assertEqual(self.target.read_bytes(), b'previous')
        self.assertFalse(list(self.target.parent.glob('*.part')))

    def test_invalid_tar_and_root_rejected(self):
        """有效 gzip 中的非 tar、错误版本目录及目录逃逸都不得发布。"""
        for payload in [gzip.compress(b'not tar'), archive_bytes('other-version'), archive_bytes('../escape')]:
            with self.subTest(payload=payload[:8]):
                with self.assertRaises(RuntimeError):
                    self.fetch([io.BytesIO(payload)], attempts=1)
                self.assertFalse(self.target.exists())
                self.assertFalse(list(self.target.parent.glob('*.part')))

    def test_cli_arguments_and_exit_status(self):
        """用本地文件 URL 验证构建脚本参数接口及失败非零退出码。"""
        source = self.target.parent / 'input.tar.gz'
        source.write_bytes(self.valid)
        args = [sys.executable, str(ROOT / 'tools/utils/source_archive.py'), str(self.target),
                source.as_uri(), '--root', 'zlib-1.3.1', '--sha256', self.digest, '--attempts', '1']
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        source.write_bytes(b'<html>bad</html>')
        args[2] = str(self.target.parent / 'failed.tar.gz')
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_bytes(), self.valid)

    def test_valid_local_archive_avoids_network(self):
        """中断后的已验证下载直接复用，不为重跑构建重复下载大文件。"""
        self.target.write_bytes(self.valid)
        request = self.fetch([], digest=self.digest)
        request.assert_not_called()

    def test_cli_non_utf8_console_does_not_break_cache_reuse(self):
        """非 UTF-8 控制台输出中文缓存路径不能导致本来有效的源码准备失败。"""
        self.target.write_bytes(self.valid)
        result = subprocess.run([
            sys.executable, str(ROOT / 'tools/utils/source_archive.py'), str(self.target),
            'https://unused', '--root', 'zlib-1.3.1', '--sha256', self.digest,
        ], env=dict(os.environ, PYTHONIOENCODING='ascii:strict'), capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b'reuse verified archive', result.stdout)
        self.assertEqual(self.target.read_bytes(), self.valid)

    def test_retry_backoff_and_permanent_http_mirror(self):
        """临时失败采用退避，永久 HTTP 错误立即切换镜像。"""
        with patch('urllib.request.urlopen', side_effect=[urllib.error.URLError('retry'), io.BytesIO(self.valid)]), \
                patch('time.sleep') as sleep, contextlib.redirect_stdout(io.StringIO()):
            download_archive(self.target, ['https://primary'], 'zlib-1.3.1')
        sleep.assert_called_once_with(2)
        self.target.unlink()
        request = self.fetch([urllib.error.HTTPError('https://primary', 404, 'Gone', {}, None),
                              io.BytesIO(self.valid)], urls=['https://primary', 'https://mirror'])
        self.assertEqual(request.call_count, 2)
        self.assertEqual(request.call_args.args[0].full_url, 'https://mirror')

    def test_slow_stream_has_total_budget(self):
        """即使数据持续缓慢到达，超出总时长后也会终止并重试。"""
        times = iter([0, 0, 181])
        with patch('time.monotonic', side_effect=lambda: next(times, 200)):
            request = self.fetch([io.BytesIO(self.valid), io.BytesIO(self.valid)])
        self.assertEqual(request.call_count, 2)

    def test_local_disk_error_is_not_network_retry(self):
        """磁盘写入/替换失败立即报错，不将本地问题误当成网络故障重复下载。"""
        with patch('pathlib.Path.replace', side_effect=PermissionError('read-only')):
            with self.assertRaises(PermissionError):
                self.fetch([io.BytesIO(self.valid)])
        self.assertFalse(self.target.exists())
        self.assertFalse(list(self.target.parent.glob('*.part')))

    def test_invalid_arguments_fail_without_request(self):
        """无效 URL、目录和校验和立即失败，不能消耗多次网络重试。"""
        cases = [([''], 'zlib-1.3.1', None), (['https://valid'], '/', None),
                 (['https://valid'], 'C:', None), (['https://valid'], '../bad', None),
                 (['https://valid'], 'zlib-1.3.1', 'not-a-sha256')]
        for urls, root, checksum in cases:
            with self.subTest(urls=urls, root=root), patch('urllib.request.urlopen') as request:
                with self.assertRaises(ValueError):
                    download_archive(self.target, urls, root, checksum)
                request.assert_not_called()

    def test_partial_source_is_atomically_repaired(self):
        """已有但未完成的源码目录重新解压；已有压缩包不会联网。"""
        self.target.write_bytes(self.valid)
        directory = self.target.parent / 'zlib-1.3.1'
        directory.mkdir()
        (directory / 'partial').write_text('partial', encoding='utf-8')
        with patch('urllib.request.urlopen') as request:
            prepare_source(self.target, ['https://unused'], directory.name, ['source.c'])
        request.assert_not_called()
        self.assertEqual((directory / 'source.c').read_bytes(), b'code')
        self.assertFalse((directory / 'partial').exists())
        self.assertTrue((directory / '.remlark-source.json').is_file())
        with patch('urllib.request.urlopen') as request, patch('subprocess.run') as extract:
            prepare_source(self.target, ['https://unused'], directory.name, ['source.c'])
        request.assert_not_called()
        extract.assert_not_called()
        (directory / 'source.c').unlink()
        prepare_source(self.target, ['https://unused'], directory.name, ['source.c'])
        self.assertEqual((directory / 'source.c').read_bytes(), b'code')

    def test_extract_failure_preserves_existing_source(self):
        """解压命令失败或超时，旧目录保持原样，临时目录必须清理。"""
        self.target.write_bytes(self.valid)
        directory = self.target.parent / 'zlib-1.3.1'
        directory.mkdir()
        (directory / 'previous').write_bytes(b'previous')
        for error in [subprocess.CalledProcessError(1, 'tar'), subprocess.TimeoutExpired('tar', 120)]:
            with self.subTest(error=type(error).__name__), patch('subprocess.run', side_effect=error):
                with self.assertRaises(subprocess.SubprocessError):
                    prepare_source(self.target, ['https://unused'], directory.name, ['source.c'])
            self.assertEqual((directory / 'previous').read_bytes(), b'previous')
            self.assertFalse((directory / '.remlark-source.json').exists())
            self.assertFalse(list(self.target.parent.glob('.source-*')))

    def test_publish_failure_rolls_back_previous_source(self):
        """目录替换失败会恢复旧目录，不留下“看似已完成”的新源码。"""
        self.target.write_bytes(self.valid)
        directory = self.target.parent / 'zlib-1.3.1'
        directory.mkdir()
        (directory / 'previous').write_bytes(b'previous')
        original = Path.replace

        def fail_publish(path, target):
            """只阻止新目录发布，允许旧目录备份与恢复。"""
            if path.name == directory.name and path.parent.name.startswith('.source-'):
                raise PermissionError('publish denied')
            return original(path, target)

        with patch('pathlib.Path.replace', fail_publish):
            with self.assertRaises(PermissionError):
                prepare_source(self.target, ['https://unused'], directory.name, ['source.c'])
        self.assertEqual((directory / 'previous').read_bytes(), b'previous')
        self.assertFalse((directory / '.remlark-source.json').exists())
        self.assertFalse(list(self.target.parent.glob('.source-*')))

    def test_missing_required_file_and_unsafe_link_rejected(self):
        """源码缺少关键文件或链接逃出根目录时拒绝，不发布完成记录。"""
        self.target.write_bytes(self.valid)
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            prepare_source(self.target, ['https://unused'], 'zlib-1.3.1', ['missing.c'])
        self.assertFalse((self.target.parent / 'zlib-1.3.1').exists())
        self.target.unlink()
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode='w:gz') as archive:
            link = tarfile.TarInfo('zlib-1.3.1/escape')
            link.type = tarfile.SYMTYPE
            link.linkname = '../../outside'
            archive.addfile(link)
        with self.assertRaisesRegex(RuntimeError, 'link escapes'):
            self.fetch([io.BytesIO(output.getvalue())], attempts=1)


if __name__ == '__main__':
    unittest.main()
