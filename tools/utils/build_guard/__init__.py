"""构建前保护运行实例：匹配构建输出路径，不覆盖、不自动退出、不结束用户连接。"""
import json
import ntpath
import os
from pathlib import Path
import sys

from .inspector import GuardError
from .linux import LinuxInspector
from .macos import MacosInspector
from .windows import WindowsInspector

PLATFORMS = ('macos', 'windows', 'linux')


def current_platform():
    """返回当前桌面平台，未知平台拒绝执行桌面保护检查。"""
    return {'darwin': 'macos', 'win32': 'windows', 'linux': 'linux'}.get(sys.platform)


def target_platform(arguments):
    """从 build 或 run 识别桌面目标；未指定设备的 run 按当前桌面检查。"""
    if arguments[0] == 'build':
        return arguments[1] if len(arguments) > 1 and arguments[1] in PLATFORMS else None
    for index, argument in enumerate(arguments):
        if argument in ('-d', '--device-id') and index + 1 < len(arguments):
            return arguments[index + 1] if arguments[index + 1] in PLATFORMS else None
        if argument.startswith(('--device-id=', '-d=')):
            value = argument.split('=', 1)[1]
            return value if value in PLATFORMS else None
    return current_platform()


def configured_build_directory(root):
    """读取 Flutter 同源配置的 build-dir，仅只读访问；默认使用项目 build。"""
    home = Path(os.environ.get('APPDATA', '.')) if sys.platform == 'win32' else Path.home()
    legacy = home / '.flutter_settings'
    config = legacy if sys.platform == 'win32' or legacy.is_file() else (
        Path(os.environ.get('XDG_CONFIG_HOME', home / '.config/flutter')) / 'settings')
    try:
        settings = json.loads(config.read_text(encoding='utf-8')) if config.exists() else {}
        directory = settings.get('build-dir', 'build')
        if not isinstance(directory, str) or not directory or Path(directory).is_absolute():
            raise ValueError('invalid build directory')
    except (OSError, ValueError, AttributeError) as error:
        raise GuardError('Cannot resolve Flutter build-dir; build cancelled.') from error
    return Path(root) / directory


def conflicting_processes(root, target, processes, build_directory=None):
    """按规范化路径匹配项目输出；不误拦安装目录、独立副本或其他检出目录。"""
    base = Path(build_directory) if build_directory is not None else Path(root) / 'build'
    result = []
    for pid, executable in processes:
        for platform in PLATFORMS if target == 'all' else (target,):
            # Windows 路径在任何测试宿主上都按 Windows 规则比较大小写和分隔符。
            if platform == 'windows':
                windows_base = str(base.resolve()) if sys.platform == 'win32' else str(base)
                executable = str(Path(executable).resolve()) if sys.platform == 'win32' else executable
                prefix = ntpath.normcase(ntpath.join(windows_base, platform))
                path = ntpath.normcase(ntpath.normpath(executable))
                inside = path.startswith(prefix.rstrip('\\') + '\\')
                application = ntpath.basename(path) == 'remlark.exe'
            else:
                prefix = (base / platform).resolve()
                path = Path(executable).resolve()
                inside = path.is_relative_to(prefix)
                application = path.name == 'remlark'
            if inside and application:
                result.append((pid, executable))
                break
    return result


def assert_safe(root, target, inspector=None, build_directory=None):
    """构建前检查所有模式/架构，防止共享原生资源或 clean 影响运行中的应用。"""
    if target not in (*PLATFORMS, 'all'):
        raise GuardError('Expected desktop target: macos, windows, linux or all.')
    host = current_platform()
    if inspector is None:
        inspector_type = {'macos': MacosInspector, 'windows': WindowsInspector, 'linux': LinuxInspector}.get(host)
        if inspector_type is None:
            raise GuardError('Cannot inspect applications on this platform; build cancelled.')
        inspector = inspector_type()
    directory = build_directory if build_directory is not None else configured_build_directory(root)
    matches = conflicting_processes(root, target, inspector.executables(), directory)
    if matches:
        details = '\n'.join(f'  PID {pid}: {path}' for pid, path in matches)
        raise GuardError(
            'Build cancelled: Remlark is running from the target build directory.\n'
            f'{details}\n'
            'Please quit it normally before building. No process was terminated.\n'
            '构建已停止：请先正常退出以上构建目录中的应用，避免覆盖原生库导致崩溃；不会自动断开连接。')
