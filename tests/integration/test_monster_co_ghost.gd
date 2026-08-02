# IT-G10 / FR-G-10：CO 幽灵——矿洞全天 + 草原夜晚生成；匀速飘向玩家；
# 接触按 8/s 掉血；活性炭口罩免疫；首次接近触发一次 warn_co 警示字幕。
extends GutTest

const GHOST_SCENE_PATH: String = "res://scenes/gameplay/monster_co_ghost.tscn"
const GHOST_SCRIPT_PATH: String = "res://scenes/gameplay/monster_co_ghost.gd"
const PLAYER_PATH: String = "res://scenes/player/player.tscn"

var gm: Node = null
var tip: Node = null


func before_each() -> void:
	var root: Window = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	assert_not_null(gm, "GameManager autoload 必须存在")
	tip = root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if tip != null:
		tip.reload() # 复位字幕展示记录（warn_co 的一次性判定）
	if gm != null:
		gm.reset_stats()
		gm.reset_clock()
	if not ResourceLoader.exists(GHOST_SCENE_PATH):
		fail_test("尚未实现 %s（FR-G-10 / TP-09）" % GHOST_SCENE_PATH)


func _spawn_ghost(at: Vector2) -> Node2D:
	if not ResourceLoader.exists(GHOST_SCENE_PATH):
		return null
	var ghost: Node2D = (load(GHOST_SCENE_PATH) as PackedScene).instantiate() as Node2D
	ghost.position = at
	add_child_autofree(ghost)
	return ghost


# 用真实玩家场景做碰撞对象；关掉它的 _physics_process 防止重力把它带走。
func _spawn_player(at: Vector2) -> CharacterBody2D:
	var player: CharacterBody2D = (load(PLAYER_PATH) as PackedScene).instantiate() as CharacterBody2D
	player.position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


# AC1：矿洞任意时间、草原仅夜晚；其余区域不出现。
func test_spawn_rule_mine_anytime_grassland_night_only() -> void:
	if not ResourceLoader.exists(GHOST_SCRIPT_PATH):
		fail_test("尚未实现 %s（FR-G-10 / TP-09）" % GHOST_SCRIPT_PATH)
		return
	var script: GDScript = load(GHOST_SCRIPT_PATH) as GDScript
	assert_true(script.can_spawn("mine", false), "矿洞白天应生成")
	assert_true(script.can_spawn("mine", true), "矿洞夜晚应生成")
	assert_false(script.can_spawn("grassland", false), "草原白天不应生成")
	assert_true(script.can_spawn("grassland", true), "草原夜晚应生成")
	assert_false(script.can_spawn("saltlake", true), "盐湖是安全区")
	assert_false(script.can_spawn("academy", true), "学院内怪物不进入")
	assert_false(script.can_spawn("camp", false), "营地白天不应生成")


# 行为：匀速朝玩家飘动，速度读 balance（最简 AI，不做寻路）。
func test_drifts_toward_player_at_balance_speed() -> void:
	var ghost: Node2D = _spawn_ghost(Vector2(100.0, 0.0))
	if ghost == null:
		return
	var speed: float = float(gm.get_balance("monsters.co_ghost_speed", -1.0))
	assert_almost_eq(ghost.drift_speed(), speed, 0.001, "漂移速度应读自 balance")
	assert_almost_eq(speed, 28.0, 0.001, "balance 交叉验证：28 px/s")
	ghost.drift_step(1.0, Vector2.ZERO)
	assert_almost_eq(ghost.global_position.x, 100.0 - speed, 0.01, "应向玩家方向漂移一个速度步")
	assert_almost_eq(ghost.global_position.y, 0.0, 0.01, "直线漂移不应偏移")


# AC2：接触玩家时生命按 8/s 下降（时间注入 1 秒，断言精确值）。
func test_contact_damage_8_per_second() -> void:
	var ghost: Node2D = _spawn_ghost(Vector2.ZERO)
	if ghost == null:
		return
	var dps: float = float(gm.get_balance("damage.co_ghost_per_second", -1.0))
	assert_almost_eq(ghost.contact_damage_per_second([]), dps, 0.001, "接触伤害应读自 balance")
	assert_almost_eq(dps, 8.0, 0.001, "balance 交叉验证：8/s")
	var before: float = gm.health
	ghost.apply_contact_tick(1.0, [])
	assert_almost_eq(gm.health, before - dps, 0.001, "接触 1 秒应掉血 8")
	ghost.apply_contact_tick(0.5, [])
	assert_almost_eq(gm.health, before - dps - dps * 0.5, 0.001, "伤害应按时间成比例")


# AC2：装备活性炭口罩时伤害为 0。
func test_carbon_mask_grants_full_immunity() -> void:
	var ghost: Node2D = _spawn_ghost(Vector2.ZERO)
	if ghost == null:
		return
	assert_eq(ghost.contact_damage_per_second(["carbon_mask"]), 0.0, "戴口罩时伤害应为 0")
	var before: float = gm.health
	ghost.apply_contact_tick(1.0, ["carbon_mask"])
	assert_almost_eq(gm.health, before, 0.001, "戴口罩接触不应掉血")


# 真实物理重叠：玩家站在幽灵碰撞区内，生命随真实帧流逝下降。
func test_real_overlap_drains_health() -> void:
	var ghost: Node2D = _spawn_ghost(Vector2.ZERO)
	if ghost == null:
		return
	var player: CharacterBody2D = _spawn_player(Vector2(5.0, 0.0))
	ghost.target_player = player
	await wait_physics_frames(15)
	assert_lt(gm.health, gm.health_max, "真实接触应持续掉血")
	assert_gt(gm.health, gm.health_max - 8.0, "0.25 秒内掉血不应超过一秒的量")


# AC3：首次接近触发一次 warn_co 警示字幕。
func test_first_approach_triggers_warn_co_once() -> void:
	var ghost: Node2D = _spawn_ghost(Vector2.ZERO)
	if ghost == null:
		return
	var player: CharacterBody2D = _spawn_player(Vector2(40.0, 0.0))
	ghost.target_player = player
	watch_signals(tip)
	await wait_physics_frames(5)
	assert_true(tip.is_shown("warn_co"), "接近时应触发 warn_co")
	assert_signal_emit_count(tip, "tip_shown", 1, "同一只幽灵接近只应触发一次")


# AC3：两只幽灵先后接近，warn_co 全局限一次（show_once 语义）。
func test_second_ghost_does_not_repeat_warning() -> void:
	var ghost_a: Node2D = _spawn_ghost(Vector2.ZERO)
	var ghost_b: Node2D = _spawn_ghost(Vector2(20.0, 0.0))
	if ghost_a == null or ghost_b == null:
		return
	var player: CharacterBody2D = _spawn_player(Vector2(10.0, 0.0))
	ghost_a.target_player = player
	ghost_b.target_player = player
	watch_signals(tip)
	await wait_physics_frames(5)
	assert_true(tip.is_shown("warn_co"), "首次接近应触发 warn_co")
	assert_signal_emit_count(tip, "tip_shown", 1, "第二只幽灵不应重复触发 warn_co")


# AC3 边界：距离够远时不触发警示。
func test_distant_player_triggers_no_warning() -> void:
	var ghost: Node2D = _spawn_ghost(Vector2.ZERO)
	if ghost == null:
		return
	var player: CharacterBody2D = _spawn_player(Vector2(400.0, 0.0))
	ghost.target_player = player
	await wait_physics_frames(3)
	assert_false(tip.is_shown("warn_co"), "远处玩家不应触发 warn_co")


# 逻辑代码不许出现中文文案（NFR-04；push_warning/push_error/print 诊断日志除外）。
func test_source_has_no_chinese_literals() -> void:
	if not ResourceLoader.exists(GHOST_SCRIPT_PATH):
		return
	var file: FileAccess = FileAccess.open(GHOST_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "monster_co_ghost.gd 应可读")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("#"):
			continue
		if line.contains("push_warning(") or line.contains("push_error(") or line.contains("print("):
			continue
		var code: String = line
		var comment_at: int = code.find("#")
		if comment_at >= 0:
			code = code.substr(0, comment_at)
		for i: int in code.length():
			var c: int = code.unicode_at(i)
			assert_false(c >= 0x4E00 and c <= 0x9FFF, "逻辑代码出现中文字面量：%s" % line)
