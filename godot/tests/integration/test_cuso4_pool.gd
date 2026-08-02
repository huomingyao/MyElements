# IT-G16 / FR-G-16：CuSO₄ 溶液池——矿洞蓝色伤害区（Area2D 被动伤害，无 E 交互）。
# AC1 浸泡期间按 damage.cuso4_pool_per_second（5/s）扣血、离开即停；
# AC2 首次接近触发一次 warn_cuso4 警示字幕，重复接近不再触发；
# AC3 池内致死走 FR-C-06 正常死亡流程（GameManager.player_died）。
extends GutTest

const POOL_SCENE_PATH: String = "res://scenes/gameplay/cuso4_pool.tscn"
const POOL_SCRIPT_PATH: String = "res://scenes/gameplay/cuso4_pool.gd"
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
		tip.reload() # 复位字幕展示记录（warn_cuso4 的一次性判定）
	if gm != null:
		gm.reset_stats()
		gm.reset_clock()
		gm.set_zone("mine") # 池在矿洞；区域对伤害无影响，仅贴近真实场景
	if not ResourceLoader.exists(POOL_SCENE_PATH):
		fail_test("尚未实现 %s（FR-G-16）" % POOL_SCENE_PATH)


func _spawn_pool(at: Vector2) -> Area2D:
	if not ResourceLoader.exists(POOL_SCENE_PATH):
		return null
	var pool: Area2D = (load(POOL_SCENE_PATH) as PackedScene).instantiate() as Area2D
	pool.position = at
	add_child_autofree(pool)
	return pool


# 用真实玩家场景做碰撞对象；关掉它的 _physics_process 防止重力把它带走。
func _spawn_player(at: Vector2) -> CharacterBody2D:
	var player: CharacterBody2D = (load(PLAYER_PATH) as PackedScene).instantiate() as CharacterBody2D
	player.position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


# AC1：浸泡伤害读 balance 表，改数值不改代码。
func test_pool_damage_reads_balance() -> void:
	var pool: Area2D = _spawn_pool(Vector2.ZERO)
	if pool == null:
		return
	if not pool.has_method("damage_per_second"):
		fail_test("溶液池应有 damage_per_second()（FR-G-16 AC1）")
		return
	var dps: float = float(gm.get_balance("damage.cuso4_pool_per_second", -1.0))
	assert_almost_eq(dps, 5.0, 0.001, "balance 交叉验证：5/s")
	assert_almost_eq(pool.damage_per_second(), dps, 0.001, "浸泡伤害应读自 balance")


# AC1：浸泡期间按 5/s 扣血（时间注入，断言精确值）。
func test_pool_tick_drains_health_proportionally() -> void:
	var pool: Area2D = _spawn_pool(Vector2.ZERO)
	if pool == null:
		return
	if not pool.has_method("apply_pool_tick"):
		fail_test("溶液池应有 apply_pool_tick(delta)（时间可注入，SPEC-06 §3）")
		return
	var dps: float = float(gm.get_balance("damage.cuso4_pool_per_second", -1.0))
	var before: float = gm.health
	pool.apply_pool_tick(1.0)
	assert_almost_eq(gm.health, before - dps, 0.001, "浸泡 1 秒应掉血 5")
	pool.apply_pool_tick(0.5)
	assert_almost_eq(gm.health, before - dps - dps * 0.5, 0.001, "伤害应按时间成比例")


# AC1：真实物理重叠——站在池内持续掉血，离开即停。
func test_real_overlap_drains_and_stops_on_exit() -> void:
	var pool: Area2D = _spawn_pool(Vector2.ZERO)
	if pool == null:
		return
	var player: CharacterBody2D = _spawn_player(Vector2.ZERO)
	pool.target_player = player
	await wait_physics_frames(15)
	assert_lt(gm.health, gm.health_max, "真实浸泡应持续掉血")
	assert_gt(gm.health, gm.health_max - 5.0, "0.25 秒内掉血不应超过一秒的量")
	# 离开池子：掉血立即停止。
	player.position = Vector2(600.0, 0.0)
	await wait_physics_frames(5)
	var health_after_exit: float = gm.health
	await wait_physics_frames(10)
	assert_almost_eq(gm.health, health_after_exit, 0.0001, "离开池内后掉血应立即停止")


# AC2：首次接近（警示半径内、池外）触发一次 warn_cuso4。
func test_first_approach_triggers_warn_cuso4_once() -> void:
	var pool: Area2D = _spawn_pool(Vector2.ZERO)
	if pool == null:
		return
	var player: CharacterBody2D = _spawn_player(Vector2(80.0, 0.0))
	pool.target_player = player
	watch_signals(tip)
	await wait_physics_frames(5)
	assert_true(tip.is_shown("warn_cuso4"), "接近时应触发 warn_cuso4")
	assert_signal_emit_count(tip, "tip_shown", 1, "同一座池接近只应触发一次")


# AC2：两座池先后接近，warn_cuso4 全局限一次（show_once 语义）。
func test_second_pool_does_not_repeat_warning() -> void:
	var pool_a: Area2D = _spawn_pool(Vector2.ZERO)
	var pool_b: Area2D = _spawn_pool(Vector2(30.0, 0.0))
	if pool_a == null or pool_b == null:
		return
	var player: CharacterBody2D = _spawn_player(Vector2(80.0, 0.0))
	pool_a.target_player = player
	pool_b.target_player = player
	watch_signals(tip)
	await wait_physics_frames(5)
	assert_true(tip.is_shown("warn_cuso4"), "首次接近应触发 warn_cuso4")
	assert_signal_emit_count(tip, "tip_shown", 1, "第二座池不应重复触发 warn_cuso4")


# AC2 边界：距离够远时不触发警示。
func test_distant_player_triggers_no_warning() -> void:
	var pool: Area2D = _spawn_pool(Vector2.ZERO)
	if pool == null:
		return
	var player: CharacterBody2D = _spawn_player(Vector2(400.0, 0.0))
	pool.target_player = player
	await wait_physics_frames(3)
	assert_false(tip.is_shown("warn_cuso4"), "远处玩家不应触发 warn_cuso4")


# AC3：池内致死触发 player_died，走 FR-C-06 正常死亡流程（不另起死亡通道）。
func test_death_in_pool_emits_player_died() -> void:
	var pool: Area2D = _spawn_pool(Vector2.ZERO)
	if pool == null:
		return
	watch_signals(gm)
	var dps: float = float(gm.get_balance("damage.cuso4_pool_per_second", -1.0))
	gm.modify_health(-(gm.health - dps)) # 压到一击致死的血量
	pool.apply_pool_tick(1.0)
	assert_almost_eq(gm.health, 0.0, 0.001, "池内伤害应能把生命扣到 0")
	assert_signal_emit_count(gm, "player_died", 1, "致死应恰好发一次 player_died（FR-C-06）")
	pool.apply_pool_tick(1.0)
	assert_signal_emit_count(gm, "player_died", 1, "重复扣血不应重复发 player_died（SPEC-03 §2.4）")


# 逻辑代码不许出现中文文案（NFR-04；push_warning/push_error/print 诊断日志除外）。
func test_source_has_no_chinese_literals() -> void:
	if not ResourceLoader.exists(POOL_SCRIPT_PATH):
		fail_test("尚未实现 %s（FR-G-16）" % POOL_SCRIPT_PATH)
		return
	var file: FileAccess = FileAccess.open(POOL_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "cuso4_pool.gd 应可读")
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
