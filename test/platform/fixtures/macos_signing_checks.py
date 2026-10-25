"""P-15：三平台验证签名编排，macOS 额外验证真实自签证书与系统工具。"""

import base64
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location('signing', ROOT / 'tools/release/macos_signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningChecks(unittest.TestCase):
    """不依赖 Apple 工具的输入、失败保护与签名顺序测试。"""

    def setUp(self):
        """每项测试使用独立临时目录与虚构凭据。"""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        env = patch.dict(os.environ, {
            'RUNNER_TEMP': str(self.root),
            'MACOS_CERTIFICATE_BASE64': base64.b64encode(b'fake-p12').decode(),
            'MACOS_CERTIFICATE_PASSWORD': 'fake-p12-password',
        })
        env.start()
        self.addCleanup(env.stop)

    def test_missing_and_invalid_credentials(self):
        """缺失或损坏的两项凭据在调用系统工具前失败。"""
        for name, value in [('MACOS_CERTIFICATE_PASSWORD', ''),
                            ('MACOS_CERTIFICATE_BASE64', '%%%')]:
            with self.subTest(name=name), patch.dict(os.environ, {name: value}), \
                    patch.object(signing, 'run') as run:
                with self.assertRaises(ValueError):
                    signing.install()
                run.assert_not_called()

    def test_identity_selection(self):
        """自动读取指纹，同一身份重复出现允许，缺失或多身份明确拒绝。"""
        first, second = 'A' * 40, 'B' * 40
        valid = f'  1) {first} "测试证书" (CSSMERR_TP_NOT_TRUSTED)\n'.encode()
        with patch.object(signing, 'run', return_value=valid + valid):
            self.assertEqual(signing.signing_identity(), first)
        for output in (b'0 identities found', valid + f'  2) {second} "Other"\n'.encode()):
            with patch.object(signing, 'run', return_value=output):
                with self.assertRaisesRegex(ValueError, 'exactly one'):
                    signing.signing_identity()

    def test_import_needs_only_certificate_and_password(self):
        """只传两项凭据即可导入，钥匙串密码自动生成且不写入文件。"""
        def fake_run(*args):
            """模拟含私钥的代码签名身份，其他系统命令默认成功。"""
            if args[1] == 'find-identity':
                return f'  1) {"A" * 40} "Test Signing"\n'.encode()
            return b''
        with patch.object(signing, 'run', side_effect=fake_run) as run, \
                patch.object(signing.secrets, 'token_urlsafe', return_value='generated-password'):
            signing.install()
        create = next(call for call in run.call_args_list if call.args[1] == 'create-keychain')
        self.assertIn('generated-password', create.args)
        self.assertFalse(signing.keychain().with_suffix('.p12').exists())

    def test_import_failure_removes_private_file(self):
        """密码错误时删除 P12，不继续签名，也不保留私钥中间文件。"""
        with patch.object(signing, 'run', side_effect=RuntimeError('import failed')):
            with self.assertRaises(RuntimeError):
                signing.install()
        self.assertFalse(signing.keychain().with_suffix('.p12').exists())

    def test_command_failure_does_not_leak_password(self):
        """工具报错含密码时，只返回工具名和退出码。"""
        result = subprocess.CompletedProcess([], 1, b'', b'fake-p12-password')
        with patch.object(signing.subprocess, 'run', return_value=result):
            with self.assertRaises(RuntimeError) as error:
                signing.run('security', 'import', '-P', 'fake-p12-password')
        self.assertNotIn('fake-p12-password', str(error.exception))

    def test_nested_signing_order(self):
        """嵌套 Mach-O 先于框架和主 App，跳过资源和符号链接。"""
        app = self.root / 'build/macos/Build/Products/Release/Remlark.app'
        framework = app / 'Contents/Frameworks/Example.framework'
        binary = framework / 'Versions/A/Example'
        binary.parent.mkdir(parents=True)
        binary.write_bytes(bytes.fromhex('cffaedfe') + b'fixture')
        resource = app / 'Contents/resource.txt'
        resource.write_text('not executable')
        # Windows 非管理员环境可能没有创建符号链接权限，核心顺序仍需验证。
        if os.name != 'nt':
            (framework / 'Example').symlink_to('Versions/A/Example')
        with patch.object(signing, 'ROOT', self.root), \
                patch.object(signing, 'sign') as sign, patch.object(signing, 'run') as run:
            signing.sign_app()
        self.assertEqual([call.args[0] for call in sign.call_args_list],
                         [binary, framework, app])
        self.assertEqual(sign.call_args.args[1], self.root / 'macos/Runner/Release.entitlements')
        self.assertIn('--all-architectures', run.call_args.args)
        self.assertIn('--deep', run.call_args.args)

    def test_other_platforms_reject_apple_tools(self):
        """Windows 与 Linux 调用入口时明确拒绝，不运行 security 或 codesign。"""
        for platform in ('win32', 'linux'):
            with patch.object(signing.sys, 'platform', platform), \
                    patch.object(signing, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'only supported on macOS'):
                    signing.main()
                run.assert_not_called()

    def test_cleanup_on_partial_import(self):
        """导入半途失败仍删除钥匙串，不修改用户证书信任。"""
        signing.keychain().touch()
        with patch.object(signing, 'run') as run:
            signing.cleanup()
        self.assertEqual(run.call_args.args[1], 'delete-keychain')

    @unittest.skipUnless(sys.platform == 'darwin', 'requires macOS security / codesign')
    def test_real_self_signed_app(self):
        """创建一次性证书，真实导入、签 App 并严格验证，最后删除临时钥匙串和私钥。"""
        identity = f'Remlark P15 {self.root.name}'
        config = self.root / 'openssl.cnf'
        config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n'
                          f'[dn]\nCN={identity}\n[ext]\nbasicConstraints=critical,CA:TRUE\n'
                          'keyUsage=critical,digitalSignature,keyCertSign\n'
                          'extendedKeyUsage=critical,codeSigning\n')
        cert, key, p12 = (self.root / name for name in ('cert.pem', 'key.pem', 'cert.p12'))
        def command(*args):
            """运行生成测试证书所需的真实系统命令，失败时显示无敏感数据的诊断。"""
            result = subprocess.run([str(arg) for arg in args], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
            return result.stdout
        command('/usr/bin/openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048',
                '-nodes', '-days', '1', '-config', config, '-keyout', key, '-out', cert)
        command('/usr/bin/openssl', 'pkcs12', '-export', '-inkey', key, '-in', cert,
                '-out', p12, '-passout', 'pass:fixture-password')
        app = self.root / 'build/macos/Build/Products/Release/Remlark.app'
        executable = app / 'Contents/MacOS/Remlark'
        executable.parent.mkdir(parents=True)
        shutil.copyfile('/usr/bin/true', executable)
        executable.chmod(0o755)
        with (app / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleExecutable': 'Remlark', 'CFBundleIdentifier': 'com.remlark.p15',
                           'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1'}, stream)
        entitlements = self.root / 'macos/Runner/Release.entitlements'
        entitlements.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'macos/Runner/Release.entitlements', entitlements)
        with patch.dict(os.environ, {'MACOS_CERTIFICATE_PASSWORD': 'fixture-password',
                                     'MACOS_CERTIFICATE_BASE64': base64.b64encode(p12.read_bytes()).decode()}), \
                patch.object(signing, 'ROOT', self.root):
            original_chains = command('security', 'list-keychains', '-d', 'user')
            try:
                signing.install()
                signing.sign_app()
                details = command('codesign', '-d', '-r-', app)
                self.assertIn(b'certificate leaf', details)
                # 第二次重签仍保持相同证书要求，区别于按 CDHash 标识的临时签名。
                signing.sign_app()
                self.assertEqual(command('codesign', '-d', '-r-', app), details)
                dist = self.root / 'dist'
                dist.mkdir()
                archive = dist / 'Remlark-macos.zip'
                command('ditto', '-c', '-k', '--keepParent', app, archive)
                unpacked = self.root / 'unpacked'
                command('ditto', '-x', '-k', archive, unpacked)
                command('codesign', '--verify', '--deep', '--strict',
                        '--all-architectures', unpacked / 'Remlark.app')
                (self.root / 'VERSION').write_text('1.0.0+1\n')
                dmg = dist / 'Remlark-1.0.0-macos-universal.dmg'
                command('hdiutil', 'create', '-srcfolder', app, '-format', 'UDZO', dmg)
                signing.sign_dmg()

            finally:
                signing.cleanup()
        self.assertFalse(signing.keychain().exists())
        self.assertEqual(command('security', 'list-keychains', '-d', 'user'), original_chains)


if __name__ == '__main__':
    unittest.main()
