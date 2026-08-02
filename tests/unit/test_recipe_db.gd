# UT-G04 / FR-G-04：配方匹配。11 条配方逐条正例 + 反例；材料顺序无关；
# wrong_condition 与 no_match 区分正确；未验纯返回 needs_purity_check；返回字段齐全；三元组无歧义。
# 契约见 SPEC-03 §4（try_craft 返回结构与匹配规则 1~5）。
extends GutTest

# 没有任何配方使用的器材与条件，用来构造「材料对但器材/条件不符」的反例。
const UNUSED_TOOL: String = "filter"
const UNUSED_CONDITION: String = "catalyst"

# try_craft 返回字典的契约字段（SPEC-03 §4，字段名不许改）。
const RESULT_KEYS: Array[String] = [
	"success", "recipe_id", "outputs", "card",
	"fail_reason", "fail_tip_id", "requires_pure_check",
]

# 卡片五字段（SPEC-03 §4 + FR-G-06 AC1/AC2）。
const CARD_KEYS: Array[String] = ["title", "equation", "body", "application", "footer"]

var db: Node = null
var gm: Node = null


func before_each() -> void:
	var root: Node = Engine.get_main_loop().root
	db = root.get_node_or_null(^"RecipeDB")
	gm = root.get_node_or_null(^"GameManager")
	assert_not_null(db, "RecipeDB autoload 必须存在")
	assert_not_null(gm, "GameManager autoload 必须存在")
	if db == null or gm == null:
		return
	# 先断言 TP-07 新增接口存在：否则脚本错误会中断 before_each，让后续测试假绿。
	assert_true(db.has_method("all_recipes"), "RecipeDB 必须有 all_recipes()")
	assert_true(db.has_method("get_fail_message"), "RecipeDB 必须有 get_fail_message()（SPEC-03 §4）")
	assert_true(db.has_method("reset_rotation"), "RecipeDB 必须有 reset_rotation()（失败文案轮转复位）")
	assert_true(db.has_method("reset_unlocked"), "RecipeDB 必须有 reset_unlocked()（已解锁进度复位）")
	if not (db.has_method("all_recipes") and db.has_method("reset_rotation")
			and db.has_method("reset_unlocked")):
		return
	# autoload 是单例，已解锁列表会跨测试残留，逐个测试复位以保证独立性。
	db.reload()
	db.reset_rotation()
	db.reset_unlocked()
	gm.set_flag("purity_check_unlocked", false)


# 取一条配方的材料副本并倒序，用来验证顺序无关（规则 1）。
func _reversed_inputs(recipe: Dictionary) -> Array:
	var items: Array = (recipe.get("inputs", []) as Array).duplicate()
	items.reverse()
	return items


# AC5 + SPEC-06 §4.2：11 条配方逐条正例。倒序传材料，顺带覆盖规则 1（顺序无关）。
func test_all_eleven_recipes_craft_successfully() -> void:
	var recipes: Array = db.all_recipes()
	assert_eq(recipes.size(), 12, "recipes.json 应有 12 条配方")
	# R4 需要验纯才能成功，先解锁，让本测试专注「逐条能合成」。
	gm.set_flag("purity_check_unlocked", true)
	for recipe: Dictionary in recipes:
		var id: String = str(recipe.get("id", ""))
		var result: Dictionary = db.try_craft(
			_reversed_inputs(recipe), str(recipe.get("tool", "")), str(recipe.get("condition", ""))
		)
		assert_true(bool(result.get("success", false)), "配方 %s 应能合成成功" % id)
		assert_eq(str(result.get("recipe_id", "")), id, "配方 %s 的 recipe_id" % id)
		assert_eq(result.get("outputs", []), recipe.get("outputs", []), "配方 %s 的产物" % id)
		assert_eq(str(result.get("fail_reason", "")), "", "成功时 fail_reason 应为空串（%s）" % id)
		assert_eq(str(result.get("fail_tip_id", "")), "", "成功时 fail_tip_id 应为空串（%s）" % id)


# AC1：返回字典七个契约字段一个不少（成功与失败两条路径都查）。
func test_result_has_all_contract_keys() -> void:
	var ok: Dictionary = db.try_craft(["stick", "s"], "portable", "ignite")
	var bad: Dictionary = db.try_craft(["stick", "stick"], "portable", "ignite")
	for key: String in RESULT_KEYS:
		assert_true(ok.has(key), "成功结果缺字段：%s" % key)
		assert_true(bad.has(key), "失败结果缺字段：%s" % key)


# FR-G-06 AC1/AC2：卡片五字段全部来自数据表，footer 固定为质量守恒那句。
func test_success_card_fields_come_from_data() -> void:
	var recipe: Dictionary = db.get_recipe("r_sulfur_torch")
	var result: Dictionary = db.try_craft(["s", "stick"], "portable", "ignite")
	var card: Dictionary = result.get("card", {})
	for key: String in CARD_KEYS:
		assert_true(card.has(key), "卡片缺字段：%s" % key)
	assert_eq(str(card.get("title", "")), str(recipe.get("card_title", "")), "卡片标题来自 card_title")
	assert_eq(str(card.get("equation", "")), str(recipe.get("equation", "")), "卡片方程式来自 equation")
	assert_eq(str(card.get("body", "")), str(recipe.get("card_body", "")), "卡片现象来自 card_body")
	assert_eq(
		str(card.get("application", "")), str(recipe.get("card_application", "")),
		"卡片应用来自 card_application"
	)
	assert_false(str(card.get("footer", "")).is_empty(), "卡片底行不应为空（card_footer）")


# FR-G-06 AC2：底行取自 tips.json 的 card_footer，不是代码里写死的中文。
func test_card_footer_comes_from_tips_table() -> void:
	var tip: Node = Engine.get_main_loop().root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if tip == null:
		return
	var result: Dictionary = db.try_craft(["s", "stick"], "portable", "ignite")
	var footer: String = str((result.get("card", {}) as Dictionary).get("footer", ""))
	assert_string_contains(footer, "质量守恒", "底行应是 card_footer 那句质量守恒")


# 规则 1：材料顺序不影响结果（AC2），三材料/两材料都按排序比较。
func test_input_order_does_not_matter() -> void:
	var a: Dictionary = db.try_craft(["hcl", "naoh"], "bench", "none")
	var b: Dictionary = db.try_craft(["naoh", "hcl"], "bench", "none")
	assert_true(bool(a.get("success", false)), "正序应成功")
	assert_true(bool(b.get("success", false)), "倒序也应成功")
	assert_eq(str(a.get("recipe_id", "")), str(b.get("recipe_id", "")), "两种顺序命中同一配方")


# 规则 2 / AC3：材料匹配但器材不符 → wrong_condition，不是 no_match。
func test_wrong_tool_yields_wrong_condition() -> void:
	var result: Dictionary = db.try_craft(["stick", "s"], UNUSED_TOOL, "ignite")
	assert_false(bool(result.get("success", false)), "器材不符不应成功")
	assert_eq(str(result.get("fail_reason", "")), "wrong_condition", "器材不符应报 wrong_condition")
	assert_eq(str(result.get("recipe_id", "")), "", "失败时 recipe_id 应为空串")
	assert_eq(result.get("outputs", []), [], "失败时 outputs 应为空数组")
	assert_eq(result.get("card", {}), {}, "失败时 card 应为空字典")


# 规则 2 / AC3：材料匹配但条件不符 → wrong_condition。
func test_wrong_condition_yields_wrong_condition() -> void:
	var result: Dictionary = db.try_craft(["stick", "s"], "portable", UNUSED_CONDITION)
	assert_false(bool(result.get("success", false)), "条件不符不应成功")
	assert_eq(str(result.get("fail_reason", "")), "wrong_condition", "条件不符应报 wrong_condition")


# 规则 4 / AC4：材料本身凑不出任何配方 → no_match（与 wrong_condition 区分开）。
func test_unknown_material_set_yields_no_match() -> void:
	var result: Dictionary = db.try_craft(["stick", "stick"], "bench", "none")
	assert_false(bool(result.get("success", false)), "无配方不应成功")
	assert_eq(str(result.get("fail_reason", "")), "no_match", "材料不匹配应报 no_match")
	assert_false(str(result.get("fail_tip_id", "")).is_empty(), "no_match 必须给失败文案 id")


# 空材料、空器材/条件等边界输入不崩溃，统一按 no_match 处理（防御性输入校验）。
func test_empty_and_malformed_input_is_no_match() -> void:
	for probe: Array in [[], [""], ["stick"]]:
		var result: Dictionary = db.try_craft(probe, "", "")
		assert_false(bool(result.get("success", false)), "非法输入 %s 不应成功" % [probe])
		assert_eq(str(result.get("fail_reason", "")), "no_match", "非法输入 %s 应报 no_match" % [probe])


# 规则 3 / FR-G-08：命中 R4 且未验纯 → needs_purity_check + requires_pure_check=true。
func test_hydrogen_burn_needs_purity_check_when_locked() -> void:
	gm.set_flag("purity_check_unlocked", false)
	var result: Dictionary = db.try_craft(["o2", "h2"], "portable", "ignite")
	assert_false(bool(result.get("success", false)), "未验纯点燃氢气不应直接成功")
	assert_eq(str(result.get("fail_reason", "")), "needs_purity_check", "应报 needs_purity_check")
	assert_true(bool(result.get("requires_pure_check", false)), "requires_pure_check 应为 true")
	assert_eq(str(result.get("recipe_id", "")), "r_hydrogen_burn", "需告知调用方命中的是 R4（爆炸事件用）")
	# 这条路径由 FR-G-08 爆炸事件接管（字幕 sys_explosion_warn），不走失败池文案。
	assert_eq(str(result.get("fail_tip_id", "")), "", "needs_purity_check 不应取失败池文案")


# 规则 3 / FR-G-09：验纯解锁后同样的三元组成功，且不再要求验纯。
func test_hydrogen_burn_succeeds_after_purity_unlocked() -> void:
	gm.set_flag("purity_check_unlocked", true)
	var result: Dictionary = db.try_craft(["h2", "o2"], "portable", "ignite")
	assert_true(bool(result.get("success", false)), "验纯后点燃氢气应成功")
	assert_eq(result.get("outputs", []), ["h2o"], "产物应是水")
	assert_false(bool(result.get("requires_pure_check", false)), "成功后不应再要求验纯")


# 规则 3 只作用于 R4：其他配方不受 purity_check_unlocked 影响。
func test_purity_flag_does_not_affect_other_recipes() -> void:
	gm.set_flag("purity_check_unlocked", false)
	var result: Dictionary = db.try_craft(["c"], "alcohol_lamp", "ignite")
	assert_true(bool(result.get("success", false)), "碳的充分燃烧与验纯无关，应成功")
	assert_false(bool(result.get("requires_pure_check", false)), "非 R4 不应要求验纯")


# 同材料同器材、仅条件不同的两条配方（R2/R3）必须各自命中，不许互相串味。
func test_same_inputs_different_condition_resolve_separately() -> void:
	var burn: Dictionary = db.try_craft(["c"], "alcohol_lamp", "ignite")
	var incomplete: Dictionary = db.try_craft(["c"], "alcohol_lamp", "low_oxygen")
	assert_eq(str(burn.get("recipe_id", "")), "r_carbon_burn", "ignite 应命中充分燃烧")
	assert_eq(str(incomplete.get("recipe_id", "")), "r_carbon_incomplete", "low_oxygen 应命中不充分燃烧")
	assert_eq(burn.get("outputs", []), ["co2"], "充分燃烧产物 CO₂")
	assert_eq(incomplete.get("outputs", []), ["co"], "不充分燃烧产物 CO")


# SPEC-04 §3：不存在两条配方拥有相同的 (inputs 排序, tool, condition) 三元组，否则匹配有歧义。
func test_recipe_triples_are_unambiguous() -> void:
	var seen: Dictionary = {}
	for recipe: Dictionary in db.all_recipes():
		var items: Array[String] = []
		for input_id: Variant in (recipe.get("inputs", []) as Array):
			items.append(str(input_id))
		items.sort()
		var key: String = "%s|%s|%s" % [
			"+".join(items), str(recipe.get("tool", "")), str(recipe.get("condition", "")),
		]
		assert_false(seen.has(key), "三元组重复：%s 与 %s" % [str(recipe.get("id", "")), str(seen.get(key, ""))])
		seen[key] = str(recipe.get("id", ""))


# 规则 5：成功后该 recipe_id 记入已解锁列表（图鉴用），失败不记。
func test_success_marks_recipe_unlocked() -> void:
	assert_false(db.unlocked_recipes().has("r_neutralize"), "初始不应已解锁")
	db.try_craft(["hcl", "naoh"], "bench", UNUSED_CONDITION)
	assert_false(db.unlocked_recipes().has("r_neutralize"), "失败不应记为已解锁")
	db.try_craft(["hcl", "naoh"], "bench", "none")
	assert_true(db.unlocked_recipes().has("r_neutralize"), "成功后应记为已解锁")


# 重复成功不产生重复解锁记录（图鉴不出现两行）。
func test_repeated_success_does_not_duplicate_unlock() -> void:
	db.try_craft(["hcl", "naoh"], "bench", "none")
	db.try_craft(["naoh", "hcl"], "bench", "none")
	var hits: int = 0
	for id: String in db.unlocked_recipes():
		if id == "r_neutralize":
			hits += 1
	assert_eq(hits, 1, "同一配方只应记一次")


# get_substance/get_recipe 对不存在 id 返回空字典（SPEC-03 §4），不崩溃。
func test_queries_return_empty_for_unknown_ids() -> void:
	assert_eq(db.get_recipe("r_nope"), {}, "不存在的配方返回空字典")
	assert_eq(db.get_substance("unobtainium"), {}, "不存在的物质返回空字典")
	assert_eq(db.get_fail_message("fail_nope"), {}, "不存在的失败文案返回空字典")


# all_substances 返回 17 条（图鉴用；HUD 计数 16 条由 FR-G-03 处理）。
func test_all_substances_has_seventeen_rows() -> void:
	assert_eq(db.all_substances().size(), 17, "substances.json 应有 17 条")


# ==== AC5 反例补齐（包B）：R5、R7~R12 每条约至少一个反例 ====
# 口径：材料对但器材/条件不符 → wrong_condition；缺一材料凑不出任何配方 → no_match。
# 正例已由 test_all_eleven_recipes_craft_successfully 逐条覆盖，这里只补反例。

func _assert_wrong_condition(items: Array, tool: String, condition: String, label: String) -> void:
	var result: Dictionary = db.try_craft(items, tool, condition)
	assert_false(bool(result.get("success", false)), "%s 不应成功" % label)
	assert_eq(str(result.get("fail_reason", "")), "wrong_condition",
		"%s 材料对但器材/条件不呼应报 wrong_condition" % label)


func _assert_no_match(items: Array, tool: String, condition: String, label: String) -> void:
	var result: Dictionary = db.try_craft(items, tool, condition)
	assert_false(bool(result.get("success", false)), "%s 不应成功" % label)
	assert_eq(str(result.get("fail_reason", "")), "no_match", "%s 缺一材料应报 no_match" % label)


# R5 电解水（h2o_clean / electrolyzer / electrify）：器材错、条件错各一例。
func test_r5_electrolysis_counter_examples() -> void:
	_assert_wrong_condition(["h2o_clean"], UNUSED_TOOL, "electrify", "R5 器材不符")
	_assert_wrong_condition(["h2o_clean"], "electrolyzer", UNUSED_CONDITION, "R5 条件不符")


# R7 实验室制 CO2（caco3+hcl / bench / none）：器材错 + 缺 hcl 各一例。
func test_r7_co2_lab_counter_examples() -> void:
	_assert_wrong_condition(["caco3", "hcl"], UNUSED_TOOL, "none", "R7 器材不符")
	_assert_no_match(["caco3"], "bench", "none", "R7 缺 hcl")


# R8 检验 CO2（co2+caoh2 / bench / none）：条件错 + 缺 caoh2 各一例。
func test_r8_co2_test_counter_examples() -> void:
	_assert_wrong_condition(["co2", "caoh2"], "bench", UNUSED_CONDITION, "R8 条件不符")
	_assert_no_match(["co2"], "bench", "none", "R8 缺 caoh2")


# R9 湿法炼铜（fe+cuso4 / bench / none）：条件错 + 缺 cuso4 各一例。
func test_r9_wet_copper_counter_examples() -> void:
	_assert_wrong_condition(["fe", "cuso4"], "bench", "ignite", "R9 条件不符")
	_assert_no_match(["fe"], "bench", "none", "R9 缺 cuso4")


# R10 灭火器原理（nahco3+hcl / bench / none）：条件错 + 缺 nahco3 各一例。
func test_r10_extinguisher_counter_examples() -> void:
	_assert_wrong_condition(["nahco3", "hcl"], "bench", "heat", "R10 条件不符")
	_assert_no_match(["hcl"], "bench", "none", "R10 缺 nahco3")


# R11 粗盐提纯（crude_salt / bench / three_step）：条件错、器材错各一例。
func test_r11_salt_purify_counter_examples() -> void:
	_assert_wrong_condition(["crude_salt"], "bench", "none", "R11 缺三步条件")
	_assert_wrong_condition(["crude_salt"], UNUSED_TOOL, "three_step", "R11 器材不符")


# R12 碳活化（c / alcohol_lamp / heat）：条件错、器材错各一例。
func test_r12_carbon_activate_counter_examples() -> void:
	_assert_wrong_condition(["c"], "alcohol_lamp", UNUSED_CONDITION, "R12 条件不符")
	_assert_wrong_condition(["c"], "bench", "heat", "R12 器材不符")

