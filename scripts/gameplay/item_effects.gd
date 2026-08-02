# ItemEffects（FR-G-12，UT-G12）：八种道具效果，数据驱动读 items.json。
# 纯逻辑 RefCounted，不进场景树、可直接实例化（SPEC-06 §3 可测性约束，同 inventory.gd）。
# 效果数值全部经 effect_value_key 指向 balance.json 读取，改数值不改代码（铁律 4）。
extends RefCounted

# ==== 常量区 ====

const ITEMS_TABLE: String = "items.json"

const KEY_TYPE: String = "type"
const KEY_EFFECT: String = "effect"
const KEY_VALUE_KEY: String = "effect_value_key"
const KEY_CONSUMABLE: String = "consumable"
const KEY_TIP: String = "tip_id"

const TYPE_EQUIP: String = "equip"
const TYPE_CONSUME: String = "consume"

# effect 枚举见 SPEC-04 §10；这里只放键名，效果数值一律走 balance。
const EFFECT_KILL_ACID: String = "kill_acid"
const EFFECT_KILL_CO: String = "kill_co"
const EFFECT_RESTORE_OXYGEN: String = "restore_oxygen"
const EFFECT_RESTORE_ENERGY: String = "restore_energy"
const EFFECT_EXTINGUISH: String = "extinguish"
const EFFECT_TEST_HARDWATER: String = "test_hardwater"
const EFFECT_NONE: String = "none"

# 硬水鉴别（肥皂水）只在盐湖湖水区域生效（FR-G-12 边界 / FR-G-14 AC3：对湖水使用）。
const ZONE_SALTLAKE: String = "saltlake"

# items.json 未配 tip_id 的效果的兜底字幕（数据表冻结不改表；条目必须已存在于 tips.json）。
# 灭火器原理：碳酸氢钠+酸快速产生 CO2 隔绝氧气灭火（SPEC-05 R10），复用 tip_co2。
const FALLBACK_TIP_EXTINGUISH: String = "tip_co2"

# use_item 返回字典的键名（调用方约定，同 RecipeDB.try_catch 的风格）。
const R_SUCCESS: String = "success"
const R_EFFECT: String = "effect"
const R_VALUE: String = "value"
const R_CONSUMED: String = "consumed"
const R_TIP: String = "tip_id"
const R_REASON: String = "reason"

# ==== 逻辑区 ====

var _items: Dictionary = {}
var _equipped: Dictionary = {}


func _init() -> void:
	reload()


# 重新读 items.json（调参/测试用）。
func reload() -> void:
	load_from(DataLoader.load_table(ITEMS_TABLE, TYPE_ARRAY, []))


# 数据注入口（SPEC-06 §3 可测性约束）：测试可用内存数组替代真实数据表。
func load_from(rows: Array) -> void:
	_items = DataLoader.index_by_id(rows)
	_equipped.clear()


# 按 id 取道具定义；不存在返回空字典。返回副本，外部改动不影响内部表。
func get_item(item_id: String) -> Dictionary:
	var item: Variant = _items.get(item_id, {})
	if typeof(item) != TYPE_DICTIONARY:
		return {}
	return (item as Dictionary).duplicate()


func all_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: String in _items:
		out.append((_items[key] as Dictionary).duplicate())
	return out


func is_equipment(item_id: String) -> bool:
	return str((_items.get(item_id, {}) as Dictionary).get(KEY_TYPE, "")) == TYPE_EQUIP


func is_consumable(item_id: String) -> bool:
	return str((_items.get(item_id, {}) as Dictionary).get(KEY_TYPE, "")) == TYPE_CONSUME


# 效果数值：按 items.json 的 effect_value_key 到 balance.json 取值（FR-G-12 AC1）。
# 没配 effect_value_key 的效果（kill_acid 等）没有数值，返回 0。
func effect_value(item_id: String) -> float:
	var key: String = str((_items.get(item_id, {}) as Dictionary).get(KEY_VALUE_KEY, ""))
	if key.is_empty():
		return 0.0
	var gm: Node = _game_manager()
	if gm == null:
		return 0.0
	return float(gm.get_balance(key, 0.0))


# 装备型道具：进入已装备集合，持续生效（FR-G-12 AC2）。重复装备幂等。
func equip(item_id: String) -> bool:
	var item: Dictionary = _items.get(item_id, {})
	if item.is_empty() or str(item.get(KEY_TYPE, "")) != TYPE_EQUIP:
		push_warning("[item] 不可装备：%s（忽略）" % item_id)
		return false
	_equipped[item_id] = true
	_show_tip(str(item.get(KEY_TIP, "")))
	return true


func unequip(item_id: String) -> void:
	_equipped.erase(item_id)


func is_equipped(item_id: String) -> bool:
	return _equipped.has(item_id)


func equipped_ids() -> Array:
	return _equipped.keys()


# 使用道具。返回：
# { success, effect, value, consumed, tip_id, reason }
# reason 取值：unknown_item / not_usable / no_target / not_in_inventory / ""
func use_item(item_id: String, inventory: RefCounted, target: Node = null) -> Dictionary:
	var result: Dictionary = {
		R_SUCCESS: false,
		R_EFFECT: "",
		R_VALUE: 0.0,
		R_CONSUMED: false,
		R_TIP: "",
		R_REASON: "",
	}
	var item: Dictionary = _items.get(item_id, {})
	if item.is_empty():
		push_warning("[item] 未知道具 id：%s（忽略）" % item_id)
		result[R_REASON] = "unknown_item"
		return result
	var effect: String = str(item.get(KEY_EFFECT, EFFECT_NONE))
	var tip_id: String = str(item.get(KEY_TIP, ""))
	# 数据表没配字幕的效果用代码兜底，保证消耗型道具不会零反馈（灭火器连字幕都没有的漏洞）。
	if tip_id.is_empty() and effect == EFFECT_EXTINGUISH:
		tip_id = FALLBACK_TIP_EXTINGUISH
	result[R_EFFECT] = effect
	result[R_TIP] = tip_id
	result[R_VALUE] = effect_value(item_id)
	var type: String = str(item.get(KEY_TYPE, ""))
	if type == TYPE_EQUIP:
		# 先校验持有再装备：隔空装备漏洞（未持有也能 equip）的修复。
		if inventory == null or not inventory.has_item(item_id, 1):
			result[R_REASON] = "not_in_inventory"
			return result
		result[R_SUCCESS] = equip(item_id)
		return result
	if type != TYPE_CONSUME or effect == EFFECT_NONE:
		result[R_REASON] = "not_usable"
		return result
	# 消耗型：砸怪类道具必须命中目标才许使用，不许对空气浪费。
	if effect == EFFECT_KILL_ACID and (target == null or not target.has_method("hit_by_spray")):
		result[R_REASON] = "no_target"
		return result
	if effect == EFFECT_KILL_CO and (target == null or not target.has_method("hit_by_carbon")):
		result[R_REASON] = "no_target"
		return result
	# 肥皂水位置校验：仅盐湖湖水区域可鉴别硬水；他处不消耗、不播硬水字幕（包B-A5）。
	if effect == EFFECT_TEST_HARDWATER and _current_zone() != ZONE_SALTLAKE:
		result[R_REASON] = "wrong_place"
		return result
	if inventory == null or not inventory.has_item(item_id, 1):
		result[R_REASON] = "not_in_inventory"
		return result
	_apply_effect(effect, float(result[R_VALUE]), target)
	result[R_CONSUMED] = inventory.remove_item(item_id, 1)
	result[R_SUCCESS] = true
	_show_tip(tip_id)
	return result


# 结算效果本身。extinguish / test_hardwater 的剧情与设施钩子由后续任务包接线，
# 本任务包只负责消耗语义与字幕（FR-G-12 AC2）：两者的即时反馈是 use_item 播的字幕
# （灭火器兜底 tip_co2，肥皂水走 items.json 的 sys_hardwater），这里显式占位防漏配。
func _apply_effect(effect: String, value: float, target: Node) -> void:
	var gm: Node = _game_manager()
	match effect:
		EFFECT_RESTORE_OXYGEN:
			if gm != null:
				gm.modify_oxygen(value)
		EFFECT_RESTORE_ENERGY:
			if gm != null:
				gm.modify_energy(value)
		EFFECT_KILL_ACID:
			target.hit_by_spray()
		EFFECT_KILL_CO:
			target.hit_by_carbon()
		EFFECT_EXTINGUISH:
			pass # 火灾剧情钩子未接线；反馈为字幕，见函数头注释。
		EFFECT_TEST_HARDWATER:
			pass # 硬水鉴别剧情钩子未接线；反馈为字幕，见函数头注释。


func _show_tip(tip_id: String) -> void:
	if tip_id.is_empty():
		return
	var tip: Node = _knowledge_tip()
	if tip != null:
		tip.show(tip_id)


# ==== autoload 访问（缺失时静默降级，不崩溃；同 inventory.gd 的做法） ====

func _game_manager() -> Node:
	return _autoload(^"GameManager")


# 当前区域（位置校验用）：GameManager 缺失时返回空串，按「不在盐湖」安全拒绝。
func _current_zone() -> String:
	var gm: Node = _game_manager()
	if gm == null:
		return ""
	return str(gm.current_zone())


func _knowledge_tip() -> Node:
	return _autoload(^"KnowledgeTip")


func _autoload(node_path: NodePath) -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(node_path)
