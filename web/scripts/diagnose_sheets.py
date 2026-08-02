# -*- coding: utf-8 -*-
"""诊断：打印每张表各动作的帧数，并把框选结果画出来肉眼校验。"""
import os, json
from PIL import Image, ImageDraw
import numpy as np
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "my chest资料库")


def load(name):
    return Image.open(os.path.join(SRC, name)).convert("RGBA")


def ink_mask(img):
    a = np.array(img)
    h, w = a.shape[:2]
    alpha = a[:, :, 3]
    rgb = a[:, :, :3].astype(int)
    corners = np.vstack([rgb[0, 0], rgb[0, w - 1], rgb[h - 1, 0], rgb[h - 1, w - 1]])
    bg = corners.mean(axis=0)
    dist = np.abs(rgb - bg).sum(axis=2)
    passable = (dist < 60) | (alpha < 10)
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if passable[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if passable[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True; q.append((ny, nx))
    ink = ~seen
    ink[alpha < 10] = False
    return ink


def bands(proj, min_gap=1, min_len=3):
    idx = np.nonzero(proj)[0]
    if len(idx) == 0:
        return []
    segs = []
    s = idx[0]; prev = idx[0]
    for i in idx[1:]:
        if i - prev > min_gap:
            if prev - s + 1 >= min_len:
                segs.append((s, prev + 1))
            s = i
        prev = i
    if prev - s + 1 >= min_len:
        segs.append((s, prev + 1))
    return segs


def diagnose(name, gap_values=(2, 6, 12)):
    img = load(name)
    a = np.array(img)
    ink = ink_mask(img)
    row_proj = ink.sum(axis=1)
    row_bands = bands(row_proj, min_gap=2, min_len=8)
    print(f"=== {name}: {len(row_bands)} row bands")
    for i, (y0, y1) in enumerate(row_bands):
        band = ink[y0:y1, :]
        counts = {}
        for g in gap_values:
            cb = bands(band.sum(axis=0), min_gap=g, min_len=6)
            counts[g] = len(cb)
        print(f"  band{i} y=[{y0},{y1}) h={y1-y0} cols(2/6/12)={counts[2]}/{counts[6]}/{counts[12]}")


for n in ["游戏角色多视图.png", "幽灵.png", "硫酸怪.png",
          "班主任动态图.png", "助教多视图.png", "化学老师多视图.png", "思维老师动态图.png"]:
    diagnose(n)
