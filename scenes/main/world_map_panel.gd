# 世界地图页（FR-U-03，SPEC-03 §7）：13 区域热区全部来自 worldmap.json。
# 已解锁 5 个彩色可点（显示简介 brief）；未解锁 8 个灰色剪影 + 名称 +「赛后解锁」角标，
# 点击抖动一次并显示预告语 teaser，不可进入（MVP 无区域跳转）。
# 面板显隐只跟 WorldMap autoload 的 map_opened/map_closed 信号；M 键在这里翻译成 open()/close()。
extends Control

# ==== 常量区 ====

const HOTSPOT_PREFIX: String = "Zone_"
const UI_BADGE_KEY: String = "map_locked_badge"

# 占位配色（美术未交付区域沿用，SPEC-08 调色板出来后整体替换）。
const COLOR_LOCKED: Color = Color(0.35, 0.35, 0.35)
const UNLOCKED_COLORS: Array[Color] = [
	Color(0.45, 0.75, 0.45),
	Color(0.85, 0.70, 0.35),
	Color(0.55, 0.65, 0.90),
	Color(0.80, 0.50, 0.40),
	Color(0.60, 0.50, 0.85),
]
# 挂场景图的热区用近白染色：不破坏图面观感，同时保持非灰（IT-U03 彩色断言）。
const ART_TINT: Color = Color(1.0, 0.99, 0.98)

# 抖动参数（一次性 Tween，不占 _process）。
const SHAKE_OFFSET: float = 4.0
const SHAKE_STEP: float = 0.06

# ==== 逻辑区 ====

# 点击未解锁区域：抖动一次（IT-U03 据此断言）。
signal locked_zone_shaken(zone_id: String)

var _hotspots: Dictionary = {}
var _hotspot_order: Array[String] = []
var _shake_tweens: Dictionary = {}

@onready var _map_area: Control = %MapArea
@onready var _info_label: Label = %InfoLabel


func _ready() -> void:
	visible = false
	_build_hotspots()
	var wm: Node = _world_map()
	if wm != null:
		wm.map_opened.connect(_on_map_opened)
		wm.map_closed.connect(_on_map_closed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("worldmap"):
		return
	var wm: Node = _world_map()
	if wm == null:
		return
	if wm.is_open():
		wm.close()
	else:
		wm.open()
	get_viewport().set_input_as_handled()


func _on_map_opened() -> void:
	visible = true


func _on_map_closed() -> void:
	visible = false


# 热区全部按 worldmap.json 构建：id/顺序/矩形/解锁状态/名称/角标都照表（AC2、AC4）。
func _build_hotspots() -> void:
	var wm: Node = _world_map()
	if wm == null:
		push_warning("[worldmap-panel] WorldMap 不可用，热区为空")
		return
	var index: int = 0
	for row: Dictionary in wm.all_zones():
		var zone_id: String = str(row.get("id", ""))
		if zone_id.is_empty():
			continue
		var unlocked: bool = wm.is_unlocked(zone_id)
		var spot := Button.new()
		spot.name = HOTSPOT_PREFIX + zone_id
		var hs: Dictionary = row.get("hotspot", {})
		spot.position = Vector2(float(hs.get("x", 0.0)), float(hs.get("y", 0.0)))
		spot.size = Vector2(float(hs.get("w", 0.0)), float(hs.get("h", 0.0)))
		spot.focus_mode = Control.FOCUS_NONE
		# 场景图（数据表 map_image 字段，铁律 4）：已解锁且有素材才挂，置于名称之下。
		var image_path: String = str(row.get("map_image", ""))
		var has_art: bool = unlocked and not image_path.is_empty() and ResourceLoader.exists(image_path)
		if has_art:
			spot.add_child(_make_zone_art(image_path))
		# 名称放在子 Label 上：Button.text 会撑大最小尺寸，热区矩形必须严格照表（AC2）。
		spot.add_child(_make_name_label(str(row.get("name", ""))))
		if unlocked:
			spot.modulate = ART_TINT if has_art else UNLOCKED_COLORS[index % UNLOCKED_COLORS.size()]
		else:
			spot.modulate = COLOR_LOCKED
			spot.add_child(_make_badge())
		spot.pressed.connect(_on_zone_pressed.bind(zone_id))
		_map_area.add_child(spot)
		_hotspots[zone_id] = spot
		_hotspot_order.append(zone_id)
		index += 1


func _make_name_label(zone_name: String) -> Label:
	var label := Label.new()
	label.name = "NameLabel"
	label.text = zone_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	return label


# 热区场景图：铺满按钮、保持比例裁边，纯展示不抢鼠标（点击仍落在 Button 上）。
func _make_zone_art(image_path: String) -> TextureRect:
	var art := TextureRect.new()
	art.name = "ZoneArt"
	art.texture = load(image_path) as Texture2D
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return art


func _make_badge() -> Label:
	var badge := Label.new()
	badge.name = "Badge"
	badge.text = _ui(UI_BADGE_KEY)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	return badge


# AC3：已解锁显示简介；未解锁抖动一次 + 预告语，不可进入。
func _on_zone_pressed(zone_id: String) -> void:
	var wm: Node = _world_map()
	if wm == null:
		return
	var row: Dictionary = wm.get_zone(zone_id)
	if wm.is_unlocked(zone_id):
		_info_label.text = str(row.get("brief", ""))
		return
	_info_label.text = str(row.get("teaser", ""))
	_shake(zone_id)
	locked_zone_shaken.emit(zone_id)


func _shake(zone_id: String) -> void:
	var spot: Button = _hotspots.get(zone_id)
	if spot == null:
		return
	var old: Tween = _shake_tweens.get(zone_id)
	if old != null and old.is_valid():
		old.kill()
	var origin_x: float = spot.position.x
	var tween: Tween = create_tween()
	tween.tween_property(spot, "position:x", origin_x + SHAKE_OFFSET, SHAKE_STEP)
	tween.tween_property(spot, "position:x", origin_x - SHAKE_OFFSET, SHAKE_STEP)
	tween.tween_property(spot, "position:x", origin_x + SHAKE_OFFSET * 0.5, SHAKE_STEP)
	tween.tween_property(spot, "position:x", origin_x, SHAKE_STEP)
	_shake_tweens[zone_id] = tween


# ==== 测试与调试查询口 ====

func hotspot_ids() -> Array[String]:
	return _hotspot_order.duplicate()


func hotspot(zone_id: String) -> Control:
	return _hotspots.get(zone_id)


func info_text() -> String:
	return _info_label.text


func _world_map() -> Node:
	return get_node_or_null(^"/root/WorldMap")


func _ui(key: String) -> String:
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm == null:
		return key
	return gm.get_ui_string(key)
