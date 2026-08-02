# 粗盐提纯三步状态机（FR-G-14，TP-10）：溶解 → 过滤 → 蒸发，顺序错误拒绝并给提示。
# 纯逻辑 RefCounted，可被单测直接实例化（SPEC-06 §3，同 inventory.gd 的定位）。
# 完成时走 RecipeDB.try_craft（tool=bench / condition=three_step，SPEC-05 R11），
# 产物与卡片全部来自数据表；字幕 id 取配方 unlock_tip 字段。
extends RefCounted

# ==== 常量区 ====

# 三步顺序（SPEC-05 R11：溶解 → 过滤 → 蒸发）。id 不是玩家可见文案。
const STEPS: Array[String] = ["dissolve", "filter", "evaporate"]

const INPUT_ID: String = "crude_salt"
const RECIPE_ID: String = "r_salt_purify"
const TOOL_ID: String = "bench"
const CONDITION_ID: String = "three_step"

# 跳步/缺料时的提示与每步字幕同用配方的 unlock_tip（sys_purify 文案本身就是正确顺序）。
const FALLBACK_TIP_ID: String = "sys_purify"

# ==== 逻辑区 ====

var _step_index: int = 0
var _done: bool = false


# 当前等待的步骤 id；已完成返回空串。
func expected_step() -> String:
	if _done or _step_index >= STEPS.size():
		return ""
	return STEPS[_step_index]


func is_done() -> bool:
	return _done


# 流程是否已经开始（完成第一步后算开始；已完成也算开始过）。
func is_started() -> bool:
	return _step_index > 0 or _done


# 重新开始一轮（上一轮的粗盐已变成 nacl）。
func reset() -> void:
	_step_index = 0
	_done = false


# 推进一步。inventory 用 duck-typing（has_item/remove_item/add_item），与背包实现解耦。
# 返回 {ok, rejected, done, outputs, card}：rejected=true 时状态完全不变、不给产物。
func advance(step_id: String, inventory: RefCounted) -> Dictionary:
	var result: Dictionary = {"ok": false, "rejected": true, "done": false, "outputs": [], "card": {}}
	if _done:
		_show_tip(_tip_id())
		return result
	if step_id != expected_step():
		# 跳步：给正确顺序的提示，状态不变、不消耗、不产出（AC1）。
		_show_tip(_tip_id())
		return result
	if _step_index == 0:
		# 第一步（溶解）需要粗盐在手。
		if inventory == null or not bool(inventory.has_item(INPUT_ID, 1)):
			_show_tip(_tip_id())
			return result
	_step_index += 1
	if _step_index < STEPS.size():
		# 中间步骤：每步一条字幕（FR-G-14 描述），不产出不消耗。
		_show_tip(_tip_id())
		result["ok"] = true
		result["rejected"] = false
		return result
	return _finish(inventory, result)


# 第三步完成：材料匹配走配方引擎（规则与合成台一致），产物入包，卡片随结果返回。
func _finish(inventory: RefCounted, result: Dictionary) -> Dictionary:
	var db: Node = _recipe_db()
	if db == null:
		push_warning("[purify] RecipeDB 不可用，提纯未结算")
		_step_index -= 1  # 回滚，允许重试
		return result
	var craft: Dictionary = db.try_craft([INPUT_ID], TOOL_ID, CONDITION_ID)
	if not bool(craft.get("success", false)):
		push_warning("[purify] 提纯配方匹配失败：%s" % str(craft.get("fail_reason", "")))
		_step_index -= 1
		return result
	inventory.remove_item(INPUT_ID, 1)
	for output_id: Variant in (craft.get("outputs", []) as Array):
		inventory.add_item(str(output_id), 1)
	_done = true
	_show_tip(_tip_id())
	result["ok"] = true
	result["rejected"] = false
	result["done"] = true
	result["outputs"] = craft.get("outputs", [])
	result["card"] = craft.get("card", {})
	return result


# 字幕 id 来自配方 unlock_tip 字段；缺字段时用常量兜底（sys_purify 即正确顺序提示）。
func _tip_id() -> String:
	var db: Node = _recipe_db()
	if db == null:
		return FALLBACK_TIP_ID
	var recipe: Dictionary = db.get_recipe(RECIPE_ID)
	var tip_id: String = str(recipe.get("unlock_tip", ""))
	if tip_id.is_empty():
		return FALLBACK_TIP_ID
	return tip_id


func _show_tip(tip_id: String) -> void:
	var tip: Node = _knowledge_tip()
	if tip == null:
		push_warning("[purify] KnowledgeTip 不可用，字幕未显示：%s" % tip_id)
		return
	tip.show(tip_id)


func _autoload(node_name: String) -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(node_name)


func _recipe_db() -> Node:
	return _autoload(^"RecipeDB")


func _knowledge_tip() -> Node:
	return _autoload(^"KnowledgeTip")
