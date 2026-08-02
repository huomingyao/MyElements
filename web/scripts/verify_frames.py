# -*- coding: utf-8 -*-
"""校验：把切出的帧画到一张拼图上肉眼检查。"""
import os, json, re
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "my chest资料库")

# 读 frames.ts
with open(os.path.join(ROOT, "src", "gen", "frames.ts"), encoding="utf-8") as f:
    txt = f.read()
m = re.search(r"= (\{.*\})\s*$", txt, re.S)
frames = json.loads(m.group(1))

sheet_files = {
    "player": "游戏角色多视图.png", "ghost": "幽灵.png", "slime": "硫酸怪.png",
    "mentor_monitor": "班主任动态图.png", "mentor_assistant": "助教多视图.png",
    "mentor_chem": "化学老师多视图.png", "mentor_think": "思维老师动态图.png",
}

checks = [
    ("player", "idle"), ("player", "run"), ("player", "jump"), ("player", "death"),
    ("ghost", "run"), ("ghost", "death"),
    ("slime", "run"), ("slime", "death"),
    ("mentor_monitor", "idle"), ("mentor_chem", "idle"),
    ("mentor_assistant", "synthesize"), ("mentor_think", "idle"),
]

CELL = 150
cols = 8
rows = (len(checks) + cols - 1) // cols
canvas = Image.new("RGB", (cols * CELL, rows * CELL), (40, 40, 50))
from PIL import ImageDraw
d = ImageDraw.Draw(canvas)

for i, (sheet, act) in enumerate(checks):
    img = Image.open(os.path.join(SRC, sheet_files[sheet])).convert("RGBA")
    rects = frames[sheet][act]
    # 拼接该动作所有帧缩略图横向放进 cell 上部分
    n = len(rects)
    tw = CELL - 8
    fh = 100
    x_off = 4
    cell_x = (i % cols) * CELL
    cell_y = (i // cols) * CELL
    per_w = max(1, tw // n)
    for j, r in enumerate(rects):
        x, y, w, h = r["x"], r["y"], r["w"], r["h"]
        fr = img.crop((x, y, x + w, y + h))
        scale = min(per_w / w, fh / h)
        fr = fr.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.NEAREST)
        canvas.paste(fr, (cell_x + x_off + j * per_w, cell_y + 4), fr)
    d.text((cell_x + 4, cell_y + CELL - 16), f"{sheet}.{act}({n})", fill=(255, 255, 100))

out = os.path.join(ROOT, "scripts", "_grid", "verify_frames.png")
canvas.save(out)
print(out)
