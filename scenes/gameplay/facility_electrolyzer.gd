# 电解器（FR-G-13 AC2）：纯净水 → H₂ + O₂，按体积比 1:2 给量（正氧负氢，SPEC-05 R5）。
# 产物清单与卡片走 RecipeDB.try_craft（tool=electrolyzer / condition=electrify），
# 字幕 id 取配方的 unlock_tip 字段——改内容不改代码（铁律 4）。
extends "res://scenes/gameplay/facility_base.gd"

# ==== 常量区 ====

const INPUT_ID: String = "h2o_clean"
const RECIPE_ID: String = "r_electrolysis"
const TOOL_ID: String = "electrolyzer"
const CONDITION_ID: String = "electrify"

# 各产物单次电解的给量（化学计量比：2H₂O =通电= 2H₂↑ + O₂↑，SPEC-05 R5 体积比 1:2）。
# 本任务包白名单不含 data/，故锚定在此常量区（CLAUDE.md 编码规范的允许落点）；
# 赛后若进 recipes.json 的 outputs 计数字段，改表即改行为。
const OUTPUT_COUNTS: Dictionary = {"h2": 2, "o2": 1}
const FALLBACK_OUTPUT_COUNT: int = 1

# 没有纯净水时提示先过滤（sys_filter：净水四步）。
const TIP_NEED_CLEAN_WATER: String = "sys_filter"

# D4 裁决（2026-08-02）：电解成功额外灌装 1 个氧气瓶（"氧气可以制备"，SPEC-02 §5 道具表）。
# 与 OUTPUT_COUNTS 同理锚定常量区（白名单不含 balance.json）；赛后若进数据表，改表即改行为。
const BONUS_ITEM_ID: String = "oxygen_tank"
const BONUS_ITEM_COUNT: int = 1

# ==== 逻辑区 ====

func interact(player: Node) -> void:
	var inventory: RefCounted = _inventory_of(player)
	if inventory == null or not bool(inventory.has_item(INPUT_ID, 1)):
		_show_tip(TIP_NEED_CLEAN_WATER)
		return
	var db: Node = _recipe_db()
	if db == null:
		push_warning("[facility] RecipeDB 不可用，电解未执行")
		return
	var result: Dictionary = db.try_craft([INPUT_ID], TOOL_ID, CONDITION_ID)
	if not bool(result.get("success", false)):
		# 数据表缺失/配方被改坏时不消耗材料，只警告（NFR-06：单模块故障不扩散）。
		push_warning("[facility] 电解配方匹配失败：%s" % str(result.get("fail_reason", "")))
		return
	inventory.remove_item(INPUT_ID, 1)
	for output_id: Variant in (result.get("outputs", []) as Array):
		var id: String = str(output_id)
		inventory.add_item(id, int(OUTPUT_COUNTS.get(id, FALLBACK_OUTPUT_COUNT)))
	# D4：电解成功额外灌装氧气瓶（氧气可制备的具象化，SPEC-02 §5 来源列）。
	inventory.add_item(BONUS_ITEM_ID, BONUS_ITEM_COUNT)
	_show_tip(_unlock_tip_id(db))


# 字幕 id 来自配方数据（unlock_tip 字段）；缺字段时不显示，不硬编码。
func _unlock_tip_id(db: Node) -> String:
	var recipe: Dictionary = db.get_recipe(RECIPE_ID)
	var tip_id: String = str(recipe.get("unlock_tip", ""))
	if tip_id.is_empty():
		push_warning("[facility] 配方 %s 缺 unlock_tip 字段" % RECIPE_ID)
	return tip_id
