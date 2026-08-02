# -*- coding: utf-8 -*-
"""探查玩家表 band3 的精细行结构，确定 jump 与 crouch/pickup 的分界。"""
import os
from PIL import Image
import numpy as np
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "my chest资料库")

img = Image.open(os.path.join(SRC, "游戏角色多视图.png")).convert("RGBA")
a = np.array(img)
h, w = a.shape[:2]
rgb = a[:, :, :3].astype(int)
alpha = a[:, :, 3]
bg = rgb[0, 0]
dist = np.abs(rgb - bg).sum(axis=2)
ink = (dist >= 60) & (alpha >= 10)

# 打印 band3 区域 [830,1530) 的行投影，找空隙
for y0, y1 in [(830, 1530)]:
    sub = ink[y0:y1, :]
    proj = sub.sum(axis=1)
    # 找全零行段
    zero_runs = []
    run_start = None
    for i, v in enumerate(proj):
        if v == 0 and run_start is None:
            run_start = i
        elif v != 0 and run_start is not None:
            zero_runs.append((y0 + run_start, y0 + i - 1, i - run_start))
            run_start = None
    if run_start is not None:
        zero_runs.append((y0 + run_start, y0 + len(proj) - 1, len(proj) - run_start))
    print(f"region [{y0},{y1}) zero-runs (start,end,len):")
    for z in zero_runs:
        if z[2] >= 3:
            print("  ", z)
    # 非零行段
    nz = []
    run_start = None
    for i, v in enumerate(proj):
        if v != 0 and run_start is None:
            run_start = i
        elif v == 0 and run_start is not None:
            nz.append((y0 + run_start, y0 + i - 1))
            run_start = None
    if run_start is not None:
        nz.append((y0 + run_start, y0 + len(proj) - 1))
    print("  non-zero row segments:")
    for s in nz:
        print("   ", s, "h=", s[1] - s[0] + 1)
