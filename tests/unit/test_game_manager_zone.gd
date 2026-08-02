# UT-C03 / FR-C-03：区域判定与分区氧气净速率、重复 set_zone 不发信号、首次进入触发一次区域字幕。
# 氧气净速率规则见 SPEC-02 §4.1「氧气净速率结算规则」：净变化 = 安全区回复 − 区域消耗。
extends GutTest

# SPEC-01 FR-C-03 AC2 的五区域净速率（正 = 回复，负 = 消耗）。
const EXPECTED_NET_RATE: Dictionary = {
	"grassland": 0.5,
	"camp": 0.5,
	"saltlake": 0.0,
	"mine": -2.0,
	"academy": 0.0,
}

# 足够播完任意一条字幕的秒数（最长 style 为 warning 5 秒）。
const TIP_DRAIN_SECONDS: float = 10.0

var gm: Node = null
var tip: Node = null


func before_each() -> void:
	var root: Node = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	tip = root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(gm, "GameManager autoload 必须存在")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if gm == null or tip == null:
		return
	# 先断言新契约方法存在：否则脚本错误会中断 before_each，让后续测试假绿。
	assert_true(gm.has_method("tick"), "GameManager 必须有 tick(delta)（SPEC-03 §2.2）")
	assert_true(gm.has_method("reset_clock"), "GameManager 必须有 reset_clock()")
	assert_true(tip.has_method("load_from"), "KnowledgeTip 必须有 load_from(rows) 数据注入口")
	if not (gm.has_method("reset_clock") and tip.has_method("load_from")):
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	gm.set_zone("grassland")


# AC1：current_zone() 返回当前区域 id，切换时发 zone_changed(zone_id)。
func test_current_zone_and_change_signal() -> void:
	watch_signals(gm)
	gm.set_zone("mine")
	assert_eq(gm.current_zone(), "mine", "current_zone 应返回刚设置的区域")
	assert_signal_emitted_with_parameters(gm, "zone_changed", ["mine"])


# AC1 + SPEC-03 §2.4：同一区域重复 set_zone 不发信号。
func test_repeated_set_zone_does_not_emit() -> void:
	gm.set_zone("camp")
	watch_signals(gm)
	gm.set_zone("camp")
	gm.set_zone("camp")
	assert_signal_emit_count(gm, "zone_changed", 0, "重复进入同一区域不应再发信号")


# 未知区域 id 被忽略，不改变当前区域也不发信号（防御性输入校验）。
func test_unknown_zone_is_ignored() -> void:
	gm.set_zone("camp")
	watch_signals(gm)
	gm.set_zone("atlantis")
	assert_eq(gm.current_zone(), "camp", "未知区域不应改变当前区域")
	assert_signal_emit_count(gm, "zone_changed", 0, "未知区域不应发信号")


# AC2：五区域氧气净速率与 balance 表一致（tick 注入 10 秒后看差值）。
func test_zone_oxygen_net_rates_match_balance() -> void:
	for zone_id: String in EXPECTED_NET_RATE:
		var expected: float = EXPECTED_NET_RATE[zone_id]
		gm.set_zone(zone_id)
		gm.reset_stats()
		# 从半满起算，避免满值 clamp 掩盖回复量。
		gm.modify_oxygen(-gm.oxygen_max * 0.5)
		var before: float = gm.oxygen
		gm.tick(10.0)
		assert_almost_eq(gm.oxygen - before, expected * 10.0, 0.001,
			"区域 %s 的 10 秒氧气净变化" % zone_id)


# AC2：速率必须真的读自 balance，改表即改行为（改数值不改代码）。
func test_mine_rate_follows_balance_table() -> void:
	var drain: float = float(gm.get_balance("stats.oxygen_drain.mine", -1.0))
	assert_almost_eq(drain, 2.0, 0.001, "balance 里的矿洞氧气消耗速率")
	var regen: float = float(gm.get_balance("stats.oxygen_regen_safe", -1.0))
	assert_almost_eq(regen, 1.0, 0.001, "balance 里的安全区氧气回复速率")


# 氧气满值时安全区不会溢出上限。
func test_safe_zone_does_not_exceed_max() -> void:
	gm.set_zone("grassland")
	gm.reset_stats()
	gm.tick(60.0)
	assert_almost_eq(gm.oxygen, gm.oxygen_max, 0.001, "满氧时安全区不应超过上限")


# AC3：首次进入某区域触发一次该区域横幅字幕，重复进入不再触发。
func test_first_entry_shows_zone_tip_once() -> void:
	# 用注入表替代 tips.json，测试不依赖 TP-02 的数据交付。
	tip.load_from([
		{"id": "zone_grass", "text": "空气的成分", "style": "banner", "duration": 4.0},
		{"id": "zone_mine", "text": "矿洞氧气稀薄", "style": "banner", "duration": 4.0},
	])
	watch_signals(tip)
	gm.set_zone("mine")
	assert_signal_emit_count(tip, "tip_shown", 1, "首次进入矿洞应触发一次区域字幕")
	assert_eq(tip.current_tip_id(), "zone_mine", "当前显示的应是矿洞字幕")
	assert_true(tip.is_shown("zone_mine"), "矿洞字幕应记为已展示")
	# 队列是串行的：先把矿洞那条播完，草原那条才会上台发 tip_shown。
	tip.advance(TIP_DRAIN_SECONDS)
	gm.set_zone("grassland")
	assert_signal_emit_count(tip, "tip_shown", 2, "首次进入草原应触发草原字幕")
	tip.advance(TIP_DRAIN_SECONDS)
	gm.set_zone("mine")
	assert_signal_emit_count(tip, "tip_shown", 2, "重回矿洞不应再发矿洞字幕")
	assert_eq(tip.current_tip_id(), "", "重回矿洞不应有字幕在显示")


# A4 回归（FR-C-03 AC3）：全新会话的第一次 set_zone("grassland") 必须发 zone_changed 并播出生区横幅。
# 此前 _zone 初值即 "grassland"，world._reset_run 的首次定位被同区去重吞掉，出生区横幅永不播。
func test_first_zone_assignment_emits_signal_and_tip() -> void:
	tip.load_from([
		{"id": "zone_grass", "text": "空气的成分", "style": "banner", "duration": 4.0},
	])
	var script: GDScript = load("res://scripts/autoload/game_manager.gd") as GDScript
	assert_not_null(script, "game_manager.gd 应可加载")
	if script == null:
		return
	# 另起一个全新实例模拟开局（共享 autoload 的 _zone 已被其他测试写过，无法代表首局）。
	var fresh: Node = script.new()
	add_child_autofree(fresh)
	watch_signals(fresh)
	watch_signals(tip)
	fresh.set_zone("grassland")
	assert_signal_emitted_with_parameters(fresh, "zone_changed", ["grassland"])
	assert_eq(tip.current_tip_id(), "zone_grass", "首次进入草原应立即播出 zone_grass 横幅（A4）")
	# 同区去重仍然成立：紧接着重复 set_zone 不再发信号。
	fresh.set_zone("grassland")
	assert_signal_emit_count(fresh, "zone_changed", 1, "重复 set_zone 同区不应再发信号")
	tip.reload() # 收尾：恢复真实字幕表，避免污染后续测试文件共享的 KnowledgeTip


# 区域字幕 id 必须来自映射表，逻辑代码里不许出现中文字面量（NFR-04）。
func test_zone_tip_ids_are_data_driven() -> void:
	for zone_id: String in gm.ZONE_IDS:
		assert_true(gm.ZONE_TIP_IDS.has(zone_id),
			"区域 %s 必须在 ZONE_TIP_IDS 里有对应字幕 id" % zone_id)
