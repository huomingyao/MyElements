# IT-U03 / FR-U-03：世界地图页——13 热区齐全且状态与 worldmap.json 一致；
# 已解锁显示简介 brief；未解锁抖动一次 + 预告语 teaser +「赛后解锁」角标且不可进入；
# M 键开关；文案全部来自数据表（NFR-04）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const PANEL_SCENE: String = "res://scenes/main/world_map_panel.tscn"
const PANEL_SCRIPT: String = "res://scenes/main/world_map_panel.gd"
const UI_BADGE: String = "map_locked_badge"

var _panel: Node = null
var _wm: Node = null


func before_each() -> void:
	_panel = null
	_wm = Engine.get_main_loop().root.get_node_or_null(^"WorldMap")
	assert_not_null(_wm, "WorldMap autoload 必须存在")
	if _wm == null:
		return
	_wm.reload()
	if _wm.is_open():
		_wm.close()
	if not ResourceLoader.exists(PANEL_SCENE):
		fail_test("尚未实现 %s（FR-U-03 / TP-12）" % PANEL_SCENE)
		return
	_panel = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child_autofree(_panel)
	await wait_process_frames(1)


func after_each() -> void:
	if _wm != null and _wm.is_open():
		_wm.close()


func _skip_unless_ready(method_names: Array = []) -> bool:
	if _panel == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not _panel.has_method(method_name):
			fail_test("WorldMapPanel 应有 %s()（FR-U-03）" % method_name)
			return true
	return false


func _send_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


# AC2：13 个区域热区齐全，id 与顺序跟 worldmap.json 一致，热区矩形照表摆放。
func test_thirteen_hotspots_match_worldmap_json() -> void:
	if _skip_unless_ready(["hotspot_ids", "hotspot"]):
		return
	var rows: Array = Fixture.rows_of("worldmap.json")
	assert_eq(rows.size(), 13, "worldmap.json 应有 13 条（UT-D06 口径）")
	var expected_ids: Array = []
	for row in rows:
		expected_ids.append(str(row.get("id", "")))
	assert_eq(_panel.hotspot_ids(), expected_ids, "热区 id 与顺序应与 worldmap.json 一致")
	for row in rows:
		var zone_id: String = str(row.get("id", ""))
		var spot: Node = _panel.hotspot(zone_id)
		assert_not_null(spot, "应有热区 %s" % zone_id)
		if spot == null:
			continue
		var hs: Dictionary = row.get("hotspot", {})
		assert_eq(
			spot.position,
			Vector2(float(hs.get("x", -1)), float(hs.get("y", -1))),
			"%s 热区位置应照表摆放" % zone_id
		)
		assert_eq(
			spot.size,
			Vector2(float(hs.get("w", -1)), float(hs.get("h", -1))),
			"%s 热区尺寸应照表摆放" % zone_id
		)


# AC2：5 彩色已解锁 + 8 灰色剪影，状态与数据表一致；未解锁带「赛后解锁」角标。
func test_hotspot_states_match_data_table() -> void:
	if _skip_unless_ready(["hotspot"]):
		return
	var rows: Array = Fixture.rows_of("worldmap.json")
	var badge_text: String = str(Fixture.read_object("ui_strings.json").get(UI_BADGE, ""))
	assert_false(badge_text.is_empty(), "ui_strings.json 应有 %s" % UI_BADGE)
	var unlocked_count: int = 0
	for row in rows:
		var zone_id: String = str(row.get("id", ""))
		var unlocked: bool = bool(row.get("unlocked", false))
		assert_eq(_wm.is_unlocked(zone_id), unlocked, "%s 解锁状态应与数据表一致" % zone_id)
		var spot: Node = _panel.hotspot(zone_id)
		if spot == null:
			continue
		var badge: Node = spot.get_node_or_null(NodePath("Badge"))
		if unlocked:
			unlocked_count += 1
			var tint: Color = spot.modulate
			assert_false(
				is_equal_approx(tint.r, tint.g) and is_equal_approx(tint.g, tint.b),
				"已解锁区域应是彩色而非灰色剪影：%s" % zone_id
			)
			assert_null(badge, "已解锁区域不该有角标：%s" % zone_id)
		else:
			var tint2: Color = spot.modulate
			assert_true(
				is_equal_approx(tint2.r, tint2.g) and is_equal_approx(tint2.g, tint2.b),
				"未解锁区域应是灰色剪影：%s" % zone_id
			)
			assert_not_null(badge, "未解锁区域应有「赛后解锁」角标：%s" % zone_id)
			if badge != null:
				assert_eq(str(badge.text), badge_text, "角标文案应取自 ui_strings.%s" % UI_BADGE)
	assert_eq(unlocked_count, 5, "已解锁区域应恰好 5 个")


# AC3：点击已解锁区域显示简介 brief（数据表原文）。
func test_unlocked_zone_click_shows_brief() -> void:
	if _skip_unless_ready(["hotspot", "info_text"]):
		return
	for row in Fixture.rows_of("worldmap.json"):
		if not bool(row.get("unlocked", false)):
			continue
		var zone_id: String = str(row.get("id", ""))
		var spot: Node = _panel.hotspot(zone_id)
		if spot == null:
			continue
		spot.pressed.emit()
		assert_eq(
			_panel.info_text(),
			str(row.get("brief", "")),
			"点击已解锁 %s 应显示 brief 原文" % zone_id
		)


# AC3：点击未解锁区域抖动一次 + 显示预告语 teaser，不可进入（不切场景）。
func test_locked_zone_click_shakes_shows_teaser_and_never_enters() -> void:
	if _skip_unless_ready(["hotspot", "info_text"]):
		return
	var scene_before: Node = get_tree().current_scene
	for row in Fixture.rows_of("worldmap.json"):
		if bool(row.get("unlocked", false)):
			continue
		var zone_id: String = str(row.get("id", ""))
		var spot: Node = _panel.hotspot(zone_id)
		if spot == null:
			continue
		watch_signals(_panel)
		spot.pressed.emit()
		assert_eq(
			_panel.info_text(),
			str(row.get("teaser", "")),
			"点击未解锁 %s 应显示 teaser 原文" % zone_id
		)
		assert_signal_emitted_with_parameters(
			_panel, "locked_zone_shaken", [zone_id], -1
		)
		assert_eq(get_tree().current_scene, scene_before, "未解锁区域不可进入（不许切场景）")
		assert_false(_wm.is_unlocked(zone_id), "%s 不应被点击解锁" % zone_id)


# AC1：游戏内 M 键打开/关闭地图页（走 WorldMap autoload 信号，面板只负责显隐）。
func test_m_key_toggles_map_panel() -> void:
	if _panel == null:
		return
	assert_false(_panel.visible, "初始应隐藏")
	_send_action("worldmap")
	await wait_process_frames(2)
	assert_true(_wm.is_open(), "按 M 应打开地图页")
	assert_true(_panel.visible, "打开后面板应可见")
	_send_action("worldmap")
	await wait_process_frames(2)
	assert_false(_wm.is_open(), "再按 M 应关闭地图页")
	assert_false(_panel.visible, "关闭后面板应隐藏")


# AC4 + NFR-04：区域名显示在热区上且来自数据表；面板脚本无中文字面量。
func test_zone_texts_come_from_data_tables() -> void:
	if _skip_unless_ready(["hotspot"]):
		return
	for row in Fixture.rows_of("worldmap.json"):
		var zone_id: String = str(row.get("id", ""))
		var spot: Node = _panel.hotspot(zone_id)
		if spot == null:
			continue
		var name_label: Node = spot.get_node_or_null(NodePath("NameLabel"))
		assert_not_null(name_label, "%s 热区应有 NameLabel" % zone_id)
		if name_label != null:
			assert_eq(
				str(name_label.text),
				str(row.get("name", "")),
				"%s 热区名称应取自 worldmap.json" % zone_id
			)
	var text: String = FileAccess.get_file_as_string(PANEL_SCRIPT)
	assert_false(text.is_empty(), "应能读到 %s" % PANEL_SCRIPT)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		# 日志文案允许中文（与现有 autoload 同一约定）；禁的是流向界面的硬编码文案。
		if stripped.contains("push_warning(") or stripped.contains("push_error("):
			continue
		assert_false(_has_cjk(stripped), "逻辑代码里不许硬编码中文（NFR-04）：%s" % stripped)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
