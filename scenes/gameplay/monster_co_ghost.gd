# CO 幽灵（FR-G-10，IT-G10）：矿洞全天 + 草原夜晚出现，匀速飘向玩家（可穿墙，"气体"设定），
# 接触按 damage.co_ghost_per_second 掉血；活性炭砸中即消散（吸附原理，FR-G-10 AC3）。
# 装备活性炭口罩（carbon_mask）时接触完全免疫（FR-G-10 AC5，SPEC-02 §4.1）。
# 首次接近触发一次 warn_co 警示字幕。AI 保持最简：匀速追踪，不做寻路与状态机分层。
extends Node2D

# 被活性炭砸中（世界/道具层接到后可播消散特效）。
signal destroyed()

# ==== 常量区 ====

const BAL_SPEED: String = "monsters.co_ghost_speed"
const BAL_DPS: String = "damage.co_ghost_per_second"

# 数据表缺失时的兜底默认值（不属调参项）。
const FALLBACK_SPEED: float = 28.0
const FALLBACK_DPS: float = 8.0

# 触发警示字幕的接近半径（balance 表无此键，属一次性布警参数；调参时一眼找到）。
const WARN_RADIUS: float = 64.0
const WARN_TIP_ID: String = "warn_co"

const PLAYER_GROUP: String = "player"

# 生成区域 id（SPEC-02 §3）：矿洞全天 + 草原夜晚。
const ZONE_MINE: String = "mine"
const ZONE_GRASSLAND: String = "grassland"

# 安全区（FR-M-01 AC2）：玩家在学院内时幽灵不追踪。
const ZONE_ACADEMY: String = "academy"

# 免疫道具 id（FR-G-10 AC5）：装备后接触完全免疫，判定只看 equipped_ids 是否含此 id。
const MASK_ITEM_ID: String = "carbon_mask"

# 光晕呼吸（表现参数，非调参项）：只动 %Glow 子节点局部 modulate，不影响位置/物理/玩法。
const GLOW_MODULATE_HIGH: float = 1.5
const GLOW_MODULATE_LOW: float = 0.6
const GLOW_PULSE_PERIOD: float = 1.1

# ==== 逻辑区 ====

# 目标玩家：由世界场景写入；为空时回退到 player 组查找。
var target_player: Node2D = null

var _contacts: Array = []
var _destroyed: bool = false

# 视觉逻辑分离（模块化重构）：身体/双眼/光晕各自独立节点（%Visuals 容器下），
# 各部件颜色与动画走独立方法，改单个部件不碰其他部件。
@onready var _contact_area: Area2D = %ContactArea
@onready var _body: Polygon2D = %Body
@onready var _eye_l: Polygon2D = %EyeL
@onready var _eye_r: Polygon2D = %EyeR
@onready var _glow: Polygon2D = %Glow
@onready var _anim_sprite: AnimatedSprite2D = %AnimSprite


func _ready() -> void:
	_contact_area.body_entered.connect(_on_contact_body_entered)
	_contact_area.body_exited.connect(_on_contact_body_exited)
	_apply_visuals()
	_start_glow_pulse()


# 生成规则（FR-G-10 AC1）：矿洞任意时间、草原仅夜晚；其余区域不出现。
static func can_spawn(zone_id: String, night: bool) -> bool:
	if zone_id == ZONE_MINE:
		return true
	if zone_id == ZONE_GRASSLAND and night:
		return true
	return false


func drift_speed() -> float:
	return _balance_float(BAL_SPEED, FALLBACK_SPEED)


# 接触伤害（/s）。FR-G-10 AC5：装备活性炭口罩（carbon_mask）时完全免疫，返回 0。
func contact_damage_per_second(equipped_ids: Array) -> float:
	if equipped_ids.has(MASK_ITEM_ID):
		return 0.0
	return _balance_float(BAL_DPS, FALLBACK_DPS)


# 活性炭砸中即消散（FR-G-10 AC3）：发 destroyed 信号并释放；重复砸幂等。
func hit_by_carbon() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit()
	queue_free()


func is_destroyed() -> bool:
	return _destroyed


# 时间可注入（SPEC-06 §3）：测试一次注入 1 秒断言精确掉血。
func apply_contact_tick(delta: float, equipped_ids: Array) -> void:
	if delta <= 0.0:
		return
	var dps: float = contact_damage_per_second(equipped_ids)
	if dps <= 0.0:
		return
	var gm: Node = _game_manager()
	if gm == null:
		return
	gm.modify_health(-dps * delta)


# 匀速朝目标飘动（最简追踪，可穿墙：直接改 position，不过物理碰撞）。
# 玩家在学院内时不追踪（FR-M-01 AC2：学院是安全区，取最简实现——静止）。
func drift_step(delta: float, target_pos: Vector2) -> void:
	if delta <= 0.0:
		return
	if _player_in_academy():
		return
	var to_target: Vector2 = target_pos - global_position
	if to_target.is_zero_approx():
		return
	# 贴图朝右为基准，向左飘时水平翻转。
	if _anim_sprite != null:
		_anim_sprite.flip_h = to_target.x < 0.0
	global_position += to_target.normalized() * minf(drift_speed() * delta, to_target.length())


func _player_in_academy() -> bool:
	var gm: Node = _game_manager()
	return gm != null and str(gm.current_zone()) == ZONE_ACADEMY


func is_touching_player() -> bool:
	var player: Node2D = _resolve_player()
	return player != null and _contacts.has(player)


func _physics_process(delta: float) -> void:
	if _destroyed:
		return
	var player: Node2D = _resolve_player()
	if player == null:
		return
	drift_step(delta, player.global_position)
	if global_position.distance_to(player.global_position) <= WARN_RADIUS:
		_show_warn_tip()
	if _contacts.has(player):
		apply_contact_tick(delta, _equipped_ids_of(player))


func _resolve_player() -> Node2D:
	if target_player != null and is_instance_valid(target_player):
		return target_player
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(PLAYER_GROUP) as Node2D


# 玩家若提供装备查询方法则读取；否则按无装备处理（装备 UI 接线由后续任务包完成）。
func _equipped_ids_of(player_node: Node) -> Array:
	if player_node != null and player_node.has_method("get_equipped_item_ids"):
		return player_node.get_equipped_item_ids()
	return []


func _show_warn_tip() -> void:
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip != null:
		tip.show_once(WARN_TIP_ID)


func _on_contact_body_entered(body: Node2D) -> void:
	if not _contacts.has(body):
		_contacts.append(body)


func _on_contact_body_exited(body: Node2D) -> void:
	_contacts.erase(body)


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
		_body.color = Color(0.6, 0.6, 0.6, 0.5)
	if _eye_l != null:
		_eye_l.color = Color(0.9, 0.95, 1.0, 1.0)
	if _eye_r != null:
		_eye_r.color = Color(0.9, 0.95, 1.0, 1.0)
	if _glow != null:
		_glow.color = Color(0.6, 0.6, 0.6, 0.18)


# 光晕呼吸（纯视觉：只动 %Glow 局部 modulate；节点 free 时随 tween 一起销毁）。
func _start_glow_pulse() -> void:
	if _glow == null:
		return
	var tween: Tween = create_tween().set_loops()
	tween.set_parallel(true)
	tween.tween_property(_glow, "modulate:a", GLOW_MODULATE_HIGH, GLOW_PULSE_PERIOD)
	tween.tween_property(_glow, "modulate:a", GLOW_MODULATE_LOW, GLOW_PULSE_PERIOD).set_delay(GLOW_PULSE_PERIOD)
