# CuSO₄ 溶液池（FR-G-16，IT-G16）：矿洞蓝色伤害区，Area2D 被动伤害（无 E 交互）。
# 浸泡期间按 damage.cuso4_pool_per_second（5/s）扣血，离开即停；
# 首次接近触发一次 warn_cuso4 警示字幕（KnowledgeTip.show_once 语义）；
# 池内致死复用 GameManager.modify_health 的 player_died 通道（FR-C-06 正常死亡流程）。
extends Area2D

# ==== 常量区 ====

const BAL_DPS: String = "damage.cuso4_pool_per_second"

# 数据表缺失时的兜底默认值（不属调参项）。
const FALLBACK_DPS: float = 5.0

# 触发警示字幕的接近半径（balance 表无此键，属一次性布警参数；调参时一眼找到）。
# 大于池体半宽，保证玩家踏入前先看到警示。
const WARN_RADIUS: float = 96.0
const WARN_TIP_ID: String = "warn_cuso4"

const PLAYER_GROUP: String = "player"

# ==== 逻辑区 ====

# 目标玩家：由世界场景写入；为空时回退到 player 组查找。
var target_player: Node2D = null

var _contacts: Array = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


# 浸泡伤害（/s），读 balance 表（改数值不改代码，FR-G-16 AC1）。
func damage_per_second() -> float:
	return _balance_float(BAL_DPS, FALLBACK_DPS)


# 时间可注入（SPEC-06 §3）：测试一次注入 1 秒断言精确掉血。
func apply_pool_tick(delta: float) -> void:
	if delta <= 0.0:
		return
	var dps: float = damage_per_second()
	if dps <= 0.0:
		return
	var gm: Node = _game_manager()
	if gm == null:
		return
	gm.modify_health(-dps * delta)


func is_player_inside() -> bool:
	var player: Node2D = _resolve_player()
	return player != null and _contacts.has(player)


func _physics_process(delta: float) -> void:
	var player: Node2D = _resolve_player()
	if player == null:
		return
	if global_position.distance_to(player.global_position) <= WARN_RADIUS:
		_show_warn_tip()
	if _contacts.has(player):
		apply_pool_tick(delta)


func _resolve_player() -> Node2D:
	if target_player != null and is_instance_valid(target_player):
		return target_player
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(PLAYER_GROUP) as Node2D


func _show_warn_tip() -> void:
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip != null:
		tip.show_once(WARN_TIP_ID)


func _on_body_entered(body: Node2D) -> void:
	if not _contacts.has(body):
		_contacts.append(body)


func _on_body_exited(body: Node2D) -> void:
	_contacts.erase(body)


func _game_manager() -> Node:
	return get_node_or_null(^"/root/GameManager")


func _balance_float(key: String, fallback: float) -> float:
	var gm: Node = _game_manager()
	if gm == null:
		return fallback
	return float(gm.get_balance(key, fallback))
