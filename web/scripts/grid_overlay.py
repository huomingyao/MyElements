# -*- coding: utf-8 -*-
"""在精灵表上画坐标网格，便于目测切割边界。"""
import os, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "my chest资料库")
OUT = os.path.join(ROOT, "scripts", "_grid")
os.makedirs(OUT, exist_ok=True)

name = sys.argv[1] if len(sys.argv) > 1 else "游戏角色多视图.png"
y0 = int(sys.argv[2]) if len(sys.argv) > 2 else 0
y1 = int(sys.argv[3]) if len(sys.argv) > 3 else 2400

img = Image.open(os.path.join(SRC, name)).convert("RGB")
img = img.crop((0, y0, img.width, y1))
d = ImageDraw.Draw(img)
for y in range(0, img.height, 50):
    d.line([(0, y), (img.width, y)], fill=(255, 0, 0), width=1)
    d.text((2, y + 1), str(y0 + y), fill=(255, 0, 0))
for x in range(0, img.width, 100):
    d.line([(x, 0), (x, img.height)], fill=(0, 100, 255), width=1)
    d.text((x + 1, 2), str(x), fill=(0, 100, 255))
out = os.path.join(OUT, f"grid_{name}_{y0}_{y1}.png")
img.save(out)
print(out)
