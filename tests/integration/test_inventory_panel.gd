# IT-U05 / FR-U-05（含 FR-G-02 AC4）：背包界面——Tab 开关、格子图标与数量、
# 占位图兜底、打开时玩家输入被屏蔽（ui_manager 裁决）、支持拖拽到合成台。
extends GutTest

const PANEL_SCENE: String = "res://scenes/ui/inventory_panel.tscn"
const PANEL_SCRIPT: String = "res://scenes/ui/inventory_panel.gd"
const UI_MANAGER_SCRIPT: String = "res://scenes/main/ui_manager.gd"
const INVENTORY_SCRIPT: String = "res://scripts/gameplay/inventory.gd"

var gm: Node = null
var _inventory: RefCounted = null
var _panel: Node = null


# 通用假面板：验证 ui_manager 互斥时充当「另一个面板」。
class FakePanel:
	extends Control
	var _open: bool = false
	func open() -> void:
		_open = true
		visible = true
	func close() -> void:
		_open = false
		visible = false
	func is_open() -> bool:
		return _open


func before_each() -> void:
	gm = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	assert_not_null(gm, "GameManager autoload 必须存在")
	if gm == null:
		return
	gm.reload_config()
	_inventory = (load(INVENTORY_SCRIPT) as GDScript).new()
	_panel = null
	if not ResourceLoader.exists(PANEL_SCENE):
		fail_test("尚未实现 %s（FR-U-05 / TP-06 补）" % PANEL_SCENE)
		return
	_panel = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child_autofree(_panel)
	await wait_process_frames(1)
	if _panel.has_method("bind"):
		_panel.bind(_inventory)


func _skip_unless_ready(method_names: Array = []) -> bool:
	if _panel == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not _panel.has_method(method_name):
			fail_test("背包界面应有 %s()（FR-U-05）" % method_name)
			return true
	return false


func _tab_event() -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = "inventory"
	event.pressed = true
	return event


# FR-G-02 AC4：Tab 打开/关闭背包界面。
func test_tab_toggles_panel() -> void:
	if _skip_unless_ready(["is_open"]):
		return
	assert_false(_panel.is_open(), "初始关闭")
	_panel._unhandled_input(_tab_event())
	assert_true(_panel.is_open(), "Tab 应打开背包")
	assert_true(_panel.visible, "打开时可见")
	_panel._unhandled_input(_tab_event())
	assert_false(_panel.is_open(), "再按 Tab 应关闭")


# FR-G-02 AC4：格子数 = 背包格数（8），显示数量；信号驱动刷新（不轮询）。
func test_slots_show_counts_and_follow_signal() -> void:
	if _skip_unless_ready(["slot_count", "slot_count_text"]):
		return
	assert_eq(_panel.slot_count(), _inventory.slot_count(), "格子数应与背包一致")
	_inventory.add_item("o2", 3)
	_inventory.add_item("stick", 1)
	await wait_process_frames(1)
	assert_eq(_panel.slot_count_text(0), "3", "第一格数量 3")
	assert_eq(_panel.slot_count_text(1), "1", "第二格数量 1")
	_inventory.add_item("o2", 2)
	await wait_process_frames(1)
	assert_eq(_panel.slot_count_text(0), "5", "inventory_changed 信号驱动刷新")


# AC2：图标缺失时显示占位纹理，不留空白也不崩溃。
func test_missing_icon_uses_placeholder() -> void:
	if _skip_unless_ready(["slot_icon_texture"]):
		return
	_inventory.add_item("o2", 1)
	await wait_process_frames(1)
	var tex: Texture2D = _panel.slot_icon_texture(0)
	assert_not_null(tex, "图标缺失时必须有占位纹理")
	assert_true(tex.get_width() > 0, "占位纹理不应是空图")


# 空格子：数量为空串、不显示物品（边界）。
func test_empty_slot_shows_nothing() -> void:
	if _skip_unless_ready(["slot_count_text", "slot_item_id"]):
		return
	assert_eq(_panel.slot_count_text(0), "", "空格数量为空")
	assert_eq(_panel.slot_item_id(0), "", "空格无物品 id")


# 拖拽支持（FR-U-05：拖到合成台）：格子提供拖拽数据，空格不提供。
func test_slots_provide_drag_data() -> void:
	if _skip_unless_ready(["slot_button"]):
		return
	_inventory.add_item("o2", 2)
	await wait_process_frames(1)
	var slot: Node = _panel.slot_button(0)
	assert_not_null(slot, "应有第 0 格")
	if slot == null:
		return
	var data: Variant = slot._get_drag_data(Vector2.ZERO)
	assert_true(data is Dictionary, "拖拽数据应为字典")
	if data is Dictionary:
		assert_eq(str(data.get("id", "")), "o2", "拖拽数据携带物品 id")
	var empty_slot: Node = _panel.slot_button(1)
	if empty_slot != null:
		assert_eq(empty_slot._get_drag_data(Vector2.ZERO), null, "空格不提供拖拽")


# AC1：打开时玩家输入被屏蔽——ui_manager 裁决（聊天框例外由世界注册时声明）。
func test_ui_manager_blocks_input_when_panel_open() -> void:
	if not FileAccess.file_exists(UI_MANAGER_SCRIPT):
		fail_test("尚未实现 %s（SPEC-03 §8）" % UI_MANAGER_SCRIPT)
		return
	if _skip_unless_ready(["open", "close"]):
		return
	var manager: Node = (load(UI_MANAGER_SCRIPT) as GDScript).new()
	add_child_autofree(manager)
	manager.register_panel("inventory", _panel, true)
	assert_false(manager.input_blocked(), "无面板打开时不屏蔽")
	manager.open("inventory")
	assert_true(_panel.is_open(), "经 ui_manager 打开背包")
	assert_true(manager.input_blocked(), "背包打开时输入被屏蔽")
	manager.close_active()
	assert_false(manager.input_blocked(), "关闭后恢复")


# SPEC-03 §8：模态面板互斥——打开另一个面板时当前面板被关闭。
func test_ui_manager_enforces_exclusivity() -> void:
	if not FileAccess.file_exists(UI_MANAGER_SCRIPT):
		fail_test("尚未实现 %s（SPEC-03 §8）" % UI_MANAGER_SCRIPT)
		return
	if _skip_unless_ready(["open"]):
		return
	var manager: Node = (load(UI_MANAGER_SCRIPT) as GDScript).new()
	add_child_autofree(manager)
	var other: FakePanel = FakePanel.new()
	add_child_autofree(other)
	manager.register_panel("inventory", _panel, true)
	manager.register_panel("craft", other, true)
	manager.open("inventory")
	manager.open("craft")
	assert_false(_panel.is_open(), "打开合成台时背包应被关闭")
	assert_true(other.is_open(), "合成台应打开")
	assert_eq(manager.active_panel(), "craft", "当前面板应为 craft")


# ui_manager 的聊天例外：注册为不屏蔽的面板打开时不挡输入（FR-M-02 AC1）。
func test_ui_manager_chat_exception_does_not_block() -> void:
	if not FileAccess.file_exists(UI_MANAGER_SCRIPT):
		fail_test("尚未实现 %s（SPEC-03 §8）" % UI_MANAGER_SCRIPT)
		return
	var manager: Node = (load(UI_MANAGER_SCRIPT) as GDScript).new()
	add_child_autofree(manager)
	var chat: FakePanel = FakePanel.new()
	add_child_autofree(chat)
	manager.register_panel("chat", chat, false)
	manager.open("chat")
	assert_false(manager.input_blocked(), "聊天框打开不屏蔽玩家输入")


# NFR-04：逻辑代码里不许出现中文字面量（注释与诊断日志除外）。
func test_scripts_have_no_hardcoded_chinese() -> void:
	for path: String in [PANEL_SCRIPT, UI_MANAGER_SCRIPT]:
		if not FileAccess.file_exists(path):
			fail_test("尚未实现 %s" % path)
			continue
		var text: String = FileAccess.get_file_as_string(path)
		for line in text.split("\n"):
			var stripped: String = str(line).strip_edges()
			if stripped.begins_with("#"):
				continue
			if stripped.contains("push_warning") or stripped.contains("push_error") or stripped.contains("print("):
				continue
			assert_false(_has_cjk(stripped), "%s 逻辑代码里不许硬编码中文（NFR-04）：%s" % [path, stripped])


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
