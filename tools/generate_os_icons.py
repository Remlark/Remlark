"""生成独立的系统 Logo PNG；依赖 Pillow、resvg-py，来源见 assets/os_icons/sources.json。"""

import hashlib
import io
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, urlopen

import resvg_py
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'os_icons'


def generate(item):
    """下载品牌原图并等比放入透明画布，保留透明边缘与源文件摘要。"""
    key, source = item
    with urlopen(Request(source['url'], headers={'User-Agent': 'Remlark-Icon-Generator/1.0'}), timeout=45) as response:
        raw = response.read()
    source['source_sha256'] = hashlib.sha256(raw).hexdigest()
    if source['url'].endswith('.svg'):
        raw = resvg_py.svg_to_bytes(svg_string=raw.decode(), width=256, height=256)
    picture = Image.open(io.BytesIO(raw)).convert('RGBA')
    bounds = picture.getbbox()
    if bounds:
        picture = picture.crop(bounds)
    # 方形标志视觉重量较大，允许在来源配置中单独增加留白。
    scale = source.get('content_size', 208) / max(picture.size)
    picture = picture.resize((round(picture.width * scale), round(picture.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (256, 256))
    canvas.alpha_composite(picture, ((256 - picture.width) // 2, (256 - picture.height) // 2))
    canvas.save(ROOT / f'{key}.png', optimize=True)
    return key, source


def main():
    """批量生成资源；失败直接退出，避免把不完整的下载当成成功。"""
    sources = json.loads((ROOT / 'sources.json').read_text())
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = dict(pool.map(generate, sources.items()))
    (ROOT / 'sources.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    print(f'Generated {len(results)} icons')


if __name__ == '__main__':
    main()
