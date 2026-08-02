# CodexCell（FR-U-04）：图鉴网格中的一格物质卡。
# 已收集：彩色图标 + 真名 + 分类标签；未收集：剪影 + codex_locked 占位文案，不泄露名称/化学式/分类。
# 图标美术未交付时按 substances.json 的 icon 字段加载失败即回退到纯色占位纹理（不留空白不崩溃）。
extends PanelContainer

# ==== 常量区 ====
# 剪影着色：未收集格统一压暗（NFR-04：调参数值集中在常量区）。
const SILHOUETTE_TINT: Color = Color(0.12, 0.12, 0.14)
const PLACEHOLDER_SIZE: int = 32
const PLACEHOLDER_SATURATION: float = 0.55
const PLACEHOLDER_VALUE: float = 0.85
const HUE_FULL_TURN: float = 1.0
const HASH_NORMALIZER: float = 1073741824.0
# tooltip 展示的数据字段（包D：codex_line + obtain 来源指引，全部取自数据表，NFR-04）。
const TOOLTIP_FIELDS: Array[String] = ["codex_line", "obtain"]

# ==== 状态区 ====
var _substance_id: String = ""
var _unlocked: bool = false
var _tint: Color = SILHOUETTE_TINT

@onready var _icon: TextureRect = %IconRect
@onready var _name_label: Label = %NameLabel
@onready var _category_label: Label = %CategoryLabel


# ==== 逻辑区 ====
# 绑定一条物质记录与解锁状态。locked_text 由调用方取自 ui_strings.codex_locked（NFR-04）。
func bind(substance: Dictionary, unlocked: bool, locked_text: String) -> void:
	_substance_id = str(substance.get("id", ""))
	_unlocked = unlocked
	if _unlocked:
		_name_label.text = str(substance.get("name", ""))
		_category_label.text = str(substance.get("category", ""))
	else:
		_name_label.text = locked_text
		_category_label.text = ""
	_apply_icon(str(substance.get("icon", "")))
	_apply_tooltip(substance, locked_text)


func substance_id() -> String:
	return _substance_id


func is_unlocked() -> bool:
	return _unlocked


func is_silhouette() -> bool:
	return not _unlocked


func name_text() -> String:
	return _name_label.text


func category_text() -> String:
	return _category_label.text


func icon_tint() -> Color:
	return _tint


func icon_texture() -> Texture2D:
	return _icon.texture


# 详情 tooltip（包D）：已收集格展示图鉴一句话 + 获得途径（obtain 字段）；
# 未收集格只显示占位文案，与剪影同口径不泄露任何数据表内容。
# 文案逐字来自数据表字段，代码里不出现玩家可见文字（NFR-04）。
func _apply_tooltip(substance: Dictionary, locked_text: String) -> void:
	if not _unlocked:
		tooltip_text = locked_text
		return
	var lines: Array[String] = []
	for field: String in TOOLTIP_FIELDS:
		var line: String = str(substance.get(field, "")).strip_edges()
		if not line.is_empty():
			lines.append(line)
	tooltip_text = "\n".join(lines)


# 图标加载：路径存在用真图标（解锁显示原色，锁定压暗成剪影）；
# 路径缺失（美术未交付）生成白色占位块，解锁格按 id 散列上色、锁定格仍压暗。
func _apply_icon(icon_path: String) -> void:
	var tex: Texture2D = null
	var has_real_icon: bool = false
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
		has_real_icon = tex != null
	if tex == null:
		tex = _placeholder_texture()
	if _unlocked:
		_tint = Color.WHITE if has_real_icon else _color_for_id(_substance_id)
	else:
		_tint = SILHOUETTE_TINT
	_icon.texture = tex
	_icon.modulate = _tint


# 白色占位块：着色全部交给 modulate，同一张纹理服务所有格。
func _placeholder_texture() -> Texture2D:
	var image: Image = Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


# 由物质 id 决定的稳定占位色（同一物质每次打开颜色一致）。
func _color_for_id(substance_id: String) -> Color:
	var hue: float = fmod(absf(float(substance_id.hash())) / HASH_NORMALIZER, HUE_FULL_TURN)
	return Color.from_hsv(hue, PLACEHOLDER_SATURATION, PLACEHOLDER_VALUE)
