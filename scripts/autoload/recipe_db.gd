# RecipeDB（SPEC-03 §4，FR-G-04/G-06/G-07）：物质表与配方表的查询与匹配。
# 匹配规则 1~5 见 SPEC-03 §4；失败文案按 reason 分池确定性轮转（SPEC-01 FR-G-07 判定口径），
# 不用 randi()——SPEC-06 §3 要求随机可预测。
extends Node

# ==== 常量区 ====

const EMPTY_CRAFT_RESULT: Dictionary = {
	"success": false,
	"recipe_id": "",
	"outputs": [],
	"card": {},
	"fail_reason": "no_match",
	"fail_tip_id": "",
	"requires_pure_check": false,
}

const REASON_NO_MATCH: String = "no_match"
const REASON_WRONG_CONDITION: String = "wrong_condition"
const REASON_NEEDS_PURITY: String = "needs_purity_check"

# 卡片底行文案在 tips.json 的这一条（SPEC-05 §3.4）。
const CARD_FOOTER_TIP_ID: String = "card_footer"

const KEY_ID: String = "id"
const KEY_INPUTS: String = "inputs"
const KEY_TOOL: String = "tool"
const KEY_CONDITION: String = "condition"
const KEY_OUTPUTS: String = "outputs"
const KEY_REASON: String = "reason"
const KEY_TEXT: String = "text"
const KEY_REQUIRES_PURE: String = "requires_pure_check"

const FLAG_PURITY: String = "purity_check_unlocked"

# 铜+酸彩蛋（FR-G-07 口径，包B-A7）：fail_copper_acid 不进通用 no_match 轮转池，
# 仅当输入确实是铜+酸组合时确定性返回。校验器要求 reason 枚举不变，故数据表不动、引擎分流。
const EASTER_EGG_FAIL_ID: String = "fail_copper_acid"
const COPPER_ID: String = "cu"
const ACID_ID: String = "hcl"

# ==== 逻辑区 ====

var _substances: Array = []
var _substances_by_id: Dictionary = {}
var _recipes: Array = []
var _recipes_by_id: Dictionary = {}
var _fail_messages: Array = []
var _fail_by_id: Dictionary = {}
var _fail_pools: Dictionary = {}
var _rotation: Dictionary = {}
var _card_footer: String = ""
var _unlocked: Array[String] = []


func _ready() -> void:
	reload()

func reload() -> void:
	_substances = DataLoader.load_table("substances.json", TYPE_ARRAY, [])
	_substances_by_id = DataLoader.index_by_id(_substances)
	_recipes = DataLoader.load_table("recipes.json", TYPE_ARRAY, [])
	_recipes_by_id = DataLoader.index_by_id(_recipes)
	_fail_messages = DataLoader.load_table("fail_messages.json", TYPE_ARRAY, [])
	_fail_by_id = DataLoader.index_by_id(_fail_messages)
	_build_fail_pools()
	_load_card_footer()
	reset_rotation()


# 按 reason 把失败文案分池：池间绝不混用（FR-G-07 AC1）。
func _build_fail_pools() -> void:
	_fail_pools = {}
	for row: Variant in _fail_messages:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = row
		var reason: String = str(dict.get(KEY_REASON, ""))
		var id: String = str(dict.get(KEY_ID, ""))
		if reason.is_empty() or id.is_empty():
			continue
		if id == EASTER_EGG_FAIL_ID:
			# 彩蛋文案不进通用轮转池（包B-A7）：铜+酸组合由 _fail_no_match 特判返回。
			continue
		var pool: Array = _fail_pools.get(reason, [])
		pool.append(id)
		_fail_pools[reason] = pool


# 卡片底行取自 tips.json 的 card_footer（FR-G-06 AC2：不在代码里写死）。
func _load_card_footer() -> void:
	_card_footer = ""
	var rows: Array = DataLoader.load_table("tips.json", TYPE_ARRAY, [])
	var row: Dictionary = DataLoader.index_by_id(rows).get(CARD_FOOTER_TIP_ID, {})
	if row.is_empty():
		push_warning("[recipe] tips.json 缺 %s（卡片底行为空）" % CARD_FOOTER_TIP_ID)
		return
	_card_footer = str(row.get(KEY_TEXT, ""))


# 轮转计数器复位（测试/新开局用）：确定性轮转的可预测性靠它保证。
func reset_rotation() -> void:
	_rotation = {}


# 已解锁配方清空（测试/新开局用）。这是玩家进度而非表数据，故不并入 reload()。
func reset_unlocked() -> void:
	_unlocked.clear()


func get_substance(id: String) -> Dictionary:
	return _substances_by_id.get(id, {})


func all_substances() -> Array[Dictionary]:
	return _dict_rows(_substances)


func get_recipe(id: String) -> Dictionary:
	return _recipes_by_id.get(id, {})


func all_recipes() -> Array[Dictionary]:
	return _dict_rows(_recipes)


func all_fail_messages() -> Array[Dictionary]:
	return _dict_rows(_fail_messages)


# 按 fail_tip_id 取失败文案记录（SPEC-03 §4）；不存在返回空字典。
func get_fail_message(fail_id: String) -> Dictionary:
	return _fail_by_id.get(fail_id, {})


func unlocked_recipes() -> Array[String]:
	return _unlocked.duplicate()


func _dict_rows(rows: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Variant in rows:
		if typeof(row) == TYPE_DICTIONARY:
			out.append(row)
	return out


# 核心匹配（SPEC-03 §4 规则 1~5）。
func try_craft(items: Array, tool: String, condition: String) -> Dictionary:
	var wanted: Array[String] = _normalize_items(items)
	if wanted.is_empty():
		return _fail(REASON_NO_MATCH)

	# 规则 1：materials 排序后比较，顺序无关。先按材料筛出候选，再看器材/条件。
	var material_hit: bool = false
	for recipe: Dictionary in all_recipes():
		if _sorted_inputs(recipe) != wanted:
			continue
		material_hit = true
		if str(recipe.get(KEY_TOOL, "")) != tool or str(recipe.get(KEY_CONDITION, "")) != condition:
			continue
		return _resolve_hit(recipe)

	# 规则 2：材料对但器材/条件都不符 → wrong_condition；规则 4：材料本身不匹配 → no_match。
	if material_hit:
		return _fail(REASON_WRONG_CONDITION)
	return _fail_no_match(wanted)


# no_match 的文案裁决（包B-A7）：铜+酸组合确定性返回专属彩蛋（不消耗通用池轮转），
# 其余组合走通用 no_match 轮转池。
func _fail_no_match(wanted: Array[String]) -> Dictionary:
	if wanted.has(COPPER_ID) and wanted.has(ACID_ID):
		var result: Dictionary = EMPTY_CRAFT_RESULT.duplicate(true)
		result["fail_reason"] = REASON_NO_MATCH
		result["fail_tip_id"] = EASTER_EGG_FAIL_ID
		return result
	return _fail(REASON_NO_MATCH)


# 命中三元组后的裁决：规则 3（未验纯）优先于成功，规则 5 登记解锁。
func _resolve_hit(recipe: Dictionary) -> Dictionary:
	var recipe_id: String = str(recipe.get(KEY_ID, ""))
	if bool(recipe.get(KEY_REQUIRES_PURE, false)) and not _purity_unlocked():
		# 这条路径由 FR-G-08 爆炸事件接管（字幕 sys_explosion_warn），不取失败池文案。
		var blocked: Dictionary = EMPTY_CRAFT_RESULT.duplicate(true)
		blocked["recipe_id"] = recipe_id
		blocked["fail_reason"] = REASON_NEEDS_PURITY
		blocked[KEY_REQUIRES_PURE] = true
		return blocked
	mark_unlocked(recipe_id)
	var result: Dictionary = EMPTY_CRAFT_RESULT.duplicate(true)
	result["success"] = true
	result["recipe_id"] = recipe_id
	result["outputs"] = (recipe.get(KEY_OUTPUTS, []) as Array).duplicate()
	result["card"] = build_card(recipe)
	result["fail_reason"] = ""
	return result


# 卡片五字段全部来自数据表（FR-G-06 AC1），底行来自 tips.json 的 card_footer（AC2）。
func build_card(recipe: Dictionary) -> Dictionary:
	return {
		"title": str(recipe.get("card_title", "")),
		"equation": str(recipe.get("equation", "")),
		"body": str(recipe.get("card_body", "")),
		"application": str(recipe.get("card_application", "")),
		"footer": _card_footer,
	}


# 组装失败结果并按 reason 取一条轮转文案。
func _fail(reason: String) -> Dictionary:
	var result: Dictionary = EMPTY_CRAFT_RESULT.duplicate(true)
	result["fail_reason"] = reason
	result["fail_tip_id"] = _next_fail_tip_id(reason)
	return result


# 确定性轮转（FR-G-07 AC2）：每个 reason 一个计数器取模池长度，各池互不干扰。
func _next_fail_tip_id(reason: String) -> String:
	var pool: Array = _fail_pools.get(reason, [])
	if pool.is_empty():
		push_warning("[recipe] 失败文案池为空：%s" % reason)
		return ""
	var cursor: int = int(_rotation.get(reason, 0))
	_rotation[reason] = cursor + 1
	return str(pool[cursor % pool.size()])


# 材料归一化：去掉空串、转字符串、排序（规则 1 的前提）。
func _normalize_items(items: Array) -> Array[String]:
	var out: Array[String] = []
	for item: Variant in items:
		var id: String = str(item)
		if id.is_empty():
			continue
		out.append(id)
	out.sort()
	return out


func _sorted_inputs(recipe: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for input_id: Variant in (recipe.get(KEY_INPUTS, []) as Array):
		out.append(str(input_id))
	out.sort()
	return out


# 规则 3 的判定源是 GameManager 的全局标记，RecipeDB 自己不存这个状态。
func _purity_unlocked() -> bool:
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm == null:
		return false
	return bool(gm.get_flag(FLAG_PURITY))


# 成功合成后登记为已解锁（规则 5，图鉴用）。
func mark_unlocked(recipe_id: String) -> void:
	if recipe_id.is_empty() or _unlocked.has(recipe_id):
		return
	_unlocked.append(recipe_id)
