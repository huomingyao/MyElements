# 酸雾怪刷新器（FR-G-11 AC1）：night_started 时在营地外围刷 2~3 只，day_started 时全部清除。
# 数量读 balance 的 monsters.acid_mist_night_count_min/max；rng 可注入种子，测试可复现（SPEC-06 §3）。
extends Node2D

# ==== 常量区 ====

const BAL_COUNT_MIN: String = "monsters.acid_mist_night_count_min"
const BAL_COUNT_MAX: String = "monsters.acid_mist_night_count_max"

# 数据表缺失时的兜底默认值（不属调参项）。
const FALLBACK_COUNT_MIN: int = 2
const FALLBACK_COUNT_MAX: int = 3

const MIST_SCENE_PATH: String = "res://scenes/gameplay/monster_acid_mist.tscn"

# 营地外围刷新环半径（balance 表无此键；地图到位后按营地大小调）。
const SPAWN_RADIUS: float = 120.0

# ==== 逻辑区 ====

# 营地中心：地图到位前由世界场景写入；测试直接赋值。
var camp_center: Vector2 = Vector2.ZERO
# 目标玩家，透传给刷出的酸雾怪。
var target_player: Node2D = null
# 可注入的场景与随机源（测试注入种子复现结果）。
var mist_scene: PackedScene = null
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _mists: Array = []


func _ready() -> void:
	rng.randomize()
	if mist_scene == null and ResourceLoader.exists(MIST_SCENE_PATH):
		mist_scene = load(MIST_SCENE_PATH) as PackedScene
	var gm: Node = _game_manager()
	if gm == null:
		return
	if not gm.night_started.is_connected(_on_night_started):
		gm.night_started.connect(_on_night_started)
	if not gm.day_started.is_connected(_on_day_started):
		gm.day_started.connect(_on_day_started)


# 夜晚刷新数量：balance 的 [min, max] 闭区间（FR-G-11 AC1）。
func night_mist_count() -> int:
	var lo: int = int(_balance(BAL_COUNT_MIN, FALLBACK_COUNT_MIN))
	var hi: int = int(_balance(BAL_COUNT_MAX, FALLBACK_COUNT_MAX))
	if hi < lo:
		push_warning("[monster] 酸雾怪数量上下限颠倒（%d > %d），按下限处理" % [lo, hi])
		hi = lo
	return rng.randi_range(lo, hi)


# 在营地外围的环上均匀刷一晚的酸雾怪，返回刷出的实例。
func spawn_night_mists() -> Array:
	clear_mists()
	if mist_scene == null:
		push_warning("[monster] 酸雾怪场景缺失：%s（跳过刷新）" % MIST_SCENE_PATH)
		return []
	var count: int = night_mist_count()
	for i: int in count:
		var mist: Node2D = mist_scene.instantiate() as Node2D
		add_child(mist)
		var angle: float = TAU * float(i) / float(count)
		mist.global_position = camp_center + Vector2.RIGHT.rotated(angle) * SPAWN_RADIUS
		mist.target_player = target_player
		_mists.append(mist)
	return _mists.duplicate()


# 白天清除全部酸雾怪（FR-G-11 AC1）。
func clear_mists() -> void:
	for mist: Node in _mists:
		if is_instance_valid(mist):
			mist.queue_free()
	_mists.clear()


# 当前存活数（已 queue_free 但未释放的不计）。
func alive_count() -> int:
	var count: int = 0
	for mist: Node in _mists:
		if is_instance_valid(mist) and not mist.is_queued_for_deletion():
			count += 1
	return count


func _on_night_started(_day_count: int) -> void:
	spawn_night_mists()


func _on_day_started(_day_count: int) -> void:
	clear_mists()


func _game_manager() -> Node:
	return get_node_or_null(^"/root/GameManager")


func _balance(key: String, fallback: int) -> Variant:
	var gm: Node = _game_manager()
	if gm == null:
		return fallback
	return gm.get_balance(key, fallback)
