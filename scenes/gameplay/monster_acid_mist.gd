# 酸雾怪（FR-G-11，IT-G11）：夜晚在营地外围刷新，锁定方向直线冲撞，命中 -10（单次）；
# 中和喷雾喷中即消散。撞墙后自行重锁定玩家方向（沿锁定方向的短距射线探测墙体，
# 不再依赖世界调用 redirect）；存活超过 balance 的 monsters.acid_mist_lifetime_seconds
# 自销毁（防锁定方向飞出地图永不回收）。
# AI 保持最简：直线冲撞 + 重锁定，不做寻路与状态机分层。
extends Node2D

signal destroyed()

# ==== 常量区 ====

const BAL_SPEED: String = "monsters.acid_mist_speed"
const BAL_HIT: String = "damage.acid_mist_per_hit"
const BAL_LIFETIME: String = "monsters.acid_mist_lifetime_seconds"

# 数据表缺失时的兜底默认值（不属调参项）。
const FALLBACK_SPEED: float = 90.0
const FALLBACK_HIT: float = 10.0
const FALLBACK_LIFETIME: float = 200.0

# 撞墙探测的射线长度（机制参数，balance 表无此键；略大于单帧位移即可提前转向）。
const WALL_PROBE_DISTANCE: float = 16.0

# 光晕呼吸（表现参数，非调参项）：只动 %Glow 子节点局部 modulate，不影响位置/物理/玩法。
const GLOW_MODULATE_HIGH: float = 1.5
const GLOW_MODULATE_LOW: float = 0.6
const GLOW_PULSE_PERIOD: float = 0.9

const PLAYER_GROUP: String = "player"

# ==== 逻辑区 ====

# 目标玩家：由刷新器/世界写入；为空时回退到 player 组查找。
var target_player: Node2D = null

var _charge_dir: Vector2 = Vector2.ZERO
var _has_lock: bool = false
var _struck: Array = []
var _destroyed: bool = false
var _alive_seconds: float = 0.0

# 视觉逻辑分离（模块化重构）：外圈/主体/内芯各自独立节点（%Visuals 容器下），
# 各部件颜色与动画走独立方法，改单个部件不碰其他部件。
@onready var _hit_area: Area2D = %HitArea
@onready var _body: Polygon2D = %Body
@onready var _core: Polygon2D = %Core
@onready var _glow: Polygon2D = %Glow
@onready var _anim_sprite: AnimatedSprite2D = %AnimSprite


func _ready() -> void:
	_hit_area.body_entered.connect(_on_hit_area_body_entered)
	_hit_area.body_exited.connect(_on_hit_area_body_exited)
	_apply_visuals()
	_start_glow_pulse()


func charge_speed() -> float:
	return _balance_float(BAL_SPEED, FALLBACK_SPEED)


func hit_damage() -> float:
	return _balance_float(BAL_HIT, FALLBACK_HIT)


func lifetime_seconds() -> float:
	return _balance_float(BAL_LIFETIME, FALLBACK_LIFETIME)


func charge_direction() -> Vector2:
	return _charge_dir


# 直线冲撞：首次调用时锁定指向目标的方向，之后沿直线冲（SPEC-02 §4.6 最简 AI）。
func charge_step(delta: float, target_pos: Vector2) -> void:
	if _destroyed or delta <= 0.0:
		return
	if not _has_lock:
		redirect(target_pos)
	# 贴图朝右为基准，向左冲时水平翻转。
	if _anim_sprite != null and not is_zero_approx(_charge_dir.x):
		_anim_sprite.flip_h = _charge_dir.x < 0.0
	global_position += _charge_dir * charge_speed() * delta


# 重新锁定方向（撞墙后由自身重锁定调用；测试可直接调用）。
func redirect(target_pos: Vector2) -> void:
	var to_target: Vector2 = target_pos - global_position
	if to_target.is_zero_approx():
		return
	_charge_dir = to_target.normalized()
	_has_lock = true


# 撞墙探测：沿锁定方向打一条短距射线，命中墙体（非玩家的物理体）视为撞墙。
# 场景根节点是 Node2D 而非 CharacterBody2D，用不了 is_on_wall()，用射线等价判定；
# 玩家本体从命中里排除，避免把冲到玩家脸上误判成撞墙。
func is_wall_ahead() -> bool:
	if not _has_lock or _charge_dir.is_zero_approx() or not is_inside_tree():
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return false
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		global_position, global_position + _charge_dir * WALL_PROBE_DISTANCE)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var exclude: Array[RID] = []
	var player: Node2D = _resolve_player()
	if player is CollisionObject2D:
		exclude.append((player as CollisionObject2D).get_rid())
	query.exclude = exclude
	return not space.intersect_ray(query).is_empty()


# 存活计时：累计超过 lifetime_seconds() 自销毁，返回本帧是否触发（SPEC-06 §3：
# 测试可直接注入大 delta，不等真实秒数）。
func apply_timeout(delta: float) -> bool:
	if _destroyed or delta <= 0.0:
		return false
	_alive_seconds += delta
	if _alive_seconds < lifetime_seconds():
		return false
	despawn()
	return true


# 存活超时自销毁：与喷雾命中同一条销毁路径，幂等。
func despawn() -> void:
	_destroy()


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
	_destroy()


func is_destroyed() -> bool:
	return _destroyed


func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit()
	queue_free()


func _physics_process(delta: float) -> void:
	if _destroyed:
		return
	if apply_timeout(delta):
		return
	var player: Node2D = _resolve_player()
	if player == null:
		return
	# 撞墙自行重锁定（修复：world.gd 从未调用 redirect，酸雾怪一锁到底永不回头）。
	if is_wall_ahead():
		redirect(player.global_position)
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


# 占位视觉按部件配置（P4 美术替换前的确定性配色；改单个部件色直接改这里）。
func _apply_visuals() -> void:
	if _body != null:
		_body.color = Color(0.7, 0.85, 0.2, 0.6)
	if _core != null:
		_core.color = Color(0.85, 1.0, 0.35, 0.85)
	if _glow != null:
		_glow.color = Color(0.7, 0.85, 0.2, 0.25)


# 光晕呼吸（纯视觉：只动 %Glow 局部 modulate；节点 free 时随 tween 一起销毁）。
func _start_glow_pulse() -> void:
	if _glow == null:
		return
	var tween: Tween = create_tween().set_loops()
	tween.set_parallel(true)
	tween.tween_property(_glow, "modulate:a", GLOW_MODULATE_HIGH, GLOW_PULSE_PERIOD)
	tween.tween_property(_glow, "modulate:a", GLOW_MODULATE_LOW, GLOW_PULSE_PERIOD).set_delay(GLOW_PULSE_PERIOD)
