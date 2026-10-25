"""Linux 从 procfs 读取可执行路径，不依赖进程名匹配或命令行转义。"""
import os
from pathlib import Path

from .inspector import GuardError, ProcessInspector


class LinuxInspector(ProcessInspector):
    """枚举 procfs；无权限识别同名主机进程时拒绝继续构建。"""

    def __init__(self, proc=Path('/proc')):
        """允许隔离测试提供 procfs 目录，生产环境固定读取系统 procfs。"""
        self.proc = proc

    def executables(self):
        """跳过已经退出的进程，保留被替换后带 deleted 标记的运行文件。"""
        rows = []
        try:
            entries = list(self.proc.iterdir())
        except OSError as error:
            raise GuardError('Cannot inspect /proc; build cancelled.') from error
        for entry in entries:
            if not entry.name.isdigit():
                continue
            try:
                path = os.readlink(entry / 'exe').removesuffix(' (deleted)')
            except FileNotFoundError:
                continue
            except PermissionError:
                try:
                    # procfs 不经过 ps 转义；读取名称也显式指定 UTF-8，兼容 C locale。
                    name = (entry / 'comm').read_text(encoding='utf-8').strip()
                except FileNotFoundError:
                    continue
                except OSError as error:
                    raise GuardError('Cannot identify a running process; build cancelled.') from error
                if name.lower() == 'remlark':
                    raise GuardError('Cannot inspect a running Remlark; build cancelled.')
                continue
            except OSError as error:
                raise GuardError('Cannot inspect a running executable; build cancelled.') from error
            if Path(path).name.lower() == 'remlark':
                rows.append((int(entry.name), path))
        return rows
