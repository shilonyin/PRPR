# -*- coding: utf-8 -*-
"""重绘 app_icon.ico：金色圆角底 + 深色线框猫脸，与导轨 _CatPainter 同形。

原来的图标是蓝紫底 + 白色方框猫头（0xFF5B6ABF 时代的品牌色）。
新主题把强调色换成金色 #D8A657，导轨顶部的猫头也是同一条矢量路径，
标题栏沿用旧图标会显得两套视觉并存 —— 所以按同一路径重画。

小尺寸（16/20/24）必须靠实底 + 深色线条才看得清，
纯线框金线在 16px 会糊成一片，所以底色取金色、线条取深色。
"""
import os

from PIL import Image, ImageDraw

# 脚本放在 automation/designs/ 下，仓库根是往上两级。
# 原来这里写死了本机绝对路径，换台机器就跑不了。
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

S = 1024                      # 超高分辨率绘制，最后缩到各档，自带抗锯齿
GOLD = (216, 166, 87, 255)    # AppPalette.dark.gold
INK = (20, 17, 10, 255)       # AppPalette.dark.onGold
RADIUS = 232                  # 圆角约 22.7%，Windows 磁贴/任务栏都好看

def bez(p0, p1, p2, p3, n=64):
    """三次贝塞尔采样成点列。PIL 没有曲线 API，只能自己铺点。"""
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0]
        y = u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1]
        out.append((x, y))
    return out

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle([0, 0, S - 1, S - 1], radius=RADIUS, fill=GOLD)

cx, cy = S / 2, S / 2 + 14          # 视觉重心略下移，猫脸才不显得飘
k = 34.0                            # 1 单位 = 34px（路径按 24 单位设计；留出四周呼吸位）
lw = 40

def P(dx, dy):
    return (cx + dx * k, cy + dy * k)

face = bez(P(-7, -2), P(-7, 6), P(7, 6), P(7, -2)) \
     + bez(P(7, -2), P(7, -6.5), P(3.5, -7.5), P(0, -7.5)) \
     + bez(P(0, -7.5), P(-3.5, -7.5), P(-7, -6.5), P(-7, -2))
face.append(face[0])
d.line(face, fill=INK, width=lw, joint="curve")

# 耳朵用实心三角：描边三角的根部会和脸留下 1-2px 缝隙，
# 缩到 16px 时这条缝隙变成一圈灰边，整只猫就糊成一个方块。
for sx in (-1, 1):
    d.polygon([P(sx*6.9, -4.6), P(sx*6.2, -10.6), P(sx*2.3, -7.6)], fill=INK)

# 两只眼：实心圆点 + 一条鼻线，和导轨 24px 的版本同构
r = 1.15 * k
for sx in (-1, 1):
    ex, ey = P(sx*3.2, -1.6)
    d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=INK)
# 鼻子：朝下的小三角。原设计是一条 3 单位横线，但笔宽 40px 时
# 线长(102px)只比线宽大一点，画出来是一个圆角方块，不像鼻子。
d.polygon([P(-1.5, 2.2), P(1.5, 2.2), P(0, 3.8)], fill=INK)

master = os.path.join(ROOT, "automation", "tmp", "icon-master.png")
os.makedirs(os.path.dirname(master), exist_ok=True)
img.save(master)

sizes = [(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48),
         (64, 64), (128, 128), (256, 256)]
img.save(os.path.join(ROOT, "app", "windows", "runner", "resources", "app_icon.ico"),
         format="ICO", sizes=sizes)
print("saved", img.size, "->", len(sizes), "sizes")