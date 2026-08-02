# IT-G11 / FR-G-11：酸雾怪——仅夜晚在营地外围刷 2~3 只、白天清除；
# 直线冲撞命中 -10（单次）；中和喷雾喷中即销毁并显示 sys_spray 字幕。
extends GutTest

const MIST_SCENE_PATH: String = "res://scenes/gameplay/monster_acid_mist.tscn"
const MIST_SCRIPT_PATH: String = "res://scenes/gameplay/monster_acid_mist.gd"
const SPAWNER_SCRIPT_PATH: String = "res://scenes/gameplay/monster_spawner.gd"
const PLAYER_PATH: String = "res://scenes/player/player.tscn"
const ITEM_EFFECTS_PATH: String = "res://scripts/gameplay/item_effects.gd"
const INVENTORY_PATH: String = "res://scripts/gameplay/inventory.gd"

var gm: Node = null
var tip: Node = null


func before_each() -> void:
	var root: Window = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	assert_not_null(gm, "GameManager autoload 必须存在")
	tip = root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if tip != null:
		tip.reload()
	if gm != null:
		gm.reset_stats()
		gm.reset_clock()
	for path: String in [MIST_SCENE_PATH, MIST_SCRIPT_PATH, SPAWNER_SCRIPT_PATH]:
		if not ResourceLoader.exists(path):
			fail_test("尚未实现 %s（FR-G-11 / TP-09）" % path)


func _implemented() -> bool:
	return ResourceLoader.exists(MIST_SCENE_PATH) \
		and ResourceLoader.exists(MIST_SCRIPT_PATH) \
		and ResourceLoader.exists(SPAWNER_SCRIPT_PATH)


func _spawn_mist(at: Vector2) -> Node2D:
	var mist: Node2D = (load(MIST_SCENE_PATH) as PackedScene).instantiate() as Node2D
	mist.position = at
	add_child_autofree(mist)
	return mist


func _spawn_spawner() -> Node2D:
	var spawner: Node2D = (load(SPAWNER_SCRIPT_PATH) as GDScript).new() as Node2D
	add_child_autofree(spawner)
	return spawner


# 用真实玩家场景做碰撞对象；关掉它的 _physics_process 防止重力把它带走。
func _spawn_player(at: Vector2) -> CharacterBody2D:
	var player: CharacterBody2D = (load(PLAYER_PATH) as PackedScene).instantiate() as CharacterBody2D
	player.position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


# AC1：刷新数量在 balance 的 [2, 3] 区间；多只时位置在营地外围的环上。
func test_spawn_count_within_balance_range() -> void:
	if not _implemented():
		return
	var lo: int = int(gm.get_balance("monsters.acid_mist_night_count_min", -1))
	var hi: int = int(gm.get_balance("monsters.acid_mist_night_count_max", -1))
	assert_eq(lo, 2, "balance 交叉验证：下限 2")
	assert_eq(hi, 3, "balance 交叉验证：上限 3")
	var spawner: Node2D = _spawn_spawner()
	spawner.camp_center = Vector2(500.0, 300.0)
	for seed: int in [1, 7, 42]:
		spawner.rng.seed = seed
		var mists: Array = spawner.spawn_night_mists()
		assert_true(mists.size() >= lo and mists.size() <= hi,
			"刷新数量应在 %d~%d，实际 %d" % [lo, hi, mists.size()])
		assert_eq(spawner.alive_count(), mists.size(), "存活计数应与刷出数一致")
		for mist: Node2D in mists:
			assert_almost_eq(spawner.camp_center.distance_to(mist.global_position),
				spawner.SPAWN_RADIUS, 0.5, "酸雾怪应刷在营地外围的环上")


# AC1：仅夜晚刷新——night_started 信号触发生成，day_started 信号全部清除。
func test_night_signal_spawns_and_day_signal_clears() -> void:
	if not _implemented():
		return
	var spawner: Node2D = _spawn_spawner()
	spawner.camp_center = Vector2(500.0, 300.0)
	assert_eq(spawner.alive_count(), 0, "未入夜时不应有酸雾怪")
	gm.day_started.emit(2)
	assert_eq(spawner.alive_count(), 0, "白天信号不应刷怪（仅夜晚刷新）")
	gm.night_started.emit(2)
	var spawned: int = spawner.alive_count()
	assert_true(spawned >= 2 and spawned <= 3, "入夜应刷 2~3 只，实际 %d" % spawned)
	gm.day_started.emit(3)
	await wait_physics_frames(2)
	assert_eq(spawner.alive_count(), 0, "天亮应清除全部酸雾怪")


# 行为：直线冲撞——锁定方向后沿直线冲，速度读 balance，不追踪弯曲。
func test_charge_moves_straight_at_balance_speed() -> void:
	if not _implemented():
		return
	var mist: Node2D = _spawn_mist(Vector2(200.0, 0.0))
	var speed: float = float(gm.get_balance("monsters.acid_mist_speed", -1.0))
	assert_almost_eq(mist.charge_speed(), speed, 0.001, "冲撞速度应读自 balance")
	assert_almost_eq(speed, 90.0, 0.001, "balance 交叉验证：90 px/s")
	mist.charge_step(1.0, Vector2.ZERO)
	assert_almost_eq(mist.global_position.x, 200.0 - speed, 0.01, "应朝锁定方向冲一个速度步")
	# 撞墙后重新锁定（世界调用 redirect）：换目标后方向更新，但两次调用间保持直线。
	mist.redirect(Vector2(mist.global_position.x, 100.0))
	assert_almost_eq(mist.charge_direction().y, 1.0, 0.001, "redirect 后应锁定新方向")
	mist.charge_step(0.5, Vector2.ZERO)
	assert_almost_eq(mist.global_position.y, speed * 0.5, 0.01, "应沿新锁定方向直线冲")
	assert_almost_eq(mist.global_position.x, 200.0 - speed, 0.01, "直线冲撞不应追踪弯曲")


# AC2：冲撞命中玩家生命 -10（单次命中，不是持续掉血）。
func test_charge_hit_deals_10_once() -> void:
	if not _implemented():
		return
	var mist: Node2D = _spawn_mist(Vector2.ZERO)
	var player: CharacterBody2D = _spawn_player(Vector2(4.0, 0.0))
	mist.target_player = player
	var hit: float = float(gm.get_balance("damage.acid_mist_per_hit", -1.0))
	assert_almost_eq(hit, 10.0, 0.001, "balance 交叉验证：10/次")
	await wait_physics_frames(5)
	assert_almost_eq(gm.health, gm.health_max - hit, 0.01, "冲撞命中应 -10")
	await wait_physics_frames(10)
	assert_almost_eq(gm.health, gm.health_max - hit, 0.01, "单次命中不应持续扣血")


# AC3：中和喷雾命中即销毁并显示 sys_spray 字幕（走 FR-G-12 的道具使用全路径）。
func test_spray_hit_destroys_mist_and_shows_tip() -> void:
	if not _implemented():
		return
	if not ResourceLoader.exists(ITEM_EFFECTS_PATH):
		fail_test("尚未实现 %s（FR-G-12 / TP-09，本测试依赖道具效果）" % ITEM_EFFECTS_PATH)
		return
	var mist: Node2D = _spawn_mist(Vector2.ZERO)
	var fx: RefCounted = (load(ITEM_EFFECTS_PATH) as GDScript).new()
	var inv: RefCounted = (load(INVENTORY_PATH) as GDScript).new()
	inv.add_item("neutral_spray", 1)
	var result: Dictionary = fx.use_item("neutral_spray", inv, mist)
	assert_true(bool(result.get("success", false)), "喷雾命中应使用成功")
	assert_true(mist.is_queued_for_deletion(), "命中后酸雾怪应即销毁")
	await wait_physics_frames(2)
	assert_false(is_instance_valid(mist), "销毁后实例应被释放")
	assert_true(tip.is_shown("sys_spray"), "命中应显示 sys_spray 字幕")
	assert_eq(inv.count_of("neutral_spray"), 0, "喷雾应消耗一个")


# AC3 补充：hit_by_spray 幂等——重复命中不重复发信号、不崩溃。
func test_hit_by_spray_is_idempotent() -> void:
	if not _implemented():
		return
	var mist: Node2D = _spawn_mist(Vector2.ZERO)
	watch_signals(mist)
	mist.hit_by_spray()
	mist.hit_by_spray()
	assert_signal_emit_count(mist, "destroyed", 1, "销毁信号只应发一次")
	assert_true(mist.is_destroyed(), "命中后应处于已销毁状态")


# 逻辑代码不许出现中文文案（NFR-04；push_warning/push_error/print 诊断日志除外）。
func test_source_has_no_chinese_literals() -> void:
	if not _implemented():
		return
	for path: String in [MIST_SCRIPT_PATH, SPAWNER_SCRIPT_PATH]:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "%s 应可读" % path)
		if file == null:
			continue
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
				assert_false(c >= 0x4E00 and c <= 0x9FFF, "%s 逻辑代码出现中文字面量：%s" % [path, line])
