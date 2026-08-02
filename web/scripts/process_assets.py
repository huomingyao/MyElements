# -*- coding: utf-8 -*-
"""
素材处理管线 v2（显式配置驱动）：
1. 五张地图背景裁剪
2. 精灵表：按显式 (action, rect, expected) 配置切帧 -> src/gen/frames.ts
3. 导师立绘 trim
4. 背包 UI 面板裁剪
5. 程序化图标
6. 音乐拷贝
"""
import os, json, shutil
from PIL import Image
import numpy as np
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "my chest资料库")
OUT_ART = os.path.join(ROOT, "public", "assets", "art")
OUT_AUDIO = os.path.join(ROOT, "public", "assets", "audio", "bgm")
GEN_TS = os.path.join(ROOT, "src", "gen")

for d in [OUT_ART, OUT_AUDIO, GEN_TS,
          os.path.join(OUT_ART, "maps"), os.path.join(OUT_ART, "chars"),
          os.path.join(OUT_ART, "mentors"), os.path.join(OUT_ART, "icons"),
          os.path.join(OUT_ART, "ui")]:
    os.makedirs(d, exist_ok=True)


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


# ---------- 1. 地图背景 ----------
def crop_map(src_name, out_name, cut_y=None, max_scan=0.75):
    img = load(src_name)
    a = np.array(img)
    h, w = a.shape[:2]
    if cut_y is None:
        dark = (a[:, :, :3].sum(axis=2) < 120)
        cut_y = int(h * 0.41)
        for y in range(60, int(h * max_scan)):
            if dark[y].mean() > 0.97 and dark[y + 1].mean() > 0.97:
                cut_y = y
                break
    img.crop((0, 0, w, cut_y)).save(os.path.join(OUT_ART, "maps", out_name))
    print(f"map {out_name}: {w}x{cut_y}")


crop_map("地图一.png", "grassland.png")
crop_map("地图二.png", "camp.png")
crop_map("地图三.png", "mine.png")
crop_map("地图4.png", "saltlake.png", max_scan=0.8)
crop_map("地图5.png", "academy.png", cut_y=420)


# ---------- 2. 精灵表切帧（显式配置）----------
def col_bands(proj, min_gap=6, min_len=6):
    idx = np.nonzero(proj)[0]
    if len(idx) == 0:
        return []
    segs = []
    s = idx[0]; prev = idx[0]
    for i in idx[1:]:
        if i - prev > min_gap:
            if prev - s + 1 >= min_len:
                segs.append([s, prev + 1])
            s = i
        prev = i
    if prev - s + 1 >= min_len:
        segs.append([s, prev + 1])
    return segs


def slice_action(ink, rgb, rect, expected):
    """在 rect=(x0,y0,x1,y1) 内切 expected 帧。"""
    x0, y0, x1, y1 = rect
    sub = ink[y0:y1, x0:x1]
    bands = col_bands(sub.sum(axis=0), min_gap=6)
    blocks = []
    for (cx0, cx1) in bands:
        w = cx1 - cx0; h = y1 - y0
        if w < 14 or w * h < 1500:
            continue
        bx0, by0, bx1, by1 = x0 + cx0, y0, x0 + cx1, y1
        bright = rgb[by0:by1, bx0:bx1].astype(float).mean()
        if bright < 46:  # 黑色文字
            continue
        blocks.append([cx0, cx1])
    if not blocks:
        return []
    # 过滤微小碎屑（面积 < 中位数 15%）
    areas = [(b[1] - b[0]) for b in blocks]
    med = sorted(areas)[len(areas) // 2]
    blocks = [b for b in blocks if (b[1] - b[0]) >= med * 0.22]
    # 过多 -> 合并最近的相邻块
    while len(blocks) > expected:
        gaps = [(blocks[i + 1][0] - blocks[i][1], i) for i in range(len(blocks) - 1)]
        gaps.sort()
        i = gaps[0][1]
        blocks[i][1] = blocks[i + 1][1]
        del blocks[i + 1]
    # 不足 -> 在最宽块的内部最大空隙处分裂
    while 0 < len(blocks) < expected:
        blocks.sort(key=lambda b: b[1] - b[0])
        widest = blocks[-1]
        seg = sub[:, widest[0]:widest[1]]
        proj = seg.sum(axis=0)
        # 找内部最长零列段
        best_len, best_at = 0, None
        run = None
        for i, v in enumerate(proj):
            if v == 0 and run is None:
                run = i
            elif v != 0 and run is not None:
                if i - run > best_len:
                    best_len, best_at = i - run, run
                run = None
        if run is not None and len(proj) - run > best_len:
            best_len, best_at = len(proj) - run, run
        if best_at is None or best_len < 3:
            break
        cut = widest[0] + best_at + best_len // 2
        blocks[-1] = [widest[0], cut]
        blocks.append([cut, widest[1]])
    blocks.sort(key=lambda b: b[0])
    # trim 到内容
    rects = []
    for (cx0, cx1) in blocks:
        seg = sub[:, cx0:cx1]
        ys = np.nonzero(seg.any(axis=1))[0]
        xs = np.nonzero(seg.any(axis=0))[0]
        if len(ys) == 0 or len(xs) == 0:
            continue
        fx0 = x0 + cx0 + xs[0]; fx1 = x0 + cx0 + xs[-1] + 1
        fy0 = y0 + ys[0]; fy1 = y0 + ys[-1] + 1
        rects.append([int(fx0), int(fy0), int(fx1 - fx0), int(fy1 - fy0)])
    return rects


# sheet: (src, [(action, rect(x0,y0,x1,y1), expected)])
SHEETS = {
    "player": ("游戏角色多视图.png", [
        ("idle",     (0, 115, 1792, 441), 4),
        ("run",      (0, 456, 1792, 838), 8),
        ("jump",     (300, 860, 1700, 1175), 6),
        ("crouch",   (0, 1245, 720, 1500), 3),
        ("pickup",   (740, 1245, 1792, 1500), 4),
        ("death",    (0, 1518, 1792, 1781), 5),
        ("crafting", (0, 1788, 1792, 2068), 5),
        ("learning", (0, 2193, 1792, 2392), 4),
    ]),
    "ghost": ("幽灵.png", [
        ("idle",  (0, 114, 1792, 345), 4),
        ("run",   (0, 449, 1792, 642), 8),
        ("jump",  (0, 658, 1792, 984), 6),
        ("death", (0, 1550, 1000, 1773), 5),
        ("craft", (0, 1837, 1000, 2086), 4),
        ("listen",(0, 2141, 1000, 2355), 4),
    ]),
    "slime": ("硫酸怪.png", [
        ("run",        (0, 97, 1792, 317), 6),
        ("jump",       (0, 360, 1792, 676), 5),
        ("crouch",     (0, 802, 1792, 991), 4),
        ("death",      (0, 1372, 1792, 1658), 6),
        ("synthesize", (0, 1770, 1792, 2032), 6),
        ("listen",     (0, 2047, 1792, 2356), 4),
    ]),
    "mentor_monitor": ("班主任动态图.png", [
        ("idle", (0, 20, 1376, 245), 4),
        ("walk", (1376, 20, 2752, 245), 4),
        ("cast", (0, 266, 2752, 748), 6),
        ("happy",(0, 752, 2752, 935), 6),
        ("write",(0, 956, 2752, 1140), 8),
        ("sleep",(0, 1185, 2752, 1318), 4),
        ("hammer",(0, 1322, 2752, 1525), 8),
    ]),
    "mentor_assistant": ("助教多视图.png", [
        ("run",        (0, 113, 1792, 360), 8),
        ("jump",       (0, 384, 1792, 744), 4),
        ("crouch",     (0, 766, 1792, 1087), 4),
        ("pickup",     (0, 1115, 1792, 1416), 4),
        ("death",      (0, 1451, 1792, 1735), 4),
        ("synthesize", (0, 1812, 1792, 2065), 5),
        ("teach",      (0, 2141, 1792, 2395), 4),
    ]),
    "mentor_chem": ("化学老师多视图.png", [
        ("idle",  (0, 82, 1792, 365), 4),
        ("run",   (0, 384, 1792, 721), 8),
        ("jump",  (0, 742, 1792, 1124), 7),
        ("squat", (40, 1205, 800, 1450), 3),
        ("pickup",(840, 1205, 1792, 1450), 3),
        ("death", (0, 1488, 1792, 1748), 5),
        ("craft", (0, 1769, 1792, 2083), 6),
        ("teach", (0, 2111, 1792, 2357), 5),
    ]),
    "mentor_think": ("思维老师动态图.png", [
        ("idle",    (0, 52, 880, 286), 4),
        ("run",     (0, 442, 1792, 660), 8),
        ("jump",    (0, 697, 1792, 1006), 6),
        ("crouch",  (0, 1117, 1792, 1291), 2),
        ("pickup",  (40, 1400, 830, 1620), 4),
        ("death",   (880, 1400, 1792, 1620), 4),
        ("crafting",(0, 1747, 1792, 1981), 5),
        ("teaching",(0, 2122, 1792, 2370), 6),
    ]),
}

def apply_transparency(img, ink):
    """把泛洪背景像素置透明，返回新图。"""
    a = np.array(img).copy()
    a[~ink] = (0, 0, 0, 0)
    return Image.fromarray(a)


frames = {}
for key, (src_name, actions) in SHEETS.items():
    img = load(src_name)
    rgb = np.array(img)[:, :, :3]
    ink = ink_mask(img)
    result = {}
    for (act, rect, expected) in actions:
        rects = slice_action(ink, rgb, rect, expected)
        if rects:
            result[act] = rects
            flag = "" if len(rects) == expected else f"  !! expected {expected}"
            print(f"  {key}.{act}: {len(rects)}{flag}")
    apply_transparency(img, ink).save(os.path.join(OUT_ART, "chars", f"{key}.png"))
    frames[key] = result

# 导师 idle 兜底
if "idle" not in frames["mentor_assistant"] and "synthesize" in frames["mentor_assistant"]:
    frames["mentor_assistant"]["idle"] = frames["mentor_assistant"]["synthesize"][:2]

with open(os.path.join(GEN_TS, "frames.ts"), "w", encoding="utf-8") as f:
    f.write("// 由 scripts/process_assets.py 自动生成，勿手改\n")
    f.write("export interface FrameRect { x: number; y: number; w: number; h: number }\n")
    f.write("export const SPRITE_FRAMES: Record<string, Record<string, FrameRect[]>> = ")
    obj_frames = {
        sheet: {
            act: [{"x": r[0], "y": r[1], "w": r[2], "h": r[3]} for r in rects]
            for act, rects in actions.items()
        }
        for sheet, actions in frames.items()
    }
    f.write(json.dumps(obj_frames, ensure_ascii=False))
    f.write("\n")
print("frames.ts written")


# ---------- 3. 导师立绘 trim ----------
def trim_portrait(src_name, out_name):
    img = load(src_name)
    ink = ink_mask(img)
    ys = np.nonzero(ink.any(axis=1))[0]
    xs = np.nonzero(ink.any(axis=0))[0]
    box = (int(xs[0]), int(ys[0]), int(xs[-1] + 1), int(ys[-1] + 1))
    apply_transparency(img, ink).crop(box).save(os.path.join(OUT_ART, "mentors", out_name))
    print(f"portrait {out_name}: {box[2]-box[0]}x{box[3]-box[1]}")


trim_portrait("化学老师.png", "chem.png")
trim_portrait("班主任.png", "monitor.png")
trim_portrait("助教.png", "assistant.png")
trim_portrait("思维老师.png", "think.png")


# ---------- 4. 背包 UI ----------
def split_inventory(src_name):
    img = load(src_name)
    a = np.array(img)
    rgb = a[:, :, :3].astype(int)
    bg = rgb[5, 5]
    dist = np.abs(rgb - bg).sum(axis=2)
    ink = dist > 60
    proj = ink.sum(axis=0)
    idx = np.nonzero(proj)[0]
    segs = []
    s = idx[0]; prev = idx[0]
    for i in idx[1:]:
        if i - prev > 4:
            if prev - s + 1 >= 200:
                segs.append((s, prev + 1))
            s = i
        prev = i
    if prev - s + 1 >= 200:
        segs.append((s, prev + 1))
    names = ["panel_inventory.png", "panel_craft.png"]
    for i, (x0, x1) in enumerate(segs[:2]):
        sub_ink = ink[:, x0:x1]
        ys = np.nonzero(sub_ink.any(axis=1))[0]
        y0, y1 = int(ys[0]), int(ys[-1] + 1)
        img.crop((int(x0), y0, int(x1), y1)).save(os.path.join(OUT_ART, "ui", names[i]))
        print(f"ui {names[i]}: {x1-x0}x{y1-y0}")


split_inventory("背包.png")


# ---------- 5. 程序化图标（仅生成没有真实素材的 id）----------
# 已有真实美术（16种基本物质.png / 九种物品.png 抠图）的 id 不再程序生成
REAL_ART_IDS = {
    "o2", "h2", "c", "s", "co", "co2", "h2o", "h2o_clean", "caco3", "fe2o3",
    "cuso4", "hcl", "naoh", "caoh2", "fe", "crude_salt", "nacl",
    "sulfur_torch", "neutral_spray", "activated_carbon", "extinguisher",
    "oxygen_tank", "soap_water", "stick", "cu", "nahco3",
}
PALETTE = {
    "o2": (111, 214, 232), "h2": (191, 238, 247), "c": (34, 31, 46),
    "s": (255, 217, 74), "co": (107, 100, 120), "co2": (164, 158, 174),
    "h2o": (47, 159, 196), "h2o_clean": (111, 214, 232),
    "caco3": (168, 144, 120), "fe2o3": (138, 107, 74), "cuso4": (47, 159, 196),
    "hcl": (255, 163, 46), "naoh": (242, 240, 245), "caoh2": (226, 226, 230),
    "fe": (192, 200, 216), "crude_salt": (200, 190, 170), "nacl": (250, 250, 252),
    "sulfur_torch": (226, 84, 43), "neutral_spray": (148, 194, 42),
    "activated_carbon": (34, 31, 46), "carbon_mask": (63, 58, 77),
    "extinguisher": (226, 84, 43), "oxygen_tank": (111, 214, 232),
    "soap_water": (191, 238, 247), "stick": (138, 107, 74),
    "cu": (226, 132, 43), "nahco3": (242, 240, 245),
}
SHAPES = {"单质": "orb", "化合物": "flask", "氧化物": "diamond", "酸": "bottle", "碱": "bottle", "盐": "cube"}


def draw_icon(id_, category=None, type_=None):
    S = 4
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    color = PALETTE.get(id_, (164, 158, 174))
    dark = tuple(max(0, c - 70) for c in color)
    light = tuple(min(255, c + 60) for c in color)
    shape = SHAPES.get(category, "orb")
    if type_ == "equip":
        shape = "shield"
    elif type_ == "consume":
        shape = "bottle"
    elif type_ == "material":
        shape = "bar"
    def px(x0, y0, x1, y1, c):
        d.rectangle([x0 * S, y0 * S, x1 * S - 1, y1 * S - 1], fill=c)
    if shape == "orb":
        d.ellipse([3 * S, 3 * S, 13 * S - 1, 13 * S - 1], fill=color, outline=dark, width=S)
        d.ellipse([5 * S, 4 * S, 7 * S - 1, 6 * S - 1], fill=light)
    elif shape == "flask":
        px(6, 2, 10, 5, dark)
        d.polygon([(6 * S, 5 * S), (10 * S, 5 * S), (13 * S, 14 * S), (3 * S, 14 * S)], fill=color, outline=dark)
        px(5, 10, 11, 13, light)
    elif shape == "diamond":
        d.polygon([(8 * S, 2 * S), (14 * S, 8 * S), (8 * S, 14 * S), (2 * S, 8 * S)], fill=color, outline=dark)
        d.polygon([(8 * S, 4 * S), (11 * S, 8 * S), (8 * S, 10 * S)], fill=light)
    elif shape == "bottle":
        px(6, 2, 10, 4, dark)
        px(5, 4, 11, 14, color)
        d.rectangle([5 * S, 4 * S, 11 * S - 1, 14 * S - 1], outline=dark, width=S)
        px(6, 8, 10, 13, light)
    elif shape == "cube":
        px(3, 5, 13, 14, color)
        d.rectangle([3 * S, 5 * S, 13 * S - 1, 14 * S - 1], outline=dark, width=S)
        px(4, 6, 12, 8, light)
    elif shape == "shield":
        d.polygon([(3 * S, 3 * S), (13 * S, 3 * S), (13 * S, 9 * S), (8 * S, 14 * S), (3 * S, 9 * S)], fill=color, outline=dark)
        px(6, 5, 10, 8, light)
    elif shape == "bar":
        px(2, 7, 14, 10, color)
        d.rectangle([2 * S, 7 * S, 14 * S - 1, 10 * S - 1], outline=dark, width=S)
        px(3, 7, 6, 8, light)
    img.save(os.path.join(OUT_ART, "icons", f"{id_}.png"))


for sid, cat in [("o2","单质"),("h2","单质"),("c","单质"),("s","单质"),("co","化合物"),
                 ("co2","化合物"),("h2o","化合物"),("h2o_clean","化合物"),("caco3","盐"),
                 ("fe2o3","氧化物"),("cuso4","盐"),("hcl","酸"),("naoh","碱"),
                 ("caoh2","碱"),("fe","单质"),("crude_salt","盐"),("nacl","盐")]:
    if sid not in REAL_ART_IDS:
        draw_icon(sid, category=cat)
for iid, t in [("sulfur_torch","equip"),("neutral_spray","consume"),("activated_carbon","consume"),
               ("carbon_mask","equip"),("extinguisher","consume"),("oxygen_tank","consume"),
               ("soap_water","consume"),("stick","material"),("cu","material"),("nahco3","material")]:
    if iid not in REAL_ART_IDS:
        draw_icon(iid, type_=t)
draw_icon("placeholder", category="化合物")
print("icons done")


# ---------- 5b. 真实美术图标抠图（16种基本物质 / 九种物品）----------
def cut_grid_icons(src_name, cols, rows, cell_map, cut_ratio=0.70):
    """按等分网格抠出每格图形区，文字行检测+比例兜底切除文字，去白底透明化。"""
    img = load(src_name)
    w, h = img.size
    cw = w / cols
    ch = h / rows
    for (row, col), icon_id in cell_map.items():
        x0 = int(round(col * cw))
        y0 = int(round(row * ch))
        x1 = int(round((col + 1) * cw))
        y1 = int(round((row + 1) * ch))
        cell = np.array(img.crop((x0 + 7, y0 + 7, x1 - 7, y1 - 7)))
        ch_h, ch_w = cell.shape[:2]
        rgb = cell[:, :, :3].astype(int)
        alpha = cell[:, :, 3]
        # 仅“极白”像素视为背景候选（实测：背景≈251，白色物体本体≈226~236，阈值取 243）
        mx = rgb.max(axis=2); mn = rgb.min(axis=2)
        near_white = ((mx - mn) < 18) & (rgb.mean(axis=2) > 243)
        passable = near_white | (alpha < 10)
        # 从边界泛洪，背景精确识别
        seen = np.zeros((ch_h, ch_w), bool)
        from collections import deque as _dq
        q = _dq()
        for xx in range(ch_w):
            for yy in (0, ch_h - 1):
                if passable[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True; q.append((yy, xx))
        for yy in range(ch_h):
            for xx in (0, ch_w - 1):
                if passable[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True; q.append((yy, xx))
        while q:
            yy, xx = q.popleft()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = yy + dy, xx + dx
                if 0 <= ny < ch_h and 0 <= nx < ch_w and passable[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; q.append((ny, nx))
        ink = ~seen
        ink[alpha < 10] = False
        # 文字切除：自 0.5 高度向下找首个 ≥4 行空带（该类图鉴格设计中，首个空带即图形与文字分界）
        row_ink = ink.sum(axis=1)
        cut_y = int(ch_h * cut_ratio)
        run = 0
        gap_start = None
        for yy in range(int(ch_h * 0.5), ch_h):
            if row_ink[yy] <= 3:
                if run == 0:
                    gap_start = yy
                run += 1
            else:
                if run >= 4:
                    cut_y = min(cut_y, gap_start)
                    break
                run = 0
        ink[cut_y:, :] = False
        ys = np.nonzero(ink.any(axis=1))[0]
        xs = np.nonzero(ink.any(axis=0))[0]
        if len(ys) == 0 or len(xs) == 0:
            continue
        out = cell.copy()
        out[~ink] = (0, 0, 0, 0)
        trimmed = Image.fromarray(out).crop((int(xs[0]), int(ys[0]), int(xs[-1] + 1), int(ys[-1] + 1)))
        trimmed.save(os.path.join(OUT_ART, "icons", f"{icon_id}.png"))
    print(f"cut icons from {src_name}: {len(cell_map)}")


SUBSTANCE_GRID = {
    (0, 0): "o2", (0, 1): "h2", (0, 2): "c", (0, 3): "s",
    (1, 0): "co", (1, 1): "co2", (1, 2): "h2o", (1, 3): "caco3",
    (2, 0): "fe2o3", (2, 1): "cuso4", (2, 2): "hcl", (2, 3): "naoh",
    (3, 0): "caoh2", (3, 1): "fe", (3, 2): "crude_salt", (3, 3): "nacl",
}
cut_grid_icons("16种基本物质.png", 4, 4, SUBSTANCE_GRID, 0.70)
# 纯净水复用水滴图标（同种物质视觉）
import shutil as _shutil
_shutil.copyfile(os.path.join(OUT_ART, "icons", "h2o.png"),
                 os.path.join(OUT_ART, "icons", "h2o_clean.png"))

ITEM_GRID = {
    (0, 0): "sulfur_torch", (0, 1): "neutral_spray", (0, 2): "activated_carbon",
    (1, 0): "extinguisher", (1, 1): "oxygen_tank", (1, 2): "soap_water",
    (2, 0): "stick", (2, 1): "cu", (2, 2): "nahco3",
}
cut_grid_icons("九种物品.png", 3, 3, ITEM_GRID, 0.72)


# ---------- 6. 音乐 ----------
shutil.copyfile(os.path.join(SRC, "游戏背景音乐.mp3"),
                os.path.join(OUT_AUDIO, "main_theme.mp3"))
print("music done")
print("ALL ASSETS PROCESSED")
