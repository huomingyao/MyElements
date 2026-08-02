# 背包界面（FR-U-05 / FR-G-02 AC4，IT-U05，TP-06 补）：Tab 开关，格子 + 图标 + 数量。
# 格子数 = 背包格数（不写死 8）；信号驱动刷新（inventory_changed，不轮询）。
# 图标缺失时按 id 散列稳定色占位（不留空白不崩溃，AC2；美术归 P4 替换）。
# 格子可拖拽（拖到合成台入格）；managed=true 时 Tab 只发 toggle_requested，由 ui_manager 裁决互斥。
extends Control

# managed 模式下 Tab 的开关请求（世界把它接到 ui_manager.toggle）。
signal toggle_requested()

# ==== 常量区 ====

const GRID_COLUMNS: int = 4
const SLOT_MIN_SIZE: Vector2 = Vector2(72, 52)
const PLACEHOLDER_SIZE: int = 32
const PLACEHOLDER_SATURATION: float = 0.55
const PLACEHOLDER_VALUE: float = 0.85
const HASH_NORMALIZER: float = 1073741824.0
const HUE_FULL_TURN: float = 1.0

const UI_TITLE: String = "inventory_title"
const ACTION_TOGGLE: String = "inventory"

# ==== 逻辑区 ====

# true 时 Tab 不自行开关，只发 toggle_requested（SPEC-03 §8：互斥由 ui_manager 裁决）。
var managed: bool = false

var _inventory: RefCounted = null
var _open: bool = false
var _slots: Array = []

@onready var _title: Label = %TitleLabel
@onready var _grid: GridContainer = %Grid


# 格子按钮：携带物品 id，支持拖拽（FR-U-05）。
class SlotButton:
	extends Button
	var item_id: String = ""

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if item_id.is_empty():
			return null
		var preview: Label = Label.new()
		preview.text = text
		set_drag_preview(preview)
		return {"id": item_id}


func _ready() -> void:
	visible = false
	_title.text = _ui(UI_TITLE)
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
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE):
		if managed:
			toggle_requested.emit()
		else:
			toggle()
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
		tex = _placeholder_texture()
		icon.modulate = _color_for_id(item_id)
	else:
		icon.modulate = Color.WHITE
	icon.texture = tex


func _placeholder_texture() -> Texture2D:
	var image: Image = Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


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
