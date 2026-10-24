"""桌面进程检查接口；各平台只负责返回进程号与真实可执行文件路径。"""
from abc import ABC, abstractmethod
import subprocess


class GuardError(RuntimeError):
    """检查失败时拒绝继续构建，避免把未知状态当作没有运行实例。"""


class ProcessInspector(ABC):
    """统一三个桌面平台的进程枚举接口，不向进程发送退出或终止信号。"""

    @abstractmethod
    def executables(self):
        """返回 (pid, executable_path) 列表，无法检查时抛出 GuardError。"""


def run_query(arguments, *, environment=None):
    """以参数列表运行只读查询，允许平台指定子进程环境，限制等待且不泄漏输出。"""
    # ARM runner 上 PowerShell + WMI 冷启动可能超过 10 秒，上限放宽到 60 秒。
    try:
        result = subprocess.run(arguments, capture_output=True, text=True,
                                encoding='utf-8', errors='replace', timeout=60,
                                env=environment)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise GuardError('Cannot inspect running applications; build cancelled.') from error
    if result.returncode != 0:
        raise GuardError('Cannot inspect running applications; build cancelled.')
    return result.stdout
