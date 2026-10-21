#!/usr/bin/env python3
"""解压后运行此脚本，为当前用户安装应用菜单入口和图标，无需管理员权限。"""

import os
from pathlib import Path
import shutil
import subprocess


def main():
    """按当前 bundle 的绝对位置安装桌面入口，移动 bundle 后需重新运行。"""
    bundle = Path(__file__).resolve().parent
    if not (bundle / 'remlark').is_file():
        raise SystemExit('Run this script from the built bundle / 请从打包后的 bundle 运行')
    data = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
    applications = data / 'applications'
    applications.mkdir(parents=True, exist_ok=True)
    # 仅安装本应用 PNG，不能覆盖用户已有的 hicolor 主题索引。
    icons = bundle / 'share/icons'
    for source in icons.rglob('*.png'):
        target = data / 'icons' / source.relative_to(icons)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    desktop = (bundle / 'share/applications/com.remlark.remlark.desktop').read_text()
    # Desktop Entry 的 Exec 使用独立转义规则，保护空格、引号与字段占位符。
    executable = str(bundle / 'remlark').replace('%', '%%')
    for char in ('\\', '"', '`', '$'):
        executable = executable.replace(char, '\\' + char)
    executable = executable.replace('\\', '\\\\')
    # GIO 会先检查 Exec 的首个可执行文件，尚未展开 %%；使用 env 避免路径含 % 时被误判为不存在。
    desktop = desktop.replace('Exec=remlark', f'Exec=/usr/bin/env "{executable}"')
    (applications / 'com.remlark.remlark.desktop').write_text(desktop)
    if shutil.which('gtk-update-icon-cache'):
        subprocess.run(['gtk-update-icon-cache', '-f', '-t', str(data / 'icons/hicolor')], check=False)
    print('Remlark desktop entry installed / 已安装 Remlark 应用菜单入口')


if __name__ == '__main__':
    main()
