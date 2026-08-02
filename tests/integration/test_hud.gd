# IT-C07 / FR-C-07：三条数值条信号驱动（非轮询）、已收集计数、
# 氧气低于阈值闪烁并触发一次 sys_oxygen_low、时间/天数指示随昼夜信号更新。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const HUD_SCENE: String = "res://scenes/main/hud.tscn"
const HUD_SCRIPT: String = "res://scenes/main/hud.gd"
const TIP_OXYGEN_LOW: String = "sys_oxygen_low"
const BAL_LOW_OXYGEN: String = "stats.hud_low_oxygen_threshold"
const BAL_DAY_DURATION: String = "daynight.day_duration"
const BAL_NIGHT_DURATION: String = "daynight.night_duration"
const UI_COLLECTED: String = "collected_counter"

var _hud: Node = null
var _gm: Node = null
var _tip: Node = null
var _low_tip_count: int = 0


func before_each() -> void:
	_hud = null
	_gm = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	_tip = Engine.get_main_loop().root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(_gm, "GameManager autoload 必须存在")
	assert_not_null(_tip, "KnowledgeTip autoload 必须存在")
	if _gm == null or _tip == null:
		return
	_gm.reload_config()
	_gm.reset_clock()
	_gm.reset_stats()
	_gm.set_zone("grassland")
	_tip.clear_queue()
	_low_tip_count = 0
	if not ResourceLoader.exists(HUD_SCENE):
		fail_test("尚未实现 %s（FR-C-07 / TP-12）" % HUD_SCENE)
		return
	_hud = (load(HUD_SCENE) as PackedScene).instantiate()
	add_child_autofree(_hud)
	await wait_process_frames(1)


func after_each() -> void:
	if _tip != null and _tip.tip_shown.is_connected(_on_tip_shown):
		_tip.tip_shown.disconnect(_on_tip_shown)
	if _gm != null:
		_gm.reload_config()
		_gm.reset_clock()
		_gm.reset_stats()
		_gm.set_zone("grassland")
	if _tip != null:
		_tip.clear_queue()


# 缺实现时记为断言失败并跳过（SPEC-06 §2：RED 必须是断言失败，不是脚本崩）。
func _skip_unless_ready(method_names: Array = []) -> bool:
	if _hud == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not _hud.has_method(method_name):
			fail_test("HUD 应有 %s()（FR-C-07）" % method_name)
			return true
	return false


func _node(unique_name: String) -> Node:
	var found: Node = _hud.get_node_or_null(NodePath("%%%s" % unique_name))
	if found == null:
		fail_test("HUD 应有唯一名节点 %%%s" % unique_name)
	return found


func _on_tip_shown(tip_id: String) -> void:
	if tip_id == TIP_OXYGEN_LOW:
		_low_tip_count += 1


# 把氧气精确设到目标值（走公开 modify 接口，信号照常发）。
func _set_oxygen(target: float) -> void:
	_gm.modify_oxygen(target - _gm.oxygen)


# AC1：三条数值条实时跟随信号变化。
func test_bars_follow_stat_signals() -> void:
	if _skip_unless_ready():
		return
	var oxygen_bar: Node = _node("OxygenBar")
	var energy_bar: Node = _node("EnergyBar")
	var health_bar: Node = _node("HealthBar")
	if oxygen_bar == null or energy_bar == null or health_bar == null:
		return
	_gm.modify_oxygen(-25.0)
	_gm.modify_energy(-40.0)
	_gm.modify_health(-10.0)
	assert_almost_eq(float(oxygen_bar.value), 75.0, 0.001, "氧气条跟随 oxygen_changed")
	assert_almost_eq(float(energy_bar.value), 60.0, 0.001, "能量条跟随 energy_changed")
	assert_almost_eq(float(health_bar.value), 90.0, 0.001, "生命条跟随 health_changed")
	assert_almost_eq(float(oxygen_bar.max_value), float(_gm.oxygen_max), 0.001, "氧气条上限同步")


# AC1：数值条无轮询——hud.gd 逻辑行里不许出现 _process / _physics_process（注释除外）。
func test_bars_have_no_process_polling() -> void:
	var text: String = FileAccess.get_file_as_string(HUD_SCRIPT)
	assert_false(text.is_empty(), "应能读到 %s" % HUD_SCRIPT)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		assert_false(stripped.contains("_process"), "HUD 不许轮询三值（FR-C-07 AC1）：%s" % stripped)


# AC2：「已收集 N/16」随计数更新，格式串来自 ui_strings.json（NFR-04）。
func test_collected_counter_uses_ui_strings_format() -> void:
	if _skip_unless_ready(["set_collected"]):
		return
	var label: Node = _node("CollectedLabel")
	if label == null:
		return
	var template: String = str(Fixture.read_object("ui_strings.json").get(UI_COLLECTED, ""))
	assert_false(template.is_empty(), "ui_strings.json 应有 %s" % UI_COLLECTED)
	_hud.set_collected(3)
	assert_eq(str(label.text), template.format({"n": 3}), "计数 3 时按数据表格式显示")
	_hud.set_collected(16)
	assert_eq(str(label.text), template.format({"n": 16}), "计数 16 时按数据表格式显示")


# AC3：氧气低于阈值 → 闪烁标记 + 触发一次 sys_oxygen_low；持续低氧不重复；
# 回到安全值后再次低氧应重新提醒一次。
func test_low_oxygen_flashes_and_warns_once_per_episode() -> void:
	if _skip_unless_ready(["is_oxygen_warning"]):
		return
	var threshold: float = float(_gm.get_balance(BAL_LOW_OXYGEN, 30.0))
	_tip.tip_shown.connect(_on_tip_shown)
	_set_oxygen(threshold - 1.0)
	assert_true(_hud.is_oxygen_warning(), "氧气低于阈值应进入闪烁状态")
	assert_eq(_low_tip_count, 1, "跌破阈值应触发一次 %s" % TIP_OXYGEN_LOW)
	_gm.modify_oxygen(-5.0)
	assert_eq(_low_tip_count, 1, "持续低氧不重复触发字幕")
	_set_oxygen(threshold + 10.0)
	assert_false(_hud.is_oxygen_warning(), "氧气回升后退出闪烁状态")
	_tip.clear_queue() # 清掉上一条，让下一条能立即上台发 tip_shown
	_set_oxygen(threshold - 1.0)
	assert_eq(_low_tip_count, 2, "回到安全后再次低氧应重新提醒一次")


# AC3：阈值读自 balance.json——边界恰好等于阈值时不报警，低于才报警。
func test_low_oxygen_threshold_comes_from_balance() -> void:
	if _skip_unless_ready(["is_oxygen_warning"]):
		return
	var threshold: float = float(_gm.get_balance(BAL_LOW_OXYGEN, 30.0))
	_set_oxygen(threshold)
	assert_false(_hud.is_oxygen_warning(), "氧气恰好等于阈值不报警（边界为严格小于）")
	_set_oxygen(threshold - 0.5)
	assert_true(_hud.is_oxygen_warning(), "低于阈值 0.5 应报警")


# 时间/天数指示：随 day_started / night_started 信号更新（同样无轮询）。
func test_time_display_follows_daynight_signals() -> void:
	if _skip_unless_ready(["time_text"]):
		return
	var day_len: float = float(_gm.get_balance(BAL_DAY_DURATION, 360.0))
	var night_len: float = float(_gm.get_balance(BAL_NIGHT_DURATION, 180.0))
	var day_one: String = _hud.time_text()
	assert_true(day_one.contains("1"), "初始应显示第 1 天：%s" % day_one)
	_gm.tick(day_len) # 进入夜晚（天数不变）
	var night_text: String = _hud.time_text()
	assert_ne(night_text, day_one, "入夜后时间指示应变化")
	_gm.tick(night_len) # 进入第 2 天清晨
	assert_true(_hud.time_text().contains("2"), "跨夜后应显示第 2 天：%s" % _hud.time_text())


# NFR-04：逻辑代码里不许出现中文字面量（注释除外）。
func test_hud_script_has_no_hardcoded_chinese() -> void:
	var text: String = FileAccess.get_file_as_string(HUD_SCRIPT)
	assert_false(text.is_empty(), "应能读到 %s" % HUD_SCRIPT)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		assert_false(_has_cjk(stripped), "逻辑代码里不许硬编码中文（NFR-04）：%s" % stripped)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
