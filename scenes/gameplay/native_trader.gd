# 原住民（FR-G-15，IT-G15）：营地 NPC，收购玩家背包里的道具换食物（直接回能量）。
# 按 E 进交易态（sys_trade_prompt）→ 世界把数字键路由到 sell_slot() → 成交或退出。
# 只收道具表条目（人造装备），物质不收；已装备的先卸下；走远自动退出（AC5）。
# 数值读 balance（items.trade_energy_restore），文案全走 tips.json（NFR-04）。
extends "res://scenes/gameplay/facility_base.gd"

# 成交一件（供世界/测试接表现层）。
signal trade_completed(item_id: String)

# ==== 常量区 ====

const BAL_TRADE_ENERGY: String = "items.trade_energy_restore"
const BAL_INTERACT_RADIUS: String = "player.interact_radius"

# 数据表缺失时的兜底默认值（不属调参项）。
const FALLBACK_TRADE_ENERGY: float = 20.0
const FALLBACK_INTERACT_RADIUS: float = 28.0

const TIP_PROMPT: String = "sys_trade_prompt"
const TIP_DONE: String = "sys_trade_done"
const TIP_EMPTY: String = "sys_trade_empty"

const TORCH_ITEM_ID: String = "sulfur_torch"

# ==== 逻辑区 ====

var _trading: bool = false
var _player: Node = null


func is_trading() -> bool:
	return _trading


# 按 E：进交易态 ⇄ 退出（AC1/AC5）。
func interact(player: Node) -> void:
	if _trading:
		_end_trading()
		return
	if player == null:
		return
	_trading = true
	_player = player
	_show_tip(TIP_PROMPT)


# 卖出快捷栏第 index 格（世界把 use_item_N 热键路由到这里）。
# 成功：道具 -1、能量 +balance、字幕 sys_trade_done、退出交易态。
# 失败（空格/物质/无背包）：字幕 sys_trade_empty，不扣东西、保持交易态（AC4）。
func sell_slot(index: int) -> bool:
	if not _trading or _player == null:
		return false
	var inventory: RefCounted = _inventory_of(_player)
	if inventory == null:
		_show_tip(TIP_EMPTY)
		return false
	var slots: Array = inventory.slots()
	if index < 0 or index >= slots.size():
		_show_tip(TIP_EMPTY)
		return false
	var item_id: String = str(slots[index].get("id", ""))
	if not _is_sellable(item_id):
		_show_tip(TIP_EMPTY)
		return false
	_unequip_if_needed(item_id)
	inventory.remove_item(item_id, 1)
	var gm: Node = _game_manager()
	if gm != null:
		gm.modify_energy(_balance_float(BAL_TRADE_ENERGY, FALLBACK_TRADE_ENERGY))
	_show_tip(TIP_DONE)
	trade_completed.emit(item_id)
	_end_trading()
	return true


# 走远自动退出（AC5：超出交互半径两倍）。
func _physics_process(_delta: float) -> void:
	if not _trading or _player == null or not is_instance_valid(_player):
		return
	var radius: float = _balance_float(BAL_INTERACT_RADIUS, FALLBACK_INTERACT_RADIUS) * 2.0
	if global_position.distance_to(_player.global_position) > radius:
		_end_trading()


func _end_trading() -> void:
	_trading = false
	_player = null


# 只收道具表条目（人造装备）；物质（substances.json）不收（AC4）。
func _is_sellable(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	var items: RefCounted = (load("res://scripts/gameplay/item_effects.gd") as GDScript).new()
	return not items.get_item(item_id).is_empty()


# 已装备的先卸下（AC3）；火把要同步玩家的照明状态。
func _unequip_if_needed(item_id: String) -> void:
	var effects: Variant = _player.get("item_effects")
	if effects != null and (effects as RefCounted).has_method("is_equipped"):
		if bool(effects.is_equipped(item_id)):
			effects.unequip(item_id)
	if item_id == TORCH_ITEM_ID and _player.has_method("set_torch_equipped"):
		_player.set_torch_equipped(false)
