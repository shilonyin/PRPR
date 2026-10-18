
from PIL import Image, ImageDraw
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "PRPR", "Assets", "Square44x44Logo.targetsize-256_altform-unplated.png")
glyph_src = Image.open(SRC).convert("RGBA")

def plate(size, bg, radius_ratio=0.22):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=max(1, int(size * radius_ratio)), fill=255)
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    base.paste(Image.new("RGBA", (size, size), bg), (0, 0), m)
    return base

def compose(size, bg):
    # 小尺寸把图案放大一点，否则 16px 下方框和猫脸会糊成一团
    inner_ratio = 0.86 if size <= 24 else (0.80 if size <= 40 else (0.74 if size <= 72 else 0.68))
    base = plate(size, bg)
    inner = max(1, int(size * inner_ratio))
    glyph = glyph_src.copy()
    glyph.thumbnail((inner, inner), Image.LANCZOS)
    base.alpha_composite(glyph, ((size - glyph.width) // 2, (size - glyph.height) // 2))
    return base

SEED = (91, 106, 191, 255)      # AppTheme 的 seed 色 0xFF5B6ABF
DARK = (26, 26, 32, 255)        # 深色主题 AppBar 底色 0xFF1A1A20

# 1) 关于页 / UI 用的大图
compose(512, SEED).save(os.path.join(ROOT, "app", "assets", "app_logo.png"))

# 2) Windows 图标（exe、任务栏、开始菜单、桌面快捷方式都读它）
sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
icons = [compose(s, SEED) for s in sizes]
icons[-1].save(
    os.path.join(ROOT, "app", "windows", "runner", "resources", "app_icon.ico"),
    format="ICO",
    sizes=[(s, s) for s in sizes],
    append_images=icons[:-1],
)
print("png:", os.path.getsize(os.path.join(ROOT, "app", "assets", "app_logo.png")))
print("ico:", os.path.getsize(os.path.join(ROOT, "app", "windows", "runner", "resources", "app_icon.ico")))
