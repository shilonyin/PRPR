import os

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
import os
src = Image.open(os.path.join(ROOT, "docs", "screenshots", "search.png")).convert("RGB")
print("src", src.size)
out = os.path.join(ROOT, "automation", "designs", "assets")
os.makedirs(out, exist_ok=True)
crops = {
  "tile-a.jpg": (600,240,890,655),
  "tile-b.jpg": (910,240,1200,655),
  "tile-c.jpg": (1210,240,1500,640),
  "tile-d.jpg": (290,240,580,420),
  "tile-e.jpg": (290,430,580,890),
  "tile-f.jpg": (600,670,890,1070),
}
for name,(l,t,r,b) in crops.items():
    c = src.crop((l,t,r,b))
    c.save(os.path.join(out,name), quality=90)
    print(name, c.size)
