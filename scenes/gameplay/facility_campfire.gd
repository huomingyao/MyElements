# 篝火（FR-G-13 AC3）：交互进食 +能量（balance items.campfire_meal_restore），
# 每日限次（balance items.campfire_daily_limit，跨天经 GameManager.day_started 重置），
# 旁边生命缓慢回复（balance stats.health_regen_campfire）。
# 回血光环是子节点 %HealAura（Area2D）；时间只从 apply_aura(delta) 进（SPEC-06 §3 可测性约束）。
extends "res://scenes/gameplay/facility_base.gd"

# ==== 常量区 ====

const BAL_MEAL: String = "items.campfire_meal_restore"
const BAL_DAILY_LIMIT: String = "items.campfire_daily_limit"
const BAL_HEAL_RATE: String = "stats.health_regen_campfire"
const TIP_MEAL: String = "sys_energy_food"
# 达到上限的反馈：睡一觉到明天再来（tips.json 既有条目，数据表冻结不加新条）。
const TIP_LIMIT: String = "sys_sleep"

# 数据表缺失时的兜底默认值（不属调参项）。
const FALLBACK_MEAL: float = 40.0
const FALLBACK_DAILY_LIMIT: int = 3
const FALLBACK_HEAL_RATE: float = 1.0

# ==== 逻辑区 ====

var _bodies_in_aura: Array[Node] = []
var _meals_today: int = 0


func _ready() -> void:
	var aura: Area2D = get_node_or_null(^"%HealAura")
	if aura == null:
		push_warning("[facility] 篝火缺 %HealAura 子节点，回血光环不生效")
	else:
		aura.body_entered.connect(body_entered_heal_aura)
		aura.body_exited.connect(body_exited_heal_aura)
	var gm: Node = _game_manager()
	if gm != null and not gm.day_started.is_connected(reset_daily_meals):
		gm.day_started.connect(reset_daily_meals)


# 进食：能量 +meal（内部 clamp 到上限由 GameManager 负责），触发六大营养素字幕。
# 每日限次：达到上限只给提示字幕，不再免费加能量。
func interact(_player: Node) -> void:
	var gm: Node = _game_manager()
	if gm == null:
		push_warning("[facility] GameManager 不可用，进食未生效")
		return
	if _meals_today >= daily_meal_limit():
		_show_tip(TIP_LIMIT)
		return
	_meals_today += 1
	gm.modify_energy(_balance_float(BAL_MEAL, FALLBACK_MEAL))
	_show_tip(TIP_MEAL)


# 当日已进食次数（测试与界面断言用）。
func meals_today() -> int:
	return _meals_today


# 每日限次读 balance（改表即改行为，铁律 4）。
func daily_meal_limit() -> int:
	return int(_balance_float(BAL_DAILY_LIMIT, float(FALLBACK_DAILY_LIMIT)))


# 跨天清零（GameManager.day_started 驱动；也可直接调用，SPEC-06 §3 可测性约束）。
func reset_daily_meals(_day_count: int = 0) -> void:
	_meals_today = 0


func _process(delta: float) -> void:
	apply_aura(delta)


# 光环结算：范围内有对象才回血；测试可直接注入大 delta。
func apply_aura(delta: float) -> void:
	if delta <= 0.0:
		return
	_prune_aura()
	if _bodies_in_aura.is_empty():
		return
	var gm: Node = _game_manager()
	if gm == null:
		return
	gm.modify_health(_balance_float(BAL_HEAL_RATE, FALLBACK_HEAL_RATE) * delta)


# 进出光环由 %HealAura 的信号驱动；测试可直接调用这两个方法模拟占位。
func body_entered_heal_aura(body: Node) -> void:
	if body != null and not _bodies_in_aura.has(body):
		_bodies_in_aura.append(body)


func body_exited_heal_aura(body: Node) -> void:
	_bodies_in_aura.erase(body)


func _prune_aura() -> void:
	_bodies_in_aura = _bodies_in_aura.filter(func(node: Node) -> bool: return is_instance_valid(node))
