import os

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
src = Image.open(os.path.join(ROOT, "docs", "screenshots", "search.png")).convert("RGB")
out = os.path.join(ROOT, "automation", "designs", "assets")
# (left, top, right, bottom) —— 从 2022x1341 里再切几个不同构图
crops = {
 "g1.jpg": (390,255,860,900),     # 大竖图
 "g2.jpg": (920,660,1420,1300),
 "g3.jpg": (1430,660,1900,1341),
 "g4.jpg": (1440,250,1990,640),
 "g5.jpg": (300,200,780,700),
 "g6.jpg": (910,250,1420,640),
}
for name,(l,t,r,b) in crops.items():
    c = src.crop((l,t,r,b))
    c.save(out + "/" + name, quality=88)
    print(name, c.size)
