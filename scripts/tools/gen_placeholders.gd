# 占位美术生成器（包 E2）。**占位资产，P4 正式美术交付后替换**——重新生成本目录：
#   ./run_tests.sh 同款 Godot：
#   godot --headless --path . -s scripts/tools/gen_placeholders.gd
#
# 规则（全部确定性，同输入必得同图）：
#   * 尺寸遵循 SPEC-08 §1：图标 16×16、导师立绘 240×320、导师小人 32×32。
#   * 颜色只取 SPEC-08 §2 的 32 色调色板；语义绑定色优先（氧气=#6fd6e8、CO=#6b6478 等）。
#   * 形状编码分类：单质=圆形、化合物=方形、氧化物=菱形、酸=倒三角、碱=正三角、盐=晶格；
#     道具按 type：equip=圆环、consume=试剂瓶、material=矿块。
#   * 导师占位配色与 scenes/mentor/mentor_art.gd 的运行时占位一致
#     （同一 _color_for：key 哈希取色相，s=0.45 / v=0.75；avatar key=导师id+idle/talk，
#     小人 key=导师id），保证换成文件后观感不跳变。
extends SceneTree

# ==== 规格常量（SPEC-08 §1）====
const ICON_SIZE: Vector2i = Vector2i(16, 16)
const AVATAR_SIZE: Vector2i = Vector2i(240, 320)
const PIXEL_SIZE: Vector2i = Vector2i(32, 32)

const DATA_SUBSTANCES: String = "res://data/substances.json"
const DATA_ITEMS: String = "res://data/items.json"
const DATA_MENTORS: String = "res://data/mentors.json"
const PLACEHOLDER_PATH: String = "res://assets/art/placeholder.png"

# ==== SPEC-08 §2 调色板（只用这些色）====
const GRAY_DARK: Color = Color("#3f3a4d")       # 未解锁剪影
const GRAY_MID: Color = Color("#6b6478")        # CO 幽灵
const GRAY_LINE: Color = Color("#a49eae")       # 面板描边
const GRAY_LIGHT: Color = Color("#f2f0f5")
const SKIN: Color = Color("#f2c9a0")
const SKIN_SHADE: Color = Color("#d99a6c")
const EARTH: Color = Color("#a89078")
const WATER_DEEP: Color = Color("#1c6b8f")
const WATER: Color = Color("#2f9fc4")
const OXYGEN: Color = Color("#6fd6e8")          # 语义：氧气
const ICE: Color = Color("#bfeef7")
const FIRE_DARK: Color = Color("#8f2418")
const LIFE: Color = Color("#e2542b")            # 语义：生命
const FIRE: Color = Color("#ffa32e")
const ENERGY: Color = Color("#ffd94a")          # 语义：能量
const ACID: Color = Color("#94c22a")
const ACID_LIGHT: Color = Color("#c8e84a")      # 语义：酸雾
const METAL_DARK: Color = Color("#4a3d99")
const METAL: Color = Color("#7f6fd6")
const METAL_LIGHT: Color = Color("#c0c8d8")
const WOOD: Color = Color("#8a6b4a")
const GRASS: Color = Color("#6fbf3f")

# 占位着色参数（与 mentor_art.gd 保持一致，勿改）。
const PLACEHOLDER_SATURATION: float = 0.45
const PLACEHOLDER_VALUE: float = 0.75
const HUE_CIRCLE: int = 360

# 物质 id → 图标主色（调色板内取值，语义见 SPEC-08 §4.2 第 3 批提示词）。
const SUBSTANCE_COLORS: Dictionary = {
	"o2": OXYGEN, "h2": ICE, "c": Color("#221f2e"), "s": ENERGY,
	"co": GRAY_MID, "co2": GRAY_LINE, "h2o": WATER, "h2o_clean": OXYGEN,
	"caco3": GRAY_LIGHT, "fe2o3": FIRE_DARK, "cuso4": WATER,
	"hcl": ACID_LIGHT, "naoh": GRAY_LIGHT, "caoh2": GRAY_LIGHT,
	"fe": METAL_LIGHT, "crude_salt": EARTH, "nacl": GRAY_LIGHT,
}
# 道具 id → 图标主色。
const ITEM_COLORS: Dictionary = {
	"sulfur_torch": FIRE, "neutral_spray": ACID, "activated_carbon": Color("#221f2e"),
	"carbon_mask": GRAY_MID, "extinguisher": LIFE, "oxygen_tank": OXYGEN,
	"soap_water": ICE, "stick": WOOD, "cu": FIRE, "nahco3": GRAY_LIGHT,
}

# 分类 → 形状（化合物为默认方形）。
const SHAPE_CIRCLE: String = "circle"
const SHAPE_SQUARE: String = "square"
const SHAPE_DIAMOND: String = "diamond"
const SHAPE_TRI_DOWN: String = "tri_down"
const SHAPE_TRI_UP: String = "tri_up"
const SHAPE_CRYSTAL: String = "crystal"
const CATEGORY_SHAPES: Dictionary = {
	"单质": SHAPE_CIRCLE, "化合物": SHAPE_SQUARE, "氧化物": SHAPE_DIAMOND,
	"酸": SHAPE_TRI_DOWN, "碱": SHAPE_TRI_UP, "盐": SHAPE_CRYSTAL,
}
# 道具 type → 形状。
const SHAPE_RING: String = "ring"
const SHAPE_BOTTLE: String = "bottle"
const SHAPE_CHUNK: String = "chunk"
const ITEM_TYPE_SHAPES: Dictionary = {
	"equip": SHAPE_RING, "consume": SHAPE_BOTTLE, "material": SHAPE_CHUNK,
}

const QUESTION_MARK: Array[String] = [
	" ### ",
	"#   #",
	"    #",
	"   # ",
	"  #  ",
	"     ",
	"  #  ",
]


# ==== 入口 ====
func _initialize() -> void:
	var made: int = 0
	made += _gen_substance_icons()
	made += _gen_item_icons()
	made += _gen_mentor_art()
	made += _gen_placeholder()
	print("GEN OK：共写出 %d 个占位 PNG（占位资产，P4 正式美术交付后替换）" % made)
	quit(0)


# ==== 数据读取 ====
static func _read_rows(path: String) -> Array:
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		printerr("GEN ERROR：%s 解析失败" % path)
		return []
	return json.data as Array


# ==== 图标 ====
func _gen_substance_icons() -> int:
	var count: int = 0
	for row_value in _read_rows(DATA_SUBSTANCES):
		var row: Dictionary = row_value as Dictionary
		var id: String = str(row.get("id", ""))
		var color: Color = SUBSTANCE_COLORS.get(id, GRAY_LINE) as Color
		var shape: String = str(CATEGORY_SHAPES.get(str(row.get("category", "")), SHAPE_SQUARE))
		var image: Image = _new_transparent(ICON_SIZE)
		_draw_shape(image, shape, color)
		_save(image, str(row.get("icon", "")))
		count += 1
	return count


func _gen_item_icons() -> int:
	var count: int = 0
	for row_value in _read_rows(DATA_ITEMS):
		var row: Dictionary = row_value as Dictionary
		var id: String = str(row.get("id", ""))
		var color: Color = ITEM_COLORS.get(id, GRAY_LINE) as Color
		var shape: String = str(ITEM_TYPE_SHAPES.get(str(row.get("type", "")), SHAPE_CHUNK))
		var image: Image = _new_transparent(ICON_SIZE)
		_draw_shape(image, shape, color)
		_save(image, str(row.get("icon", "")))
		count += 1
	return count


# 在 16×16 画布上按形状编码绘制：描边色 = 主色压暗，先描边后填充。
static func _draw_shape(image: Image, shape: String, base: Color) -> void:
	var edge: Color = base.darkened(0.5)
	match shape:
		SHAPE_CIRCLE:
			_fill_circle(image, 7.5, 7.5, 6.5, edge)
			_fill_circle(image, 7.5, 7.5, 5.0, base)
			image.set_pixel(5, 5, base.lightened(0.4))
		SHAPE_SQUARE:
			_fill_rect(image, 1, 1, 14, 14, edge)
			_fill_rect(image, 3, 3, 12, 12, base)
			image.set_pixel(4, 4, base.lightened(0.4))
		SHAPE_DIAMOND:
			_fill_diamond(image, 6.5, edge)
			_fill_diamond(image, 5.0, base)
			image.set_pixel(6, 5, base.lightened(0.4))
		SHAPE_TRI_DOWN:
			_fill_triangle(image, true, 2, edge)
			_fill_triangle(image, true, 4, base)
		SHAPE_TRI_UP:
			_fill_triangle(image, false, 2, edge)
			_fill_triangle(image, false, 4, base)
		SHAPE_CRYSTAL:
			_fill_rect(image, 1, 1, 14, 14, edge)
			_fill_rect(image, 2, 2, 7, 7, base)
			_fill_rect(image, 9, 2, 14, 7, base.lightened(0.15))
			_fill_rect(image, 2, 9, 7, 14, base.lightened(0.15))
			_fill_rect(image, 9, 9, 14, 14, base)
		SHAPE_RING:
			_fill_circle(image, 7.5, 7.5, 6.5, edge)
			_fill_circle(image, 7.5, 7.5, 4.5, base)
			_fill_circle(image, 7.5, 7.5, 2.0, Color.TRANSPARENT)
		SHAPE_BOTTLE:
			_fill_rect(image, 6, 1, 9, 3, edge)     # 瓶口
			_fill_rect(image, 4, 4, 11, 14, edge)   # 瓶身描边
			_fill_rect(image, 5, 5, 10, 13, base)
			_fill_rect(image, 5, 9, 10, 13, base.darkened(0.2))  # 液面
		SHAPE_CHUNK:
			_fill_rect(image, 2, 4, 13, 13, edge)
			_fill_rect(image, 3, 5, 12, 12, base)
			image.set_pixel(5, 7, base.lightened(0.4))
			image.set_pixel(9, 9, base.darkened(0.25))


# ==== 导师美术 ====
func _gen_mentor_art() -> int:
	var count: int = 0
	for row_value in _read_rows(DATA_MENTORS):
		var row: Dictionary = row_value as Dictionary
		var id: String = str(row.get("id", ""))
		_save(_avatar_image(id, false), str(row.get("avatar_idle", "")))
		_save(_avatar_image(id, true), str(row.get("avatar_talk", "")))
		_save(_pixel_image(id), str(row.get("sprite", "")))
		count += 3
	return count


# 立绘 240×320：底色与运行时占位同色（key=导师id+idle/talk），
# 叠加童书感半身剪影（皮肤色头 + 压暗底色身体），talk 帧张嘴。
static func _avatar_image(mentor_id: String, talking: bool) -> Image:
	var mode: String = "talk" if talking else "idle"
	var bg: Color = _color_for(mentor_id + mode)
	var body: Color = bg.darkened(0.35)
	var image: Image = Image.create(AVATAR_SIZE.x, AVATAR_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(bg)
	var cx: int = AVATAR_SIZE.x / 2
	# 身体（梯形近似：矩形 + 肩部圆角省略，占位够用）。
	_fill_rect(image, cx - 75, 180, cx + 75, AVATAR_SIZE.y - 1, body)
	_fill_rect(image, cx - 60, 168, cx + 60, 190, body)
	# 头（圆角矩形近似椭圆）。
	_fill_ellipse(image, float(cx), 108.0, 56.0, 62.0, SKIN_SHADE)
	_fill_ellipse(image, float(cx), 106.0, 50.0, 56.0, SKIN)
	# 眼睛。
	_fill_rect(image, cx - 24, 96, cx - 14, 106, GRAY_DARK)
	_fill_rect(image, cx + 14, 96, cx + 24, 106, GRAY_DARK)
	# 嘴：idle 一条线；talk 张开。
	if talking:
		_fill_rect(image, cx - 16, 134, cx + 16, 152, GRAY_DARK)
		_fill_rect(image, cx - 12, 144, cx + 12, 150, LIFE)
	else:
		_fill_rect(image, cx - 14, 140, cx + 14, 144, GRAY_DARK)
	return image


# 房间小人 32×32：透明底，主色与运行时占位同色（key=导师id）。
static func _pixel_image(mentor_id: String) -> Image:
	var main: Color = _color_for(mentor_id)
	var image: Image = _new_transparent(PIXEL_SIZE)
	# 头。
	_fill_rect(image, 11, 3, 20, 12, SKIN_SHADE)
	_fill_rect(image, 12, 4, 19, 11, SKIN)
	image.set_pixel(13, 7, GRAY_DARK)
	image.set_pixel(17, 7, GRAY_DARK)
	# 身体。
	_fill_rect(image, 10, 13, 21, 24, main.darkened(0.3))
	_fill_rect(image, 11, 14, 20, 23, main)
	# 腿。
	_fill_rect(image, 12, 25, 14, 30, GRAY_DARK)
	_fill_rect(image, 17, 25, 19, 30, GRAY_DARK)
	return image


# ==== 通用占位图：灰底问号 ====
func _gen_placeholder() -> int:
	var image: Image = Image.create(ICON_SIZE.x, ICON_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(GRAY_DARK)
	for y in range(QUESTION_MARK.size()):
		var line: String = QUESTION_MARK[y]
		for x in range(line.length()):
			if line[x] == "#":
				image.set_pixel(5 + x, 4 + y, GRAY_LINE)
	_save(image, PLACEHOLDER_PATH)
	return 1


# ==== 绘制小工具（全部轴对齐像素操作，无抗锯齿）====
static func _new_transparent(size: Vector2i) -> Image:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


static func _fill_rect(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for y in range(maxi(y0, 0), mini(y1, image.get_height() - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, image.get_width() - 1) + 1):
			image.set_pixel(x, y, color)


static func _fill_circle(image: Image, cx: float, cy: float, radius: float, color: Color) -> void:
	_fill_ellipse(image, cx, cy, radius, radius, color)


static func _fill_ellipse(
	image: Image, cx: float, cy: float, rx: float, ry: float, color: Color
) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var dx: float = (float(x) - cx) / rx
			var dy: float = (float(y) - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				image.set_pixel(x, y, color)


static func _fill_diamond(image: Image, radius: float, color: Color) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if absf(float(x) - 7.5) + absf(float(y) - 7.5) <= radius:
				image.set_pixel(x, y, color)


# down=true：尖朝下（酸）；false：尖朝上（碱）。inset 为水平内缩，垂直固定 2..13 共 12 行。
static func _fill_triangle(image: Image, down: bool, inset: int, color: Color) -> void:
	var left: int = inset
	var right: int = image.get_width() - 1 - inset
	var top: int = 2
	var bottom: int = image.get_height() - 3
	var span: float = float(bottom - top)
	for y in range(top, bottom + 1):
		var t: float = float(y - top) / span
		var frac: float = (1.0 - t) if down else t
		var half: float = (float(right - left) * 0.5) * frac
		for x in range(left, right + 1):
			if absf(float(x) - 7.5) <= half:
				image.set_pixel(x, y, color)


# ==== 与 mentor_art.gd 完全一致的确定性占位配色 ====
static func _color_for(key: String) -> Color:
	var hue: float = float(absi(key.hash()) % HUE_CIRCLE) / float(HUE_CIRCLE)
	return Color.from_hsv(hue, PLACEHOLDER_SATURATION, PLACEHOLDER_VALUE)


static func _save(image: Image, res_path: String) -> void:
	if res_path.is_empty():
		printerr("GEN ERROR：空路径，跳过")
		return
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err: Error = image.save_png(abs_path)
	if err != OK:
		printerr("GEN ERROR：写出失败 %s（err=%d）" % [res_path, err])
	else:
		print("GEN: %s" % res_path)
