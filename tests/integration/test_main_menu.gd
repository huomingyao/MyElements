# IT-C08 / FR-C-08：三个门分别加载正确场景、按钮文案来自 ui_strings、
# Esc 打开暂停菜单并可返回主菜单、主菜单内按 M 可打开世界地图页（FR-U-03 AC1 入口之一）。
# AC3（加载 ≤3 秒）无法在 headless 断言，归手工验收（见 TP-12 报告）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const MENU_SCENE: String = "res://scenes/main/main_menu.tscn"
const MENU_SCRIPT: String = "res://scenes/main/main_menu.gd"
const PAUSE_SCENE: String = "res://scenes/main/pause_menu.tscn"
const PAUSE_SCRIPT: String = "res://scenes/main/pause_menu.gd"

# 世界场景路径由 SPEC-03 §8 钉死；图鉴路径是 TP-12 与 TP-16 的约定（见报告）。
# 2026-08-02：学院门改为整页进入导师室独立场景（取代 D2 世界内出生点覆盖）。
const WORLD_SCENE_PATH: String = "res://scenes/main/world.tscn"
const CODEX_SCENE_PATH: String = "res://scenes/ui/codex_panel.tscn"
const MENTOR_ROOM_SCENE_PATH: String = "res://scenes/mentor/mentor_room.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main/main_menu.tscn"

var _menu: Node = null
var _pause: Node = null
var _nav_calls: Array = []
var _quit_calls: int = 0
var _wm: Node = null


func before_each() -> void:
	_menu = null
	_pause = null
	_nav_calls = []
	_quit_calls = 0
	_wm = Engine.get_main_loop().root.get_node_or_null(^"WorldMap")
	if _wm != null:
		_wm.reload()
		if _wm.is_open():
			_wm.close()
	if not ResourceLoader.exists(MENU_SCENE):
		fail_test("尚未实现 %s（FR-C-08 / TP-12）" % MENU_SCENE)
		return
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	if not _menu.has_method("set_navigator"):
		fail_test("MainMenu 应有 set_navigator()（可注入导航，SPEC-06 §3 可测性）")
		_menu.free()
		_menu = null
		return
	_menu.set_navigator(_record_nav)
	if _menu.has_method("set_quitter"):
		_menu.set_quitter(_record_quit)
	add_child_autofree(_menu)
	await wait_process_frames(1)


func after_each() -> void:
	if _wm != null and _wm.is_open():
		_wm.close()


func _record_nav(path: String) -> void:
	_nav_calls.append(path)


func _record_quit() -> void:
	_quit_calls += 1


func _send_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _menu_node(unique_name: String) -> Node:
	var found: Node = _menu.get_node_or_null(NodePath("%%%s" % unique_name))
	if found == null:
		fail_test("MainMenu 应有唯一名节点 %%%s" % unique_name)
	return found


# AC1：开始冒险 / 导师学院 / 图鉴 门分别导航到世界 / 导师室 / 图鉴场景；
# 2026-08-02：学院门整页进入导师室独立场景（不再写出生点覆盖元数据）。
func test_three_doors_navigate_to_expected_scenes() -> void:
	if _menu == null:
		return
	var start_button: Node = _menu_node("StartButton")
	var academy_button: Node = _menu_node("AcademyButton")
	var codex_button: Node = _menu_node("CodexButton")
	if start_button == null or academy_button == null or codex_button == null:
		return
	start_button.pressed.emit()
	assert_eq(_nav_calls, [WORLD_SCENE_PATH], "开始冒险应加载世界场景")
	academy_button.pressed.emit()
	assert_eq(
		_nav_calls, [WORLD_SCENE_PATH, MENTOR_ROOM_SCENE_PATH],
		"学院门应整页进入导师室场景"
	)
	codex_button.pressed.emit()
	assert_eq(
		_nav_calls,
		[WORLD_SCENE_PATH, MENTOR_ROOM_SCENE_PATH, CODEX_SCENE_PATH],
		"图鉴门应加载图鉴界面"
	)


# 门上有退出入口；测试中注入假 quitter，绝不真退（会杀掉测试进程）。
func test_quit_button_invokes_quitter() -> void:
	if _menu == null:
		return
	var quit_button: Node = _menu_node("QuitButton")
	if quit_button == null:
		return
	quit_button.pressed.emit()
	assert_eq(_quit_calls, 1, "退出按钮应调用退出回调")


# 按钮文案全部来自 ui_strings.json（NFR-04）。
func test_button_labels_come_from_ui_strings() -> void:
	if _menu == null:
		return
	var strings: Dictionary = Fixture.read_object("ui_strings.json")
	var cases: Array = [
		["StartButton", "menu_start"],
		["AcademyButton", "menu_academy"],
		["CodexButton", "menu_codex"],
		["QuitButton", "menu_quit"],
	]
	for pair in cases:
		var button: Node = _menu_node(str(pair[0]))
		if button == null:
			continue
		var expected: String = str(strings.get(str(pair[1]), ""))
		assert_false(expected.is_empty(), "ui_strings.json 应有 %s" % str(pair[1]))
		assert_eq(str(button.text), expected, "%s 文案应取自 ui_strings.%s" % [str(pair[0]), str(pair[1])])


# FR-U-03 AC1：主菜单内按 M 可打开世界地图页（主菜单托管 WorldMapPanel）。
func test_world_map_opens_from_main_menu_via_m_key() -> void:
	if _menu == null:
		return
	assert_not_null(_wm, "WorldMap autoload 必须存在")
	if _wm == null:
		return
	_send_action("worldmap")
	await wait_process_frames(2)
	assert_true(_wm.is_open(), "主菜单内按 M 应打开世界地图页（FR-U-03 AC1）")
	var panel: Node = _menu.find_child("WorldMapPanel", true, false)
	assert_not_null(panel, "主菜单应托管 WorldMapPanel")
	if panel != null:
		assert_true(panel.visible, "地图页打开后面板应可见")
	_wm.close()
	await wait_process_frames(1)
	assert_false(_wm.is_open(), "收尾：地图页应能关闭")


# AC2：Esc 打开暂停菜单，再按 Esc 关闭。
func test_esc_toggles_pause_menu() -> void:
	_pause = _instantiate_pause()
	if _pause == null:
		return
	watch_signals(_pause)
	assert_false(_pause.visible, "初始应隐藏")
	_send_action("pause")
	await wait_process_frames(2)
	assert_true(_pause.visible, "Esc 应打开暂停菜单（FR-C-08 AC2）")
	assert_signal_emitted(_pause, "pause_toggled", "开关应发 pause_toggled 信号")
	_send_action("pause")
	await wait_process_frames(2)
	assert_false(_pause.visible, "再按 Esc 应关闭暂停菜单")


# AC2：暂停菜单可返回主菜单；继续按钮收起菜单。
func test_pause_menu_returns_to_main_menu() -> void:
	_pause = _instantiate_pause()
	if _pause == null:
		return
	_pause.open()
	await wait_process_frames(1)
	var menu_button: Node = _pause.get_node_or_null(NodePath("%MenuButton"))
	var continue_button: Node = _pause.get_node_or_null(NodePath("%ContinueButton"))
	assert_not_null(menu_button, "暂停菜单应有 %MenuButton")
	assert_not_null(continue_button, "暂停菜单应有 %ContinueButton")
	if menu_button == null or continue_button == null:
		return
	menu_button.pressed.emit()
	assert_eq(_nav_calls, [MAIN_MENU_SCENE_PATH], "返回主菜单应导航到主菜单场景")
	continue_button.pressed.emit()
	assert_false(_pause.visible, "继续按钮应收起暂停菜单")


func _instantiate_pause() -> Node:
	if not ResourceLoader.exists(PAUSE_SCENE):
		fail_test("尚未实现 %s（FR-C-08 AC2 / TP-12）" % PAUSE_SCENE)
		return null
	var node: Node = (load(PAUSE_SCENE) as PackedScene).instantiate()
	if not node.has_method("set_navigator"):
		fail_test("PauseMenu 应有 set_navigator()（可注入导航）")
		node.free()
		return null
	node.set_navigator(_record_nav)
	add_child_autofree(node)
	return node


# NFR-04：主菜单与暂停菜单的逻辑代码里不许出现中文字面量（注释除外）。
func test_menu_scripts_have_no_hardcoded_chinese() -> void:
	for script_path in [MENU_SCRIPT, PAUSE_SCRIPT]:
		var text: String = FileAccess.get_file_as_string(str(script_path))
		assert_false(text.is_empty(), "应能读到 %s" % str(script_path))
		for line in text.split("\n"):
			var stripped: String = str(line).strip_edges()
			if stripped.begins_with("#"):
				continue
			# 日志文案允许中文（与 game_manager.gd 等现有 autoload 同一约定）；
			# 禁的是流向界面的硬编码文案。
			if stripped.contains("push_warning(") or stripped.contains("push_error("):
				continue
			assert_false(
				_has_cjk(stripped),
				"%s 逻辑代码里不许硬编码中文（NFR-04）：%s" % [str(script_path), stripped]
			)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
