# 酸雾怪（FR-G-11，IT-G11）：夜晚在营地外围刷新，锁定方向直线冲撞，命中 -10（单次）；
# 中和喷雾喷中即消散。撞墙后由世界调用 redirect() 重新锁定。
# AI 保持最简：直线冲撞 + 重锁定，不做寻路与状态机分层。
extends Node2D

signal destroyed()

# ==== 常量区 ====

const BAL_SPEED: String = "monsters.acid_mist_speed"
const BAL_HIT: String = "damage.acid_mist_per_hit"

# 数据表缺失时的兜底默认值（不属调参项）。
const FALLBACK_SPEED: float = 90.0
const FALLBACK_HIT: float = 10.0

const PLAYER_GROUP: String = "player"

# ==== 逻辑区 ====

# 目标玩家：由刷新器/世界写入；为空时回退到 player 组查找。
var target_player: Node2D = null

var _charge_dir: Vector2 = Vector2.ZERO
var _has_lock: bool = false
var _struck: Array = []
var _destroyed: bool = false

@onready var _hit_area: Area2D = %HitArea


func _ready() -> void:
	_hit_area.body_entered.connect(_on_hit_area_body_entered)
	_hit_area.body_exited.connect(_on_hit_area_body_exited)


func charge_speed() -> float:
	return _balance_float(BAL_SPEED, FALLBACK_SPEED)


func hit_damage() -> float:
	return _balance_float(BAL_HIT, FALLBACK_HIT)


func charge_direction() -> Vector2:
	return _charge_dir


# 直线冲撞：首次调用时锁定指向目标的方向，之后沿直线冲（SPEC-02 §4.6 最简 AI）。
func charge_step(delta: float, target_pos: Vector2) -> void:
	if _destroyed or delta <= 0.0:
		return
	if not _has_lock:
		redirect(target_pos)
	global_position += _charge_dir * charge_speed() * delta


# 重新锁定方向（撞墙后由世界调用；测试可直接调用）。
func redirect(target_pos: Vector2) -> void:
	var to_target: Vector2 = target_pos - global_position
	if to_target.is_zero_approx():
		return
	_charge_dir = to_target.normalized()
	_has_lock = true


# 冲撞命中：-10（FR-G-11 AC2）。每次进入碰撞区只结算一次，离开后可再次命中。
func apply_hit() -> void:
	if _destroyed:
		return
	var gm: Node = _game_manager()
	if gm == null:
		return
	gm.modify_health(-hit_damage())


# 中和喷雾命中：即销毁（FR-G-11 AC3）。sys_spray 字幕由 ItemEffects 统一显示，避免双字幕。
func hit_by_spray() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit()
	queue_free()


func is_destroyed() -> bool:
	return _destroyed


func _physics_process(delta: float) -> void:
	var player: Node2D = _resolve_player()
	if player != null:
		charge_step(delta, player.global_position)


func _resolve_player() -> Node2D:
	if target_player != null and is_instance_valid(target_player):
		return target_player
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(PLAYER_GROUP) as Node2D


func _is_player(body: Node) -> bool:
	return body == target_player or body.is_in_group(PLAYER_GROUP)


func _on_hit_area_body_entered(body: Node2D) -> void:
	if _destroyed or not _is_player(body) or _struck.has(body):
		return
	_struck.append(body)
	apply_hit()


func _on_hit_area_body_exited(body: Node2D) -> void:
	_struck.erase(body)


func _game_manager() -> Node:
	return get_node_or_null(^"/root/GameManager")


func _balance_float(key: String, fallback: float) -> float:
	var gm: Node = _game_manager()
	if gm == null:
		return fallback
	return float(gm.get_balance(key, fallback))
