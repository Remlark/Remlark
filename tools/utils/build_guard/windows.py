"""Windows 通过 CIM 读取可执行路径，避免 tasklist 只按名称误拦已安装应用。"""
import json
import os

from .inspector import GuardError, ProcessInspector, run_query


def windows_powershell_environment():
    """从 pwsh 7 启动 5.1 时会继承 7 的模块路径，导致 CimCmdlets 等内置模块加载失败或变慢；重置为 5.1 默认目录。"""
    system_root = os.environ.get('SystemRoot', r'C:\Windows')
    program_files = os.environ.get('ProgramFiles', r'C:\Program Files')
    return dict(os.environ, PSModulePath=(
        rf'{program_files}\WindowsPowerShell\Modules;'
        rf'{system_root}\system32\WindowsPowerShell\v1.0\Modules'))


class WindowsInspector(ProcessInspector):
    """PowerShell 只查询 remlark.exe 的路径与 PID，不读取命令行或凭据。"""

    def executables(self):
        """统一单个和多个 CIM 结果，并在路径不可读时阻止覆盖。"""
        # 与 macOS 的查询环境隔离；PowerShell 直接固定 UTF-8 输出，不依赖调用方 locale。
        script = (
            "$ErrorActionPreference='Stop'; "
            "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); "
            "@(Get-CimInstance Win32_Process -Filter \"Name='remlark.exe'\" | "
            "Select-Object ProcessId,ExecutablePath) | ConvertTo-Json -Compress"
        )
        output = run_query(['powershell', '-NoProfile', '-NonInteractive', '-Command', script],
                           environment=windows_powershell_environment())
        try:
            decoded = json.loads(output.lstrip('\ufeff')) if output.strip() else []
            decoded = [decoded] if isinstance(decoded, dict) else decoded
            rows = []
            for row in decoded:
                if not isinstance(row, dict):
                    raise ValueError('invalid process entry')
                path = row.get('ExecutablePath')
                if not isinstance(path, str) or not path:
                    raise ValueError('unreadable path')
                rows.append((int(row['ProcessId']), path))
            return rows
        except (ValueError, KeyError, TypeError) as error:
            raise GuardError('Cannot inspect a running Remlark; build cancelled.') from error
