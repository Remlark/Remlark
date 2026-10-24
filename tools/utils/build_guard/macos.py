"""macOS 通过 ps 的可执行文件列检查，保留路径中的空格和中文。"""
from .inspector import GuardError, ProcessInspector, run_query


class MacosInspector(ProcessInspector):
    """读取完整可执行路径，不使用可能截断或包含参数的命令行列。"""

    def executables(self):
        """解析 PID 与 comm；只检查 Remlark，其他进程不进入错误提示。"""
        rows = []
        for line in run_query(['/bin/ps', '-ax', '-o', 'pid=', '-o', 'comm=']).splitlines():
            fields = line.strip().split(None, 1)
            if len(fields) != 2 or not fields[0].isdigit():
                raise GuardError('Unexpected process query output; build cancelled.')
            if fields[1].endswith('/remlark'):
                rows.append((int(fields[0]), fields[1]))
        return rows
