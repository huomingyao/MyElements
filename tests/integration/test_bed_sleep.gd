# IT-C05 / FR-C-05：床交互 → 跳到次日清晨，生命回满，资源刷新（resources_respawned），
# 触发字幕 sys_sleep。床只实现 SPEC-03 §5 三方法约定。
extends GutTest

const BED_SCENE: String = "res://scenes/gameplay/facility_bed.tscn"

var gm: Node = null
var tip: Node = null


class FakePlayer:
	extends Node2D
	var inventory: RefCounted = null


func before_each() -> void:
	var root: Window = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	tip = root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(gm, "GameManager autoload 必须存在")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if gm == null or tip == null:
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	gm.set_zone("camp")
	tip.reload()


func _make_player() -> FakePlayer:
	var player := FakePlayer.new()
	add_child_autofree(player)
	return player


func _spawn_bed() -> Node:
	if not ResourceLoader.exists(BED_SCENE):
		fail_test("尚未实现 %s（FR-C-05 / TP-10）" % BED_SCENE)
		return null
	var bed: Node = (load(BED_SCENE) as PackedScene).instantiate()
	add_child_autofree(bed)
	return bed


func _enter_night() -> void:
	var day_duration: float = float(gm.get_balance("daynight.day_duration", 360.0))
	gm.tick(day_duration)


# 睡觉是跳夜：白天不可交互（AC1 的前提是「夜晚在床上交互」）。
func test_bed_only_interactable_at_night() -> void:
	var bed: Node = _spawn_bed()
	if bed == null:
		return
	assert_false(bool(bed.can_interact()), "白天床不应可交互")
	_enter_night()
	assert_true(gm.is_night(), "推进一个白天后应进夜")
	assert_true(bool(bed.can_interact()), "夜晚床应可交互")


# AC1：夜晚交互后 is_night() 变 false 且 day_count +1。
# AC2：生命回到上限；触发字幕 sys_sleep。
# AC3 机制面：清晨发出 resources_respawned（采集物重新可拾取由该信号驱动，见报告）。
func test_sleep_skips_night_restores_health_and_respawns() -> void:
	var bed: Node = _spawn_bed()
	if bed == null:
		return
	_enter_night()
	gm.health = 30.0
	watch_signals(gm)
	bed.interact(_make_player())
	assert_false(gm.is_night(), "睡觉后应回到白天")
	assert_eq(gm.day_count, 2, "睡觉后天数应 +1")
	assert_almost_eq(gm.health, gm.health_max, 0.001, "睡觉后生命应回满")
	assert_true(tip.is_shown("sys_sleep"), "睡觉应触发字幕 sys_sleep")
	assert_signal_emit_count(gm, "resources_respawned", 1, "清晨应发一次 resources_respawned")
	assert_signal_emitted(gm, "day_started", "清晨应发 day_started")


# 白天直接调 interact 是非法调用：状态不许变化（防御性，交互系统外的误触不破坏状态）。
func test_interact_in_daytime_does_nothing() -> void:
	var bed: Node = _spawn_bed()
	if bed == null:
		return
	bed.interact(_make_player())
	assert_false(gm.is_night(), "白天不应进夜")
	assert_eq(gm.day_count, 1, "白天 interact 不应改变天数")
	assert_false(tip.is_shown("sys_sleep"), "白天 interact 不应触发睡觉字幕")
