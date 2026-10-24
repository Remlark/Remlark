"""Windows 通过 CIM 读取可执行路径，避免 tasklist 只按名称误拦已安装应用。"""
import json

from .inspector import GuardError, ProcessInspector, run_query


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
        output = run_query(['powershell', '-NoProfile', '-NonInteractive', '-Command', script])
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
