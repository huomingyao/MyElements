# IT-M10 / FR-M-10：配置面板占位（SPEC-03 §6.4）。
# 断言接线：key 只转发给 LLMClient.set_api_key（非空才转发）、离线开关转发且开面板时同步、
# 滑块可拖但没人消费、说明文字取自 ui_strings.config_note。
# 安全（NFR-05）：注入假客户端，**不碰真实 user://config.cfg**、不回显、不记录 key。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const PANEL_PATH: String = "res://scenes/mentor/config_panel.tscn"
const SCRIPT_PATH: String = "res://scenes/mentor/config_panel.gd"
const NOTE_KEY: String = "config_note"
const APPLY_KEY: String = "config_apply"
const UI_MANAGER_SCRIPT: String = "res://scenes/main/ui_manager.gd"

const N_KEY_INPUT: String = "KeyInput"
const N_APPLY: String = "ApplyButton"
const N_TOGGLE: String = "OfflineToggle"
const N_SLIDER: String = "PersonalitySlider"
const N_NOTE: String = "NoteLabel"

var _panel: Node = null
var _client: Node = null


# 假客户端：只记录被转发了什么，绝不落盘。签名与 LLMClient 的冻结面一致（SPEC-03 §6.2）。
class FakeClient:
	extends Node

	signal mode_changed(offline: bool)

	var keys: Array = []
	var offline_calls: Array = []
	var _offline: bool = false

	func set_api_key(key: String) -> void:
		keys.append(key)

	func is_offline() -> bool:
		return _offline

	func set_offline(value: bool) -> void:
		offline_calls.append(value)
		if _offline == value:
			return
		_offline = value
		mode_changed.emit(_offline)

	func force_offline(value: bool) -> void:
		_offline = value


func before_each() -> void:
	_panel = null
	_client = null
	if not ResourceLoader.exists(PANEL_PATH):
		fail_test("尚未实现 %s（FR-M-10 / SPEC-03 §6.4）" % PANEL_PATH)
		return
	_client = FakeClient.new()
	add_child_autofree(_client)
	_panel = (load(PANEL_PATH) as PackedScene).instantiate()
	if not _panel.has_method("set_client"):
		fail_test("ConfigPanel 应有 set_client()（SPEC-03 §6.4 非契约辅助）")
		_panel.free()
		_panel = null
		return
	_panel.set_client(_client)
	add_child_autofree(_panel)
	await wait_process_frames(1)


# 缺实现或缺方法时记为断言失败并跳过，避免 before_each 崩掉后 GUT 误报通过。
func _skip_unless(method_names: Array) -> bool:
	if _panel == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not _panel.has_method(method_name):
			fail_test("ConfigPanel 应有 %s()（SPEC-03 §6.4）" % method_name)
			return true
	return false


# 唯一名节点（%Name）；缺节点直接记失败，别让后面的断言拿 null 崩掉。
func _node(unique_name: String) -> Node:
	var found: Node = _panel.get_node_or_null(NodePath("%%%s" % unique_name))
	if found == null:
		fail_test("ConfigPanel 应有唯一名节点 %%%s（SPEC-03 §6.4）" % unique_name)
	return found


func _ui_string(key: String) -> String:
	return str(Fixture.read_object("ui_strings.json").get(key, ""))


# AC1：输入 key → apply_api_key() 转发给 LLMClient.set_api_key()，写入只发生在 user://。
func test_apply_api_key_forwards_to_client() -> void:
	if _skip_unless(["apply_api_key"]):
		return
	var input: Node = _node(N_KEY_INPUT)
	if input == null:
		return
	input.text = "sk-not-a-real-key"
	assert_true(_panel.apply_api_key(), "非空 key 应转发成功")
	assert_eq(_client.keys, ["sk-not-a-real-key"], "key 应原样交给 LLMClient.set_api_key()")


# AC1：空串/纯空白不转发——避免误清掉玩家已配好的 key。
func test_empty_key_is_not_forwarded() -> void:
	if _skip_unless(["apply_api_key"]):
		return
	var input: Node = _node(N_KEY_INPUT)
	if input == null:
		return
	input.text = ""
	assert_false(_panel.apply_api_key(), "空 key 应返回 false")
	input.text = "   "
	assert_false(_panel.apply_api_key(), "纯空白也算空")
	assert_eq(_client.keys, [], "空 key 一次都不该转发")


# NFR-05：key 输入框必须遮挡显示，且面板不提供任何读 key 的出口。
func test_key_input_is_secret_and_panel_never_exposes_key() -> void:
	if _panel == null:
		return
	var input: Node = _node(N_KEY_INPUT)
	if input == null:
		return
	assert_true(input.secret, "key 输入框必须 secret=true（NFR-05）")
	for method_name in ["api_key", "get_api_key", "key"]:
		assert_false(
			_panel.has_method(method_name),
			"面板不许提供读 key 的方法（NFR-05）：%s()" % method_name
		)


# FR-M-08 AC4：手动离线开关转发给 LLMClient，两个方向都要。
func test_offline_toggle_forwards_both_directions() -> void:
	if _skip_unless(["set_offline_toggle"]):
		return
	_panel.set_offline_toggle(true)
	assert_true(_client.is_offline(), "开关打开应让客户端进离线")
	_panel.set_offline_toggle(false)
	assert_false(_client.is_offline(), "开关关闭应让客户端回在线")
	assert_eq(_client.offline_calls, [true, false], "应逐次转发：%s" % str(_client.offline_calls))


# FR-M-08 AC4：勾选 CheckButton 本身即生效（不需要额外按确定）。
func test_toggle_node_signal_drives_client() -> void:
	if _panel == null:
		return
	var toggle: Node = _node(N_TOGGLE)
	if toggle == null:
		return
	toggle.button_pressed = true
	toggle.toggled.emit(true)
	assert_true(_client.is_offline(), "勾选开关应立即转发（FR-M-08 AC4）")


# 面板打开时显示状态必须与客户端真实状态一致，不许显示反的。
func test_toggle_syncs_with_client_state_on_open() -> void:
	if _panel == null:
		return
	var offline_client: Node = FakeClient.new()
	add_child_autofree(offline_client)
	offline_client.force_offline(true)
	var fresh: Node = (load(PANEL_PATH) as PackedScene).instantiate()
	fresh.set_client(offline_client)
	add_child_autofree(fresh)
	await wait_process_frames(1)
	var toggle: Node = fresh.get_node_or_null(NodePath("%%%s" % N_TOGGLE))
	assert_not_null(toggle, "应有 %%%s" % N_TOGGLE)
	if toggle == null:
		return
	assert_true(toggle.button_pressed, "客户端离线时开关应显示为开（SPEC-03 §6.4）")
	assert_eq(offline_client.offline_calls, [], "同步显示不该反向写回客户端")


# AC2：滑块可拖动（值确实变了），但拖动不产生任何行为——不碰客户端。
func test_personality_slider_moves_but_changes_nothing() -> void:
	if _skip_unless(["personality"]):
		return
	var slider: Node = _node(N_SLIDER)
	if slider == null:
		return
	assert_false(slider.editable == false, "滑块必须可拖动（AC2）")
	var before: float = float(_panel.personality())
	slider.value = slider.max_value
	slider.value_changed.emit(slider.value)
	await wait_process_frames(1)
	var after: float = float(_panel.personality())
	assert_ne(after, before, "拖到底后 personality() 应变化（AC2 前半：可拖动）")
	assert_eq(_client.keys, [], "拖滑块不该触发任何 key 写入")
	assert_eq(_client.offline_calls, [], "拖滑块不该改离线状态")


# 优化包C-6：MVP 期性格滑块对玩家隐藏（配置节点保留、赛后启用），避免误以为功能缺失。
func test_personality_slider_hidden_for_mvp() -> void:
	if _panel == null:
		return
	var slider: Node = _node(N_SLIDER)
	if slider == null:
		return
	assert_false(slider.visible, "MVP 期性格滑块应隐藏（死 UI 不上屏）")


# AC2：滑块值没人消费——除面板自身外，代码里不许出现 personality( 的调用。
func test_personality_value_is_consumed_by_nobody() -> void:
	var hits: Array = []
	for dir_path in ["res://scripts", "res://scenes"]:
		for file_path in _gd_files(dir_path):
			if file_path == SCRIPT_PATH:
				continue
			var text: String = FileAccess.get_file_as_string(file_path)
			if text.contains("personality("):
				hits.append(file_path)
	assert_eq(hits, [], "性格滑块不许被任何模块消费（FR-M-10 AC2）：%s" % str(hits))


# AC2：界面明示「赛后可配置」，且文案取自 ui_strings.json 而非硬编码（NFR-04）。
func test_note_text_comes_from_ui_strings() -> void:
	if _skip_unless(["note_text"]):
		return
	var expected: String = _ui_string(NOTE_KEY)
	assert_false(expected.is_empty(), "ui_strings.json 应有 %s" % NOTE_KEY)
	assert_eq(str(_panel.note_text()), expected, "说明文字应取自 ui_strings.%s" % NOTE_KEY)
	var note: Node = _node(N_NOTE)
	if note == null:
		return
	assert_eq(str(note.text), expected, "标签上显示的就是表里的原文")


# ==== 包A-3：可达性与 NFR-04 收口 ====

# NFR-04：Apply 按钮文案来自 ui_strings.config_apply，不再用场景里硬编码的 "OK"。
func test_apply_button_text_comes_from_ui_strings() -> void:
	if _panel == null:
		return
	var button: Node = _node(N_APPLY)
	if button == null:
		return
	var expected: String = _ui_string(APPLY_KEY)
	assert_false(expected.is_empty(), "ui_strings.json 应有 %s" % APPLY_KEY)
	assert_eq(
		str(button.get("text")), expected,
		"ApplyButton 文案应来自 ui_strings.%s（NFR-04）" % APPLY_KEY
	)


# ui_manager 面板契约（SPEC-03 §8）：open/close/is_open，初始隐藏等裁决器打开。
func test_panel_contract_open_close_is_open() -> void:
	if _skip_unless(["open", "close", "is_open"]):
		return
	assert_false(_panel.is_open(), "初始应处于关闭状态")
	assert_false(_panel.visible, "初始应隐藏（等 ui_manager 打开）")
	_panel.open()
	assert_true(_panel.is_open(), "open() 后应打开")
	assert_true(_panel.visible, "open() 后应可见")
	_panel.close()
	assert_false(_panel.is_open(), "close() 后应关闭")
	assert_false(_panel.visible, "close() 后应隐藏")


# 包A-3 可达性：面板在世界骨架（UILayer/UIManager）下实例化时自注册，
# 经 ui_manager.open() 打开并参与互斥裁决（模态：屏蔽玩家输入）。
func test_panel_registers_itself_with_ui_manager() -> void:
	var rig: Node = Node.new()
	add_child_autofree(rig)
	var ui_layer: Node = Node.new()
	ui_layer.name = "UILayer"
	rig.add_child(ui_layer)
	var manager: Node = (load(UI_MANAGER_SCRIPT) as GDScript).new()
	manager.name = "UIManager"
	ui_layer.add_child(manager)
	var client: Node = FakeClient.new()
	rig.add_child(client)
	var panel: Node = (load(PANEL_PATH) as PackedScene).instantiate()
	panel.set_client(client)
	rig.add_child(panel) # _ready 在此触发 → 应自注册
	await wait_process_frames(1)
	assert_true(manager.has_panel("config"), "面板应自注册进 ui_manager（包A-3 可达性）")
	if not manager.has_panel("config"):
		return
	manager.open("config")
	assert_true(manager.is_open("config"), "config 面板应能经 ui_manager 打开")
	assert_true(panel.is_open(), "面板应被 ui_manager 打开")
	assert_true(manager.input_blocked(), "config 是模态面板：打开时屏蔽玩家输入")
	manager.close_active()
	assert_false(panel.is_open(), "裁决关闭后面板应关闭")


# NFR-04：面板脚本里不许出现中文字面量（文案一律走 get_ui_string）。注释除外。
func test_panel_script_has_no_hardcoded_chinese() -> void:
	var text: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	assert_false(text.is_empty(), "应能读到 %s" % SCRIPT_PATH)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		assert_false(
			_has_cjk(stripped),
			"逻辑代码里不许硬编码中文（NFR-04）：%s" % stripped
		)


# NFR-05：面板脚本不许把 key 打进日志，也不许自己碰 user://。
func test_panel_never_logs_key_or_touches_user_config() -> void:
	var text: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	assert_false(text.is_empty(), "应能读到 %s" % SCRIPT_PATH)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		# 注释里可以提 user://，代码里不许——写盘只归 LLMClient.set_api_key()。
		assert_false(
			stripped.contains("user://"),
			"面板不许自己碰 user://（NFR-05）：%s" % stripped
		)
		var is_log: bool = (
			stripped.contains("push_error(")
			or stripped.contains("push_warning(")
			or stripped.contains("print(")
		)
		assert_false(
			is_log and (stripped.contains("KeyInput") or stripped.contains("key")),
			"日志里不许带 key（NFR-05）：%s" % stripped
		)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name_value: String = dir.get_next()
	while not name_value.is_empty():
		var full: String = "%s/%s" % [dir_path, name_value]
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name_value.ends_with(".gd"):
			out.append(full)
		name_value = dir.get_next()
	dir.list_dir_end()
	return out
