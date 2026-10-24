# -*- coding: utf-8 -*-
"""生成 app_logo.png（关于页 512）与 app_icon.ico（exe/任务栏/快捷方式读的 9 档）。

**为什么不再复用 UWP 的 Square44x44Logo**：
新主题把强调色从靛蓝 0xFF5B6ABF 换成金色 #D8A657，导轨顶部的猫头也用
CustomPaint 画成金线矢量（ui/widgets/app_rail.dart 的 _CatPainter）。
原来的图标是蓝紫圆角底 + 白色方框猫头，摆在金色标题栏旁边是两套视觉，
所以这里按 _CatPainter 的同一条路径重画：金色圆角底 + 深色猫脸。

**为什么每档单独绘制而不是从 512 缩**：
16px 的图标如果从 512 缩下来，0.6px 宽的线条会被 LANCZOS 平均成灰边，
整只猫糊成一个方块。所以每个尺寸先以 8 倍尺寸单独绘制（线条粗细按比例
补偿），再缩到目标尺寸，等于自带超采样。
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

GOLD = (216, 166, 87, 255)      # AppPalette.dark.gold
INK = (20, 17, 10, 255)         # AppPalette.dark.onGold，金色实底上的深色
RADIUS_RATIO = 0.227            # 圆角约 22.7%，与 Windows 磁贴模板接近

SUPERSAMPLE = 8


def _bezier(p0, p1, p2, p3, steps=72):
    """三次贝塞尔采样成点列。PIL 只有直线，曲线得自己铺点。"""
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((
            u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
            u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
        ))
    return out


# 小尺寸要更粗的线、更小的脸：16px 下若照 512 的比例，线宽只有 0.6px。
# 档位与 app_icon.ico 里的尺寸一一对应。
def _metrics(size):
    if size <= 24:
        return 0.030, 0.082      # (脸的单位长度, 线宽/画布)
    if size <= 40:
        return 0.033, 0.072
    if size <= 64:
        return 0.034, 0.062
    return 0.034, 0.039


def render(size):
    """画一张 size x size 的图标。"""
    px = size * SUPERSAMPLE
    unit, lw_ratio = _metrics(size)
    k = px * unit
    lw = max(1, int(round(px * lw_ratio)))

    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        [0, 0, px - 1, px - 1],
        radius=int(px * RADIUS_RATIO),
        fill=GOLD,
    )

    cx, cy = px / 2, px / 2 + k * 0.35   # 视觉重心略下移，猫脸才不显得飘

    def P(dx, dy):
        return (cx + dx * k, cy + dy * k)

    # 脸：上半圆、下颏收一点，三段贝塞尔拼成。
    face = (
        _bezier(P(-7, -2), P(-7, 6), P(7, 6), P(7, -2))
        + _bezier(P(7, -2), P(7, -6.5), P(3.5, -7.5), P(0, -7.5))
        + _bezier(P(0, -7.5), P(-3.5, -7.5), P(-7, -6.5), P(-7, -2))
    )
    face.append(face[0])

    # 耳朵用实心三角，**先于脸绘制**，且两个根点一内一外跨在脸轮廓上：
    # 外侧根 (6.9, -4.6) 略超出脸的外沿（该处轮廓 x≈6.49，描边半宽 0.5），
    # 内侧根 (3.0, -6.6) 沉在脸内部（该处轮廓 x≈4.4）。
    # 这样三角横穿那圈描边，根部被后画的描边整段盖住。
    # 若只让三角搭在轮廓外侧，耳根会留一道 1-2px 透光缝；
    # 若脸先画、耳朵后画，实心三角又会压住描边，同样破相。
    for sx in (-1, 1):
        d.polygon([P(sx * 6.9, -4.6), P(sx * 6.2, -10.6), P(sx * 3.0, -6.6)], fill=INK)

    d.line(face, fill=INK, width=lw, joint="curve")


    # 两只眼：实心圆点。
    r = k * 1.15
    for sx in (-1, 1):
        ex, ey = P(sx * 3.2, -1.6)
        d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=INK)

    # 鼻子：朝下的小三角（一条短横线在粗笔宽下会画成圆角方块，不像鼻子）。
    d.polygon([P(-1.5, 2.2), P(1.5, 2.2), P(0, 3.8)], fill=INK)

    return img.resize((size, size), Image.LANCZOS)


def main():
    png_path = os.path.join(ROOT, "app", "assets", "app_logo.png")
    ico_path = os.path.join(ROOT, "app", "windows", "runner", "resources", "app_icon.ico")

    render(512).save(png_path)

    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    frames = [render(s) for s in sizes]
    frames[-1].save(
        ico_path,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=frames[:-1],
    )

    print("png:", os.path.getsize(png_path), "bytes")
    print("ico:", os.path.getsize(ico_path), "bytes")


if __name__ == "__main__":
    main()