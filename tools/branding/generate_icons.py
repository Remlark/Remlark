"""从透明品牌母版生成各平台图标；依赖 Pillow，运行后提交生成资源。"""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def main():
    """统一缩放母版，保留透明通道并导出 macOS、Windows、Linux 与 UI 资源。"""
    source = Image.open(ROOT / 'assets/branding/app_icon_source.png').convert('RGBA')
    targets = {'assets/branding/app_icon.png': 256}
    for size in (16, 32, 64, 128, 256, 512, 1024):
        targets[f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png'] = size
    for size in (16, 24, 32, 48, 64, 128, 256, 512):
        targets[f'linux/packaging/icons/hicolor/{size}x{size}/apps/com.remlark.remlark.png'] = size
    for relative, size in targets.items():
        path = ROOT / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        source.resize((size, size), Image.Resampling.LANCZOS).save(path)
    # 多尺寸 ICO 让桌面、任务栏与资源管理器按显示密度选择清晰帧。
    source.resize((256, 256), Image.Resampling.LANCZOS).save(
        ROOT / 'windows/runner/resources/app_icon.ico',
        sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)],
    )


if __name__ == '__main__':
    main()
