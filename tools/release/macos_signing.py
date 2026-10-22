#!/usr/bin/env python3
"""macOS 发布签名：临时钥匙串导入、自签 App / DMG 与凭据清理。"""

import base64
import binascii
import json
import os
import plistlib
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MACHO_MAGIC = {bytes.fromhex(value) for value in (
    'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca',
    'cafebabf', 'bfbafeca')}


def run(*args):
    """执行签名工具并隐藏命令参数，避免失败日志泄露证书密码。"""
    try:
        result = subprocess.run([str(arg) for arg in args], capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f'{args[0]} timed out') from None
    if result.returncode:
        detail = (result.stderr.decode(errors='replace')
                  if args[0] == 'codesign' else 'check signing identity, certificate and passwords')
        raise RuntimeError(f'{args[0]} failed (exit {result.returncode}): {detail}')
    return result.stdout


def required(name):
    """在构建前检查必要配置，不允许缺失 Secret 时静默退回临时签名。"""
    value = os.environ.get(name, '')
    if not value.strip():
        raise ValueError(f'Missing required secret: {name}')
    return value


def keychain():
    """将 CI 凭据限定在 runner 临时目录，不修改默认或登录钥匙串。"""
    return Path(required('RUNNER_TEMP')) / 'remlark-signing.keychain-db'


def install():
    """将带私钥的 P12 导入临时钥匙串，不修改系统或用户的证书信任。"""
    names = ('MACOS_CERTIFICATE_BASE64', 'MACOS_CERTIFICATE_PASSWORD',
             'MACOS_SIGNING_IDENTITY', 'MACOS_KEYCHAIN_PASSWORD')
    values = {name: required(name) for name in names}
    identity = values['MACOS_SIGNING_IDENTITY']
    if identity == '-':
        raise ValueError('MACOS_SIGNING_IDENTITY must not be ad-hoc (-)')
    # 兼容复制时带换行的 Base64，损坏输入必须在调用系统工具前失败。
    payload = base64.b64decode(''.join(values['MACOS_CERTIFICATE_BASE64'].split()),
                               validate=True)
    if not payload:
        raise ValueError('Empty signing certificate')
    chain = keychain()
    p12 = chain.with_suffix('.p12')
    search_list = chain.with_suffix('.search-list.json')
    try:
        # 私钥文件创建时即限制访问权限，而不是写入后再 chmod。
        with open(p12, 'wb', opener=lambda path, flags: os.open(path, flags, 0o600)) as stream:
            stream.write(payload)
        # codesign 仍需通过用户搜索列表访问私钥，--keychain 本身不足够。
        previous = shlex.split(run('security', 'list-keychains', '-d', 'user').decode())
        search_list.write_text(json.dumps(previous), encoding='utf-8')
        password = values['MACOS_KEYCHAIN_PASSWORD']
        run('security', 'create-keychain', '-p', password, chain)
        run('security', 'set-keychain-settings', '-lut', '21600', chain)
        run('security', 'unlock-keychain', '-p', password, chain)
        run('security', 'list-keychains', '-d', 'user', '-s', chain, *previous)
        run('security', 'import', p12, '-P', values['MACOS_CERTIFICATE_PASSWORD'],
            '-k', chain, '-T', '/usr/bin/codesign')
        run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
            '-s', '-k', password, chain)
        # 自签身份不要求系统信任；-v 会过滤掉未受信任的自签证书。
        identities = run('security', 'find-identity', '-p', 'codesigning', chain)
        if identity.encode() not in identities:
            raise ValueError('Signing identity is unavailable or has no valid private key')
    finally:
        p12.unlink(missing_ok=True)


def sign(path, entitlements=None):
    """使用固定身份签名，不请求自签证书无法使用的可信时间戳。"""
    identity = required('MACOS_SIGNING_IDENTITY')
    if identity == '-':
        raise ValueError('MACOS_SIGNING_IDENTITY must not be ad-hoc (-)')
    args = ['codesign', '--force', '--sign', identity, '--keychain', keychain(),
            '--timestamp=none']
    if entitlements:
        args.extend(['--entitlements', entitlements])
    else:
        args.append('--preserve-metadata=entitlements')
    run(*args, path)


def sign_app():
    """由内到外重签所有 Mach-O 和嵌套包，最后保留主 App 的发布权限。"""
    app = ROOT / 'build/macos/Build/Products/Release/remlark.app'
    if not app.is_dir():
        raise ValueError('Build macOS app before signing')
    targets = []
    for path in app.rglob('*'):
        # Framework 的 Versions/Current 等符号链接不可重复签名。
        if path.is_symlink():
            continue
        if path.is_dir() and path.suffix in {'.framework', '.app', '.xpc', '.appex', '.bundle'}:
            info = path / 'Contents/Info.plist'
            if path.suffix == '.framework':
                targets.append(path)
            elif info.exists():
                # 隐私清单等纯资源 bundle 没有可执行文件，无需代码签名。
                with info.open('rb') as stream:
                    if plistlib.load(stream).get('CFBundleExecutable'):
                        targets.append(path)
        elif path.is_file():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO_MAGIC:
                    targets.append(path)
    for target in sorted(targets, key=lambda path: (-len(path.parts), str(path))):
        sign(target)
    sign(app, ROOT / 'macos/Runner/Release.entitlements')
    run('codesign', '--verify', '--deep', '--strict', '--all-architectures', app)


def sign_dmg():
    """只签本次 VERSION 对应的镜像，避免把 dist 中的旧附件混入发布。"""
    sys.path.insert(0, str(ROOT))
    from tools.utils.app_version import read_version
    dmg = ROOT / 'dist' / f"remlark-{read_version(ROOT)['name']}-macos-universal.dmg"
    if not dmg.is_file():
        raise ValueError('Build macOS DMG before signing')
    sign(dmg)
    run('codesign', '--verify', '--strict', dmg)


def cleanup():
    """成功或失败都移除临时钥匙串和私钥文件。"""
    chain = keychain()
    search_list = chain.with_suffix('.search-list.json')
    try:
        if search_list.exists():
            previous = json.loads(search_list.read_text(encoding='utf-8'))
            run('security', 'list-keychains', '-d', 'user', '-s', *previous)
    finally:
        if chain.exists():
            run('security', 'delete-keychain', chain)
        chain.with_suffix('.p12').unlink(missing_ok=True)
        search_list.unlink(missing_ok=True)


def main():
    """macOS 专用系统接口；其他平台不执行任何 Apple 工具。"""
    if sys.platform != 'darwin':
        raise ValueError('macOS signing is only supported on macOS')
    commands = {'install': install, 'sign-app': sign_app,
                'sign-dmg': sign_dmg, 'cleanup': cleanup}
    commands[sys.argv[1]]()


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, binascii.Error) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
