#!/usr/bin/env python3
"""
驭电（YUDIAN）App Icon 生成器
- 1024×1024、无 alpha、无圆角（iOS 负责裁切）
- 4× 超采样 + LANCZOS 缩放
用法: python3 tools/make_icon.py out.png [preview]
"""
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

SIZE = 1024
SS = 4
W = SIZE * SS

INK_TOP = (14, 18, 27)
INK_BOT = (4, 6, 11)
TEAL = (58, 235, 178)
CYAN = (54, 158, 255)
WHITE = (241, 245, 255)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def background(w):
    yy, xx = np.mgrid[0:w, 0:w].astype(np.float32)
    ny, nx = yy / w, xx / w

    # 垂直底色
    t = ny[..., None]
    top = np.array(INK_TOP, dtype=np.float32)
    bot = np.array(INK_BOT, dtype=np.float32)
    canvas = top[None, None, :] * (1 - t) + bot[None, None, :] * t

    def glow(cx, cy, radius, color, power=2.4, strength=1.0):
        d = np.sqrt((nx - cx) ** 2 + (ny - cy) ** 2) / radius
        return (np.clip(1 - d, 0, 1) ** power)[..., None] * np.array(color, np.float32) * strength

    # 中央偏上的冷色柔光 + 右上角一点蓝，形成体积感
    canvas += glow(0.50, 0.46, 0.62, (26, 82, 104), 2.6, 0.55)
    canvas += glow(0.66, 0.20, 0.50, (26, 54, 110), 2.8, 0.40)

    # 暗角
    d = np.sqrt((nx - 0.5) ** 2 + (ny - 0.5) ** 2) / 0.72
    canvas *= (1 - 0.42 * smoothstep(0.55, 1.25, d))[..., None]
    return np.clip(canvas, 0, 255).astype(np.uint8)


def bolt(cx, cy, height, scale_x=0.94):
    base = [(13, 2), (3, 14), (12, 14), (11, 22), (21, 10), (12, 10)]
    s = height / 20.0
    return [(cx + (x - 12) * s * scale_x, cy + (y - 12) * s) for x, y in base]


def draw_gauge_arc(d, cx, cy, radius, width, start_deg, end_deg, steps=1080):
    """带渐变的圆环弧；Pillow 的 arc 描边向圆心内侧生长，故 bbox 半径需补半宽"""
    r_box = radius + width / 2
    n = steps
    for i in range(n):
        a0 = start_deg + (end_deg - start_deg) * i / n
        a1 = start_deg + (end_deg - start_deg) * (i + 1) / n + 0.8
        t = i / (n - 1)
        col = tuple(int(TEAL[k] + (CYAN[k] - TEAL[k]) * t) for k in range(3))
        d.arc([cx - r_box, cy - r_box, cx + r_box, cy + r_box],
              start=a0, end=a1, fill=col + (255,), width=width)

    # 圆头收尾
    for ang, col in ((start_deg, TEAL), (end_deg, CYAN)):
        rad = math.radians(ang)
        px = cx + radius * math.cos(rad)
        py = cy + radius * math.sin(rad)
        d.ellipse([px - width / 2, py - width / 2, px + width / 2, py + width / 2],
                  fill=col + (255,))


def make(out, with_preview=False):
    bg = background(W)
    img = Image.fromarray(bg, "RGB").convert("RGBA")
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    cx = cy = W / 2
    radius = W * 0.318
    stroke = int(W * 0.049)

    # 仪表弧：开口朝下 240°
    draw_gauge_arc(d, cx, cy, radius, stroke, 150, 390)

    # 闪电：略高于几何中心，视觉上更稳
    pts = bolt(cx, cy + W * 0.018, W * 0.425)
    d.polygon(pts, fill=WHITE + (255,))

    img = Image.alpha_composite(img, layer)
    img = img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    img.save(out, format="PNG", optimize=True)

    if with_preview:
        # iOS 圆角预览 + 小尺寸检查
        mask = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1],
                                               radius=int(SIZE * 0.2237), fill=255)
        rounded = Image.new("RGB", (SIZE, SIZE), (255, 255, 255))
        rounded.paste(img, (0, 0), mask)
        rounded.save(out.replace(".png", "_rounded.png"))
        img.resize((120, 120), Image.LANCZOS).save(out.replace(".png", "_120.png"))
    return out


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "icon.png"
    preview = len(sys.argv) > 2 and sys.argv[2] == "preview"
    print(make(out, preview))
