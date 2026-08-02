# UT-C04 / FR-C-04：昼夜时钟由 tick(delta) 推进——120s 进夜、再 60s 回昼；
# day_started/night_started 各一次；day_count 清晨递增；清晨发 resources_respawned；时长读自 balance。
extends GutTest

var gm: Node = null
var day_duration: float = 0.0
var night_duration: float = 0.0


func before_each() -> void:
	gm = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	assert_not_null(gm, "GameManager autoload 必须存在")
	if gm == null:
		return
	# 先断言新契约方法存在：否则脚本错误会中断 before_each，让后续测试假绿。
	assert_true(gm.has_method("tick"), "GameManager 必须有 tick(delta)（SPEC-03 §2.2）")
	assert_true(gm.has_method("reset_clock"), "GameManager 必须有 reset_clock()")
	if not gm.has_method("reset_clock"):
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	gm.set_zone("grassland")
	day_duration = float(gm.get_balance("daynight.day_duration", -1.0))
	night_duration = float(gm.get_balance("daynight.night_duration", -1.0))


# AC2：白天/夜晚时长读自 balance.json。
func test_durations_come_from_balance() -> void:
	assert_almost_eq(day_duration, 120.0, 0.001, "白天时长应为 balance 里的 120 秒")
	assert_almost_eq(night_duration, 60.0, 0.001, "夜晚时长应为 balance 里的 60 秒")


func test_starts_in_daytime() -> void:
	assert_false(gm.is_night(), "初始应为白天")
	assert_eq(gm.day_count, 1, "初始天数为 1")


# AC1：推进 day_duration 后进夜，且 night_started 只发一次。
func test_advancing_day_duration_enters_night() -> void:
	watch_signals(gm)
	gm.tick(day_duration)
	assert_true(gm.is_night(), "推进整个白天后应进入夜晚")
	assert_signal_emit_count(gm, "night_started", 1, "night_started 应只发一次")
	assert_signal_emitted_with_parameters(gm, "night_started", [1])


# AC1：白天未走完不得进夜（边界前一刻）。
func test_night_not_entered_before_day_ends() -> void:
	gm.tick(day_duration - 1.0)
	assert_false(gm.is_night(), "白天还剩 1 秒时不应进夜")


# AC1 + AC4：再推进 night_duration 回到白天，天数 +1，清晨发 resources_respawned。
func test_advancing_night_returns_to_morning() -> void:
	gm.tick(day_duration)
	watch_signals(gm)
	gm.tick(night_duration)
	assert_false(gm.is_night(), "推进整个夜晚后应回到白天")
	assert_eq(gm.day_count, 2, "清晨天数应 +1")
	assert_signal_emit_count(gm, "day_started", 1, "day_started 应只发一次")
	assert_signal_emitted_with_parameters(gm, "day_started", [2])
	assert_signal_emit_count(gm, "resources_respawned", 1, "清晨应发一次资源刷新")


# 可测性约束（SPEC-06 §3）：一次注入 600 秒也必须正确结算，不许丢周期。
func test_single_large_delta_crosses_full_cycle() -> void:
	watch_signals(gm)
	gm.tick(day_duration + night_duration)
	assert_false(gm.is_night(), "整整一个周期后应回到白天")
	assert_eq(gm.day_count, 2, "跨完整周期天数应 +1")
	assert_signal_emit_count(gm, "night_started", 1, "大 delta 不应丢掉入夜信号")
	assert_signal_emit_count(gm, "day_started", 1, "大 delta 不应丢掉清晨信号")


# 连续两个周期：信号次数与天数都要线性递增，不许累积漂移。
func test_two_full_cycles_advance_two_days() -> void:
	watch_signals(gm)
	gm.tick((day_duration + night_duration) * 2.0)
	assert_eq(gm.day_count, 3, "两个完整周期后应是第 3 天")
	assert_signal_emit_count(gm, "night_started", 2, "两个周期应入夜两次")
	assert_signal_emit_count(gm, "day_started", 2, "两个周期应清晨两次")


# 非法 delta 不推进时钟也不崩溃（防御性输入校验）。
func test_non_positive_delta_is_ignored() -> void:
	var clock_before: float = gm.time_of_day
	gm.tick(0.0)
	gm.tick(-10.0)
	assert_almost_eq(gm.time_of_day, clock_before, 0.001, "非正 delta 不应推进时钟")


# FR-C-05 前置：sleep_until_morning 从夜晚直接跳到次日清晨。
func test_sleep_skips_night_to_next_morning() -> void:
	gm.tick(day_duration)
	assert_true(gm.is_night(), "前置条件：当前是夜晚")
	gm.modify_health(-20.0)
	watch_signals(gm)
	gm.sleep_until_morning()
	assert_false(gm.is_night(), "睡觉后应是白天")
	assert_eq(gm.day_count, 2, "睡觉后天数 +1")
	assert_almost_eq(gm.health, gm.health_max, 0.001, "睡觉后生命回满")
	assert_signal_emit_count(gm, "resources_respawned", 1, "睡觉后应刷新采集物")


# 睡觉后时钟归零，不能残留夜晚进度导致刚起床又天黑。
func test_sleep_resets_clock_to_morning() -> void:
	gm.tick(day_duration + 60.0)
	gm.sleep_until_morning()
	assert_almost_eq(gm.time_of_day, 0.0, 0.001, "睡觉后时钟应回到清晨 0 秒")
