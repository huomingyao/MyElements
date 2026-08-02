# 合成界面（FR-G-05，IT-G05，TP-07 补）：3 材料格 + 3 器材 + 反应/点燃/验纯。
# 材料从背包入格（取消全部回背包，不丢失）；成功产物入包 + card_ready 弹卡片；
# 失败按 reason 取数据表文案走 KnowledgeTip.show_custom，材料不消耗（SPEC-02 §4.4）。
# 氢气路径（FR-G-08/09）：H₂+O₂ 便携格点燃走 HydrogenEvent（未验纯爆炸 / 验纯后成功）。
# 文案全走 get_ui_string + 数据表字段（NFR-04）。
extends Control

# 合成成功：卡片字典由世界接到 CardPopup。
signal card_ready(card: Dictionary)
# managed 模式下取消/关闭的请求（世界把它接到 ui_manager.close_active）。
signal close_requested()

# ==== 常量区 ====

const SLOT_MAX: int = 3
const TOOL_OPTIONS: Array[String] = ["portable", "alcohol_lamp", "bench"]
const DEFAULT_TOOL: String = "portable"

const CONDITION_NONE: String = "none"
const CONDITION_IGNITE: String = "ignite"
const CONDITION_HEAT: String = "heat"
const CONDITION_LOW_OXYGEN: String = "low_oxygen"

const ZONE_MINE: String = "mine"

const HYDROGEN_RECIPE_ID: String = "r_hydrogen_burn"
const HYDROGEN_INPUT_ID: String = "h2"

const REASON_NEEDS_PURITY: String = "needs_purity_check"

const FAIL_STYLE: String = "banner"
const FAIL_DURATION: float = 4.0

const UI_TITLE: String = "craft_title"
const UI_REACT: String = "craft_react"
const UI_IGNITE: String = "craft_ignite"
const UI_PURITY: String = "craft_purity"
const UI_CANCEL: String = "craft_cancel"
const UI_SLOT_EMPTY: String = "craft_slot_empty"
const UI_TOOL_KEYS: Dictionary = {
	"portable": "craft_tool_portable",
	"alcohol_lamp": "craft_tool_lamp",
	"bench": "craft_tool_bench",
}

# ==== 逻辑区 ====

var _inventory: RefCounted = null
var _hydrogen: RefCounted = null
var _slots: Array[String] = []
var _tool: String = DEFAULT_TOOL
var _open: bool = false

# true 时关闭动作额外发 close_requested，由 ui_manager 同步互斥状态（SPEC-03 §8）。
var managed: bool = false

@onready var _title: Label = %TitleLabel
@onready var _slot_buttons: Array = [%Slot0, %Slot1, %Slot2]
@onready var _tool_buttons: Dictionary = {
	"portable": %ToolPortable,
	"alcohol_lamp": %ToolLamp,
	"bench": %ToolBench,
}
@onready var _react_button: Button = %ReactButton
@onready var _ignite_button: Button = %IgniteButton
@onready var _purity_button: Button = %PurityButton
@onready var _cancel_button: Button = %CancelButton


func _ready() -> void:
	visible = false
	_title.text = _ui(UI_TITLE)
	_react_button.text = _ui(UI_REACT)
	_ignite_button.text = _ui(UI_IGNITE)
	_purity_button.text = _ui(UI_PURITY)
	_cancel_button.text = _ui(UI_CANCEL)
	for tool: String in TOOL_OPTIONS:
		var button: Button = _tool_buttons[tool]
		button.text = _ui(str(UI_TOOL_KEYS[tool]))
		button.pressed.connect(select_tool.bind(tool))
	for i: int in range(_slot_buttons.size()):
		(_slot_buttons[i] as Button).pressed.connect(remove_material_at.bind(i))
	_react_button.pressed.connect(react)
	_ignite_button.pressed.connect(ignite)
	_purity_button.pressed.connect(purity_check)
	_cancel_button.pressed.connect(close)
	_refresh()


# 世界接线入口：注入玩家背包（TP-06 纯逻辑背包，鸭子类型）。
func bind(inventory: RefCounted) -> void:
	_inventory = inventory


# 世界接线入口：注入氢气事件（FR-G-08/09）。
func set_hydrogen_event(event: RefCounted) -> void:
	_hydrogen = event


func open() -> void:
	_open = true
	visible = true
	_refresh()


# 取消/关闭：格内材料全部退回背包（AC1：不丢失）。
func close() -> void:
	var was_open: bool = _open
	_return_all_materials()
	_open = false
	visible = false
	if managed and was_open:
		close_requested.emit()


func is_open() -> bool:
	return _open


# 材料入格：最多 3 格；背包里必须有（入格即从背包扣出）。
func add_material(item_id: String) -> bool:
	if _slots.size() >= SLOT_MAX:
		return false
	if _inventory == null or not bool(_inventory.has_item(item_id, 1)):
		return false
	if not bool(_inventory.remove_item(item_id, 1)):
		return false
	_slots.append(item_id)
	_refresh()
	return true


# 点格子取回材料（回背包）。
func remove_material_at(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	var item_id: String = _slots[index]
	_slots.remove_at(index)
	if _inventory != null:
		_inventory.add_item(item_id, 1)
	_refresh()


func slot_ids() -> Array:
	return _slots.duplicate()


func tool_options() -> Array[String]:
	return TOOL_OPTIONS.duplicate()


func select_tool(tool: String) -> void:
	if not TOOL_OPTIONS.has(tool):
		push_warning("[craft] 未知器材：%s（忽略）" % tool)
		return
	_tool = tool
	_refresh()


func selected_tool() -> String:
	return _tool


# 拖拽入料（FR-U-05：背包拖到合成台）：落在面板任意处即入格（等价点空格）。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not _open:
		return false
	if not (data is Dictionary):
		return false
	var item_id: String = str((data as Dictionary).get("id", ""))
	if item_id.is_empty() or _slots.size() >= SLOT_MAX:
		return false
	return _inventory != null and bool(_inventory.has_item(item_id, 1))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	add_material(str((data as Dictionary).get("id", "")))


# 「反应」：酒精灯等价于加热（heat，如 R12 碳活化），其余器材为 none（SPEC-02 §4.4 口径）。
func react() -> void:
	var condition: String = CONDITION_HEAT if _tool == "alcohol_lamp" else CONDITION_NONE
	_settle(_db().try_craft(_slots, _tool, condition))


# 「点燃」：H₂+O₂ 且器材与 R4 一致时走氢气事件（未验纯爆炸 / 验纯后成功）；
# 其余材料组合按条件直接查配方——矿洞内命中 low_oxygen 族（R3 碳不充分燃烧，D3 裁决），
# 其余按 ignite（硫火把、碳充分燃烧）。
func ignite() -> void:
	var recipe: Dictionary = _db().get_recipe(HYDROGEN_RECIPE_ID)
	var r4_inputs: Array = recipe.get("inputs", [])
	if _same_items(_slots, r4_inputs) and _tool == str(recipe.get("tool", "")) and _hydrogen != null:
		_settle(_hydrogen.ignite(_slots))
		return
	_settle(_db().try_craft(_slots, _tool, _ignite_condition()))


# 验纯步骤是否出现（FR-G-09 AC1）：格内有氢气且已解锁。
func can_purity_check() -> bool:
	if not _slots.has(HYDROGEN_INPUT_ID):
		return false
	if _hydrogen == null:
		return false
	return bool(_hydrogen.is_purity_check_available())


# 执行验纯（FR-G-09 AC2）：噗声 + sys_purity_ok，由 HydrogenEvent 结算。
func purity_check() -> bool:
	if not can_purity_check():
		return false
	var ok: bool = bool(_hydrogen.do_purity_check())
	_refresh()
	return ok


# ==== 内部 ====

# 点燃条件（D3 裁决）：矿洞内且材料+器材命中某条 low_oxygen 配方时按 low_oxygen 匹配，
# 否则恒为 ignite（SPEC-02 §4.4 口径）。
func _ignite_condition() -> String:
	if _current_zone() == ZONE_MINE and _matches_low_oxygen_recipe():
		return CONDITION_LOW_OXYGEN
	return CONDITION_IGNITE


# 是否存在一条 low_oxygen 配方与当前材料+器材吻合（数据驱动，不硬编码配方 id）。
func _matches_low_oxygen_recipe() -> bool:
	var db: Node = _db()
	if db == null:
		return false
	for recipe: Dictionary in db.all_recipes():
		if str(recipe.get("condition", "")) != CONDITION_LOW_OXYGEN:
			continue
		if str(recipe.get("tool", "")) != _tool:
			continue
		if _same_items(_slots, recipe.get("inputs", []) as Array):
			return true
	return false


func _current_zone() -> String:
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm == null:
		return ""
	return str(gm.current_zone())


# 结算配方结果：成功消耗材料、产物入包、弹卡片；失败给数据表文案、材料不动。
func _settle(result: Dictionary) -> void:
	if result.is_empty():
		return
	if bool(result.get("success", false)):
		for output_id: Variant in (result.get("outputs", []) as Array):
			if _inventory != null:
				_inventory.add_item(str(output_id), 1)
		_slots.clear()
		_show_unlock_tip(str(result.get("recipe_id", "")))
		card_ready.emit(result.get("card", {}))
		_refresh()
		return
	var fail_reason: String = str(result.get("fail_reason", ""))
	if fail_reason == REASON_NEEDS_PURITY:
		# 爆炸事件已接管（字幕 sys_explosion_warn），不再显示失败池文案。
		_refresh()
		return
	var fail_id: String = str(result.get("fail_tip_id", ""))
	var message: Dictionary = _db().get_fail_message(fail_id)
	var text: String = str(message.get("text", ""))
	if not text.is_empty():
		var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
		if tip != null:
			tip.show_custom(text, FAIL_STYLE, FAIL_DURATION)
	_refresh()


# 合成成功消费配方 unlock_tip（SPEC-04 §3）：非空则走字幕，空则跳过（如 r_carbon_activate）。
func _show_unlock_tip(recipe_id: String) -> void:
	if recipe_id.is_empty():
		return
	var tip_id: String = str(_db().get_recipe(recipe_id).get("unlock_tip", ""))
	if tip_id.is_empty():
		return
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip != null:
		tip.show(tip_id)


func _return_all_materials() -> void:
	if _inventory != null:
		for item_id: String in _slots:
			_inventory.add_item(item_id, 1)
	_slots.clear()


func _same_items(a: Array, b: Array) -> bool:
	var sa: Array[String] = []
	var sb: Array[String] = []
	for item: Variant in a:
		sa.append(str(item))
	for item: Variant in b:
		sb.append(str(item))
	sa.sort()
	sb.sort()
	return sa == sb


# 界面刷新：格子显示物质/道具名（数据表），器材高亮当前选项，验纯按钮按出现条件显隐。
func _refresh() -> void:
	for i: int in range(_slot_buttons.size()):
		var button: Button = _slot_buttons[i]
		if i < _slots.size():
			button.text = _display_name(_slots[i])
		else:
			button.text = _ui(UI_SLOT_EMPTY)
	for tool: String in TOOL_OPTIONS:
		(_tool_buttons[tool] as Button).modulate = Color(1, 1, 1) if tool == _tool else Color(0.6, 0.6, 0.6)
	_purity_button.visible = can_purity_check()


# 名称解析同采集物：先物质表再道具表；都查不到显示 id 本身（不崩溃）。
func _display_name(item_id: String) -> String:
	var substance: Dictionary = _db().get_substance(item_id)
	if not substance.is_empty():
		return str(substance.get("name", item_id))
	var items: RefCounted = (load("res://scripts/gameplay/item_effects.gd") as GDScript).new()
	var item: Dictionary = items.get_item(item_id)
	if not item.is_empty():
		return str(item.get("name", item_id))
	return item_id


func _db() -> Node:
	return get_node_or_null(^"/root/RecipeDB")


func _ui(key: String) -> String:
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm == null:
		return key
	return gm.get_ui_string(key)
