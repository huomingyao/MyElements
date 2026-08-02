# 背包界面（FR-U-05 / FR-G-02 AC4，IT-U05，TP-06 补）：Tab 开关，格子 + 图标 + 数量。
# 格子数 = 背包格数（不写死 8）；信号驱动刷新（inventory_changed，不轮询）。
# 图标缺失时按 id 散列稳定色占位（不留空白不崩溃，AC2；美术归 P4 替换）。
# 格子可拖拽（拖到合成台入格）；managed=true 时 Tab 只发 toggle_requested，由 ui_manager 裁决互斥。
extends Control

# managed 模式下 Tab 的开关请求（世界把它接到 ui_manager.toggle）。
signal toggle_requested()
# 背包打开时按 X（craft 动作）请求切到合成界面（FR-G-05 AC4；世界接到 ui_manager.open("craft")）。
signal craft_requested()

# ==== 常量区 ====

const GRID_COLUMNS: int = 4
const SLOT_MIN_SIZE: Vector2 = Vector2(64, 48)
const PLACEHOLDER_SIZE: int = 32
const PLACEHOLDER_SATURATION: float = 0.55
const PLACEHOLDER_VALUE: float = 0.85
const HASH_NORMALIZER: float = 1073741824.0
const HUE_FULL_TURN: float = 1.0

const UI_TITLE: String = "inventory_title"
const UI_CRAFT_HINT: String = "inventory_craft_hint"
const ACTION_TOGGLE: String = "inventory"
const ACTION_CRAFT: String = "craft"

# ==== 逻辑区 ====

# 占位纹理静态共享缓存（包E）：按颜色键复用，进程内所有实例共享，
# 不再每次 _refresh 每格 new Image/ImageTexture。
static var _placeholder_cache: Dictionary = {}

# true 时 Tab 不自行开关，只发 toggle_requested（SPEC-03 §8：互斥由 ui_manager 裁决）。
var managed: bool = false

var _inventory: RefCounted = null
var _open: bool = false
var _slots: Array = []

@onready var _title: Label = %TitleLabel
@onready var _grid: GridContainer = %Grid
@onready var _craft_hint: Label = %HintLabel


# 格子按钮：携带物品 id，支持拖拽（FR-U-05）。
class SlotButton:
	extends Button
	var item_id: String = ""
	# 预览构建委托给面板（内层类拿不到外层实例方法，由 _rebuild_slots 注入）。
	var preview_factory: Callable = Callable()

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if item_id.is_empty():
			return null
		var count_label: Label = get_node_or_null(^"Count") as Label
		var count_text: String = count_label.text if count_label != null else ""
		var preview: Control = null
		if preview_factory.is_valid():
			preview = preview_factory.call(item_id, count_text) as Control
		if preview == null:
			var fallback := Label.new()
			fallback.text = text
			preview = fallback
		set_drag_preview(preview)
		return {"id": item_id}


func _ready() -> void:
	visible = false
	_title.text = _ui(UI_TITLE)
	_craft_hint.text = _ui(UI_CRAFT_HINT)
	_rebuild_slots()
	_refresh()


# 世界接线入口：绑定玩家背包（TP-06 纯逻辑背包）；改信号即刷新，不轮询。
func bind(inventory: RefCounted) -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_refresh):
		_inventory.inventory_changed.disconnect(_refresh)
	_inventory = inventory
	if _inventory != null:
		_inventory.inventory_changed.connect(_refresh)
	_rebuild_slots()
	_refresh()


func open() -> void:
	_open = true
	visible = true
	_refresh()


func close() -> void:
	_open = false
	visible = false


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


# Tab 开关（FR-G-02 AC4）；managed 时转发给 ui_manager。
# X（craft 动作）：背包打开时请求切到合成界面（FR-G-05 AC4）。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE):
		if managed:
			toggle_requested.emit()
		else:
			toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_CRAFT):
		if _open:
			craft_requested.emit()
			get_viewport().set_input_as_handled()


# ==== 测试观测口 ====

func slot_count() -> int:
	return _slots.size()


# 格子节点访问口（测试与拖拽判定用；动态节点的 %唯一名 对场景外调用方不可靠）。
func slot_button(index: int) -> Node:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index]


func slot_item_id(index: int) -> String:
	if index < 0 or index >= _slots.size():
		return ""
	return (_slots[index] as SlotButton).item_id


func slot_count_text(index: int) -> String:
	if index < 0 or index >= _slots.size():
		return ""
	return str((_slots[index] as SlotButton).get_node(^"Count").text)


func slot_icon_texture(index: int) -> Texture2D:
	if index < 0 or index >= _slots.size():
		return null
	return ((_slots[index] as SlotButton).get_node(^"Icon") as TextureRect).texture


# ==== 内部 ====

# 格子数量跟随背包配置（不写死 8）。
func _rebuild_slots() -> void:
	for slot: Node in _slots:
		slot.queue_free()
	_slots.clear()
	var count: int = 8
	if _inventory != null:
		count = int(_inventory.slot_count())
	for i: int in range(count):
		var slot: SlotButton = SlotButton.new()
		slot.name = "Slot%d" % i
		slot.unique_name_in_owner = true
		slot.custom_minimum_size = SLOT_MIN_SIZE
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.flat = true
		slot.preview_factory = make_drag_preview
		var icon: TextureRect = TextureRect.new()
		icon.name = "Icon"
		icon.set_anchors_preset(Control.PRESET_CENTER)
		icon.custom_minimum_size = Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var count_label: Label = Label.new()
		count_label.name = "Count"
		count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(count_label)
		_grid.add_child(slot)
		# 动态节点默认无 owner，%唯一名查找会落空；显式指定后才支持 %SlotN。
		slot.owner = self
		_slots.append(slot)
	_grid.columns = GRID_COLUMNS


func _refresh() -> void:
	var contents: Array = []
	if _inventory != null:
		contents = _inventory.slots()
	for i: int in range(_slots.size()):
		var slot: SlotButton = _slots[i]
		if i < contents.size():
			var entry: Dictionary = contents[i]
			var item_id: String = str(entry.get("id", ""))
			slot.item_id = item_id
			slot.text = _display_name(item_id)
			(slot.get_node(^"Count") as Label).text = str(int(entry.get("count", 0)))
			_apply_icon(slot, item_id)
		else:
			slot.item_id = ""
			slot.text = ""
			(slot.get_node(^"Count") as Label).text = ""
			_apply_icon(slot, "")


# 图标：路径存在用真图标；缺失用 id 散列稳定色占位（同 codex_cell 的口径）。
# 占位纹理由静态缓存按颜色键复用（不再每格新建，包E）。
func _apply_icon(slot: SlotButton, item_id: String) -> void:
	var icon: TextureRect = slot.get_node(^"Icon") as TextureRect
	if item_id.is_empty():
		icon.texture = null
		return
	var icon_path: String = _icon_path_of(item_id)
	var tex: Texture2D = null
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	if tex == null:
		tex = placeholder_texture_for(_color_for_id(item_id))
	icon.texture = tex


# 占位纹理：按颜色键静态缓存（同色复用同一实例，散列色种类有限不会无限增长）。
static func placeholder_texture_for(color: Color) -> Texture2D:
	var cached: Variant = _placeholder_cache.get(color)
	if cached is Texture2D:
		return cached
	var image: Image = Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var tex: Texture2D = ImageTexture.create_from_image(image)
	_placeholder_cache[color] = tex
	return tex


# 拖拽预览（包E + FR-G-05 AC5）：真实图标优先（资源本身跟随鼠标），缺失回退占位纹理 + 数量角标。
func make_drag_preview(item_id: String, count_text: String) -> Control:
	var root: Control = Control.new()
	root.custom_minimum_size = Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
	root.size = Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path: String = _icon_path_of(item_id)
	var tex: Texture2D = null
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	if tex == null:
		tex = placeholder_texture_for(_color_for_id(item_id))
	icon.texture = tex
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)
	if not count_text.is_empty():
		var badge: Label = Label.new()
		badge.name = "Count"
		badge.text = count_text
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(badge)
	return root


func _color_for_id(item_id: String) -> Color:
	var hue: float = fmod(absf(float(item_id.hash())) / HASH_NORMALIZER, HUE_FULL_TURN)
	return Color.from_hsv(hue, PLACEHOLDER_SATURATION, PLACEHOLDER_VALUE)


# 名称/图标解析：先物质表（RecipeDB），再道具表（items.json）。
func _display_name(item_id: String) -> String:
	var record: Dictionary = _record_of(item_id)
	return str(record.get("name", item_id))


func _icon_path_of(item_id: String) -> String:
	var record: Dictionary = _record_of(item_id)
	return str(record.get("icon", ""))


func _record_of(item_id: String) -> Dictionary:
	var db: Node = get_node_or_null(^"/root/RecipeDB")
	if db != null:
		var substance: Dictionary = db.get_substance(item_id)
		if not substance.is_empty():
			return substance
	var items: RefCounted = (load("res://scripts/gameplay/item_effects.gd") as GDScript).new()
	return items.get_item(item_id)


func _ui(key: String) -> String:
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm == null:
		return key
	return gm.get_ui_string(key)
