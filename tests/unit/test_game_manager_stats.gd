# UT-C02 / FR-C-02：三值上限与初值、三个信号的参数、氧气归零后按表掉血、
# 能量归零速度倍率、生命归零只发一次 player_died。速率一律取自 balance.json（AC4）。
extends GutTest

const SOURCE_PATH: String = "res://scripts/autoload/game_manager.gd"
const LOGIC_MARKER: String = "# ==== 逻辑区"

var gm: Node = null


func before_each() -> void:
	gm = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	assert_not_null(gm, "GameManager autoload 必须存在")
	if gm == null:
		return
	# 先断言新契约方法存在：否则 GDScript 会抛脚本错误中断 before_each，
	# 让后续测试在未复位的状态下假绿（SPEC-06 §2：RED 必须是断言失败）。
	assert_true(gm.has_method("tick"), "GameManager 必须有 tick(delta)（SPEC-03 §2.2）")
	assert_true(gm.has_method("reset_clock"), "GameManager 必须有 reset_clock()")
	if not gm.has_method("reset_clock"):
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	gm.set_zone("grassland")


# AC1：三值上限均为 100，初值等于上限，且可被单测直接读写。
func test_stat_caps_and_initial_values() -> void:
	assert_almost_eq(gm.oxygen_max, 100.0, 0.001, "氧气上限")
	assert_almost_eq(gm.energy_max, 100.0, 0.001, "能量上限")
	assert_almost_eq(gm.health_max, 100.0, 0.001, "生命上限")
	assert_almost_eq(gm.oxygen, gm.oxygen_max, 0.001, "氧气初值应等于上限")
	assert_almost_eq(gm.energy, gm.energy_max, 0.001, "能量初值应等于上限")
	assert_almost_eq(gm.health, gm.health_max, 0.001, "生命初值应等于上限")


# AC2：三个信号参数为 (current, max)。
func test_stat_signals_carry_current_and_max() -> void:
	watch_signals(gm)
	gm.modify_oxygen(-10.0)
	gm.modify_energy(-20.0)
	gm.modify_health(-30.0)
	assert_signal_emitted_with_parameters(gm, "oxygen_changed", [90.0, 100.0])
	assert_signal_emitted_with_parameters(gm, "energy_changed", [80.0, 100.0])
	assert_signal_emitted_with_parameters(gm, "health_changed", [70.0, 100.0])


func test_stats_clamp_to_zero_and_max() -> void:
	gm.modify_oxygen(-999.0)
	assert_almost_eq(gm.oxygen, 0.0, 0.001, "氧气不得为负")
	gm.modify_oxygen(999.0)
	assert_almost_eq(gm.oxygen, gm.oxygen_max, 0.001, "氧气不得超过上限")


# AC3：氧气归零后生命按 balance 的 oxygen_zero_health_drain(5/s) 持续下降。
func test_zero_oxygen_drains_health_at_table_rate() -> void:
	var rate: float = float(gm.get_balance("stats.oxygen_zero_health_drain", -1.0))
	assert_almost_eq(rate, 5.0, 0.001, "balance 里的缺氧掉血速率")
	gm.set_zone("mine")
	gm.modify_oxygen(-gm.oxygen_max)
	assert_almost_eq(gm.oxygen, 0.0, 0.001, "前置条件：氧气已归零")
	var health_before: float = gm.health
	gm.tick(2.0)
	assert_almost_eq(gm.health, health_before - rate * 2.0, 0.001, "缺氧 2 秒应掉 2×速率 的血")


# AC3：氧气未归零时不因缺氧掉血。
func test_health_not_drained_while_oxygen_remains() -> void:
	gm.set_zone("mine")
	var health_before: float = gm.health
	gm.tick(2.0)
	assert_almost_eq(gm.health, health_before, 0.001, "有氧气时不应掉血")


# AC3：能量归零后移动速度倍率变为 balance 的 low_energy_speed_multiplier(0.5)。
func test_zero_energy_halves_move_speed() -> void:
	var expected: float = float(gm.get_balance("stats.low_energy_speed_multiplier", -1.0))
	assert_almost_eq(expected, 0.5, 0.001, "balance 里的低能量速度倍率")
	assert_almost_eq(gm.move_speed_multiplier(), 1.0, 0.001, "能量充足时倍率为 1")
	gm.modify_energy(-gm.energy_max)
	assert_almost_eq(gm.move_speed_multiplier(), expected, 0.001, "能量归零时倍率应取自 balance")


# AC3 + SPEC-03 §2.4：同帧多次伤害只发一次 player_died。
func test_death_signal_emitted_once_on_repeated_damage() -> void:
	watch_signals(gm)
	gm.modify_health(-gm.health_max)
	gm.modify_health(-10.0)
	gm.modify_health(-10.0)
	assert_signal_emit_count(gm, "player_died", 1, "生命归零后 player_died 只能发一次")


# 复活后死亡去重标记必须复位，否则第二次死亡不再发信号。
func test_death_signal_rearms_after_respawn() -> void:
	gm.modify_health(-gm.health_max)
	gm.respawn_player()
	watch_signals(gm)
	gm.modify_health(-gm.health_max)
	assert_signal_emit_count(gm, "player_died", 1, "复活后再次死亡应重新发信号")


# 能量按 balance 的 energy_drain(0.3/s) 全区一致消耗。
func test_energy_drains_at_table_rate_in_every_zone() -> void:
	var rate: float = float(gm.get_balance("stats.energy_drain", -1.0))
	assert_almost_eq(rate, 0.3, 0.001, "balance 里的能量消耗速率")
	for zone_id: String in gm.ZONE_IDS:
		gm.reset_stats()
		gm.set_zone(zone_id)
		gm.tick(10.0)
		assert_almost_eq(gm.energy, gm.energy_max - rate * 10.0, 0.001,
			"区域 %s 的能量消耗应与其他区域一致" % zone_id)


# AC4：逻辑区不许出现散落的裸速率数值。
# 常量区（CLAUDE.md 允许的「autoload 顶部常量区」）位于哨兵注释之前，只检查哨兵之后的逻辑区。
func test_logic_section_has_no_hardcoded_rates() -> void:
	var file: FileAccess = FileAccess.open(SOURCE_PATH, FileAccess.READ)
	assert_not_null(file, "应能读到 game_manager.gd 源码")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()
	assert_true(source.contains(LOGIC_MARKER),
		"源码必须有哨兵注释 %s 分隔常量区与逻辑区" % LOGIC_MARKER)
	var marker_at: int = source.find(LOGIC_MARKER)
	if marker_at < 0:
		return
	var logic: String = source.substr(marker_at)
	# 这些速率必须来自 balance.json；出现在逻辑区说明写死了。
	for forbidden: String in ["5.0", "0.3", "2.0", "0.35", "360.0", "180.0", "0.5"]:
		assert_false(logic.contains(forbidden),
			"逻辑区不应出现裸数值 %s（应走 get_balance 或常量区）" % forbidden)
