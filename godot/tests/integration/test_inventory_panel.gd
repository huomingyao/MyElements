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


func _craft_event() -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = "craft"
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


# 占位纹理缓存（包E）：同一物品跨刷新复用同一纹理实例，不再每格每刷新建图。
func test_placeholder_texture_cached_across_refreshes() -> void:
	if _skip_unless_ready(["slot_icon_texture"]):
		return
	_inventory.add_item("o2", 1)
	await wait_process_frames(1)
	var tex_before: Texture2D = _panel.slot_icon_texture(0)
	assert_not_null(tex_before, "前提：有占位纹理")
	_inventory.add_item("stick", 1) # 触发整表刷新
	await wait_process_frames(1)
	var tex_after: Texture2D = _panel.slot_icon_texture(0)
	assert_true(tex_before == tex_after, "刷新后同一物品应复用缓存纹理，不再重建")


# 占位纹理缓存按颜色键共享：同色同实例，异色各自缓存。
func test_placeholder_cache_keyed_by_color() -> void:
	if _skip_unless_ready(["placeholder_texture_for"]):
		return
	var red_a: Texture2D = _panel.placeholder_texture_for(Color(1.0, 0.0, 0.0))
	var red_b: Texture2D = _panel.placeholder_texture_for(Color(1.0, 0.0, 0.0))
	var blue: Texture2D = _panel.placeholder_texture_for(Color(0.0, 0.0, 1.0))
	assert_true(red_a == red_b, "同色应命中缓存返回同一实例")
	assert_true(red_a != blue, "不同色应各自缓存")
	if red_a != null:
		assert_eq(red_a.get_width(), 32, "占位纹理尺寸应为 PLACEHOLDER_SIZE(32)")


# 拖拽预览（包E）：占位纹理 + 数量角标，不再只是纯文字 Label。
func test_drag_preview_uses_placeholder_with_count_badge() -> void:
	if _skip_unless_ready(["make_drag_preview"]):
		return
	var preview: Control = _panel.make_drag_preview("o2", "3") as Control
	assert_not_null(preview, "应能构建拖拽预览")
	if preview == null:
		return
	var icon: TextureRect = preview.get_node_or_null(^"Icon") as TextureRect
	assert_not_null(icon, "预览应带占位纹理节点")
	if icon != null:
		assert_not_null(icon.texture, "预览占位纹理不应为空")
	var badge: Label = preview.get_node_or_null(^"Count") as Label
	assert_not_null(badge, "预览应带数量角标")
	if badge != null:
		assert_eq(str(badge.text), "3", "角标应显示数量")


# 拖拽预览用真实图标（FR-G-05 AC5 拖拽合成）：图标文件存在时预览显示资源本身，
# 不是色块占位；不存在才回退色块。
func test_drag_preview_prefers_real_icon() -> void:
	if _skip_unless_ready(["make_drag_preview"]):
		return
	var preview: Control = _panel.make_drag_preview("o2", "") as Control
	if preview == null:
		return
	var icon: TextureRect = preview.get_node_or_null(^"Icon") as TextureRect
	assert_not_null(icon, "预览应带图标节点")
	if icon == null:
		return
	assert_not_null(icon.texture, "预览应有纹理")
	if icon.texture != null:
		assert_eq(icon.texture.resource_path, "res://assets/art/icons/o2.png", "图标存在时预览应用真实资源图")


# AC1：打开时玩家输入被屏蔽——ui_manager 裁决（聊天框例外由世界注册时声明）。func test_ui_manager_blocks_input_when_panel_open() -> void:
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


# FR-G-05 AC4：背包打开时按 X（craft 动作）发出合成请求；未打开不触发；动作已注册。
func test_craft_key_requests_craft_only_when_open() -> void:
	assert_true(InputMap.has_action("craft"), "输入动作 craft 应已注册（FR-G-05 AC4）")
	if _skip_unless_ready(["open", "close"]):
		return
	if not _panel.has_signal("craft_requested"):
		fail_test("背包界面应有 craft_requested 信号（FR-G-05 AC4）")
		return
	var fired: Array = []
	_panel.craft_requested.connect(func() -> void: fired.append(1))
	_panel._unhandled_input(_craft_event())
	assert_eq(fired.size(), 0, "背包未打开时不应触发合成请求")
	_panel.open()
	_panel._unhandled_input(_craft_event())
	assert_eq(fired.size(), 1, "背包打开时按 craft 键应发出合成请求")


# FR-G-05 AC4/AC5：craft_requested 经 ui_manager 同屏并列打开合成台（背包不关），
# 再按 X（toggle）关闭合成台、背包保持。
func test_craft_request_opens_craft_alongside_inventory() -> void:
	if not FileAccess.file_exists(UI_MANAGER_SCRIPT):
		fail_test("尚未实现 %s（SPEC-03 §8）" % UI_MANAGER_SCRIPT)
		return
	if _skip_unless_ready(["open"]):
		return
	if not _panel.has_signal("craft_requested"):
		fail_test("背包界面应有 craft_requested 信号（FR-G-05 AC4）")
		return
	var manager: Node = (load(UI_MANAGER_SCRIPT) as GDScript).new()
	add_child_autofree(manager)
	var craft: FakePanel = FakePanel.new()
	add_child_autofree(craft)
	manager.register_panel("inventory", _panel, true, "crafting")
	manager.register_panel("craft", craft, true, "crafting")
	# 世界接线等价物：craft_requested → 开/关合成台（同组共存，背包不关）。
	_panel.craft_requested.connect(manager.toggle.bind("craft"))
	manager.open("inventory")
	_panel._unhandled_input(_craft_event())
	assert_true(craft.is_open(), "按 X 应打开合成界面")
	assert_true(_panel.is_open(), "合成台打开时背包应保持同屏打开（AC5）")
	assert_eq(manager.active_panel(), "craft", "最上面板应为 craft")
	_panel._unhandled_input(_craft_event())
	assert_false(craft.is_open(), "再按 X 应关闭合成界面")
	assert_true(_panel.is_open(), "关闭合成台后背包保持打开")


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
