# UT-D02 / FR-D-02：recipes.json 12 条、id 唯一、requires_pure_check 唯一、枚举合法、
# inputs/outputs 可解析、三元组无歧义、卡片四字段齐全。
# 断言依据：SPEC-04 §3 校验规则 + SPEC-05 §2 内容表。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const EXPECTED_COUNT: int = 12
const PURE_CHECK_RECIPE_ID: String = "r_hydrogen_burn"
const PHYSICAL_RECIPE_IDS: Array[String] = ["r_salt_purify", "r_carbon_activate"]
const PHYSICAL_EQUATION: String = "（物理过程，无化学方程式）"
const ID_PREFIX: String = "r_"
const TOOLS: Array[String] = ["portable", "alcohol_lamp", "bench", "electrolyzer", "filter"]
const CONDITIONS: Array[String] = [
	"none", "ignite", "heat", "electrify", "catalyst", "low_oxygen", "three_step",
]
const REQUIRED_FIELDS: Array[String] = [
	"id", "inputs", "tool", "condition", "outputs",
	"equation", "card_title", "card_body", "card_application",
]

# SPEC-05 §2 的 12 条 recipe id，顺序即 R1..R12。
const SPEC_IDS: Array[String] = [
	"r_sulfur_torch", "r_carbon_burn", "r_carbon_incomplete", "r_hydrogen_burn",
	"r_electrolysis", "r_neutralize", "r_co2_lab", "r_co2_test",
	"r_wet_copper", "r_extinguisher", "r_salt_purify", "r_carbon_activate",
]

# SPEC-05 §2 表格：id -> [方程式, tool, condition]。
const SPEC_EQUATION_TOOL_CONDITION: Dictionary = {
	"r_sulfur_torch": ["S + O₂ =点燃= SO₂", "portable", "ignite"],
	"r_carbon_burn": ["C + O₂ =点燃= CO₂", "alcohol_lamp", "ignite"],
	"r_carbon_incomplete": ["2C + O₂ =点燃= 2CO", "alcohol_lamp", "low_oxygen"],
	"r_hydrogen_burn": ["2H₂ + O₂ =点燃= 2H₂O", "portable", "ignite"],
	"r_electrolysis": ["2H₂O =通电= 2H₂↑ + O₂↑", "electrolyzer", "electrify"],
	"r_neutralize": ["HCl + NaOH = NaCl + H₂O", "bench", "none"],
	"r_co2_lab": ["CaCO₃ + 2HCl = CaCl₂ + H₂O + CO₂↑", "bench", "none"],
	"r_co2_test": ["CO₂ + Ca(OH)₂ = CaCO₃↓ + H₂O", "bench", "none"],
	"r_wet_copper": ["Fe + CuSO₄ = Cu + FeSO₄", "bench", "none"],
	"r_extinguisher": ["NaHCO₃ + HCl = NaCl + H₂O + CO₂↑", "bench", "none"],
	"r_salt_purify": [PHYSICAL_EQUATION, "bench", "three_step"],
	"r_carbon_activate": [PHYSICAL_EQUATION, "alcohol_lamp", "heat"],
}

# SPEC-05 §2「卡片标题」一行。
const SPEC_CARD_TITLES: Dictionary = {
	"r_sulfur_torch": "硫的燃烧",
	"r_carbon_burn": "碳的充分燃烧",
	"r_carbon_incomplete": "不充分燃烧的代价",
	"r_hydrogen_burn": "氢气的燃烧",
	"r_electrolysis": "电解水",
	"r_neutralize": "中和反应",
	"r_co2_lab": "实验室制二氧化碳",
	"r_co2_test": "检验二氧化碳",
	"r_wet_copper": "湿法炼铜",
	"r_extinguisher": "灭火器原理",
	"r_salt_purify": "粗盐提纯",
	"r_carbon_activate": "活性炭的活化",
}

# SPEC-05 §2「现实应用（card_application）」列表。
const SPEC_CARD_APPLICATIONS: Dictionary = {
	"r_sulfur_torch": "硫火把：夜晚照明与驱虫",
	"r_carbon_burn": "木炭取暖与烧烤，都是碳的充分燃烧",
	"r_carbon_incomplete": "煤炉不通风会产生一氧化碳——这就是煤气中毒",
	"r_hydrogen_burn": "氢能源：最清洁的燃料，燃料电池汽车已在路上",
	"r_electrolysis": "工业电解水制氢、制氧",
	"r_neutralize": "治胃酸过多、改良酸性土壤、处理酸性废水",
	"r_co2_lab": "实验室制 CO₂ 的标准方法",
	"r_co2_test": "检验二氧化碳的通用方法",
	"r_wet_copper": "古代湿法炼铜——比火法更早的冶金智慧",
	"r_extinguisher": "干粉灭火器就是这个原理",
	"r_salt_purify": "海水晒盐后的粗盐提纯，食盐从这里来",
	"r_carbon_activate": "防毒面具里的活性炭层，吸附毒气分子保护呼吸。",
}

var _rows: Array[Dictionary] = []


func before_each() -> void:
	_rows = Fixture.rows_of("recipes.json")


# AC1：恰好 12 条。
func test_recipe_count_is_twelve() -> void:
	assert_eq(_rows.size(), EXPECTED_COUNT, "recipes.json 必须恰好 12 条")


# AC1：id 唯一、r_ 前缀、集合与 SPEC-05 §2 一致。
func test_recipe_ids_unique_prefixed_and_match_spec() -> void:
	var seen: Dictionary = {}
	for row in _rows:
		var id: String = str(row.get("id", ""))
		assert_false(seen.has(id), "重复 recipe id：%s" % id)
		assert_true(id.begins_with(ID_PREFIX), "recipe id 必须以 %s 开头：%s" % [ID_PREFIX, id])
		seen[id] = true
	for spec_id in SPEC_IDS:
		assert_true(seen.has(spec_id), "SPEC-05 §2 的 recipe 缺失：%s" % spec_id)
	assert_eq(seen.size(), SPEC_IDS.size(), "recipe id 集合与 SPEC-05 §2 不一致")


# AC3：必填字段齐全非空。
func test_required_fields_present_and_non_empty() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		for field in REQUIRED_FIELDS:
			assert_true(row.has(field), "%s 缺字段 %s" % [id, field])
			var value: Variant = row.get(field, null)
			if typeof(value) == TYPE_STRING:
				assert_false((value as String).is_empty(), "%s 的 %s 为空" % [id, field])
			elif typeof(value) == TYPE_ARRAY:
				assert_gt((value as Array).size(), 0, "%s 的 %s 不能是空数组" % [id, field])


# AC2：有且仅有一条 requires_pure_check == true，且是 R4。
func test_exactly_one_recipe_requires_pure_check() -> void:
	var flagged: Array[String] = []
	for row in _rows:
		if row.get("requires_pure_check", false) == true:
			flagged.append(str(row.get("id", "")))
	assert_eq(flagged, [PURE_CHECK_RECIPE_ID] as Array[String], "只有 R4 可以 requires_pure_check=true")


# R11/R12 标记为物理过程，equation 用 SPEC-04 §3 规定的固定串。
func test_only_salt_purify_is_physical_with_placeholder_equation() -> void:
	var physical: Array[String] = []
	for row in _rows:
		if row.get("is_physical", false) == true:
			physical.append(str(row.get("id", "")))
	physical.sort()
	var expected_physical: Array[String] = PHYSICAL_RECIPE_IDS.duplicate()
	expected_physical.sort()
	assert_eq(physical, expected_physical, "只有 R11/R12 可以 is_physical=true")
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var equation: String = str(row.get("equation", ""))
		if PHYSICAL_RECIPE_IDS.has(id):
			assert_eq(equation, PHYSICAL_EQUATION, "%s 的 equation 必须是规定的物理过程串" % id)
		else:
			assert_ne(equation, PHYSICAL_EQUATION, "%s 不是物理过程，不该用占位方程式" % id)


# tool / condition 在枚举内，且与 SPEC-05 §2 表格一致。
func test_tool_and_condition_in_enum_and_match_spec() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var tool: String = str(row.get("tool", ""))
		var condition: String = str(row.get("condition", ""))
		assert_true(TOOLS.has(tool), "%s 的 tool 非法：%s" % [id, tool])
		assert_true(CONDITIONS.has(condition), "%s 的 condition 非法：%s" % [id, condition])
		var expected: Array = SPEC_EQUATION_TOOL_CONDITION.get(id, [])
		if expected.is_empty():
			continue
		assert_eq(tool, str(expected[1]), "%s 的 tool 与 SPEC-05 §2 不一致" % id)
		assert_eq(condition, str(expected[2]), "%s 的 condition 与 SPEC-05 §2 不一致" % id)


# 方程式用 Unicode 下标，不许出现 LaTeX 记号。
func test_equations_use_unicode_subscripts_not_latex() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var equation: String = str(row.get("equation", ""))
		assert_false(equation.contains("_"), "%s 的 equation 含 LaTeX 下标记号：%s" % [id, equation])
		assert_false(equation.contains("\\"), "%s 的 equation 含 LaTeX 反斜杠：%s" % [id, equation])
		assert_false(equation.contains("$"), "%s 的 equation 含 LaTeX 数学符号：%s" % [id, equation])


# 卡片标题与现实应用逐字符对齐 SPEC-05 §2。
func test_card_title_and_application_match_spec_verbatim() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		if SPEC_CARD_TITLES.has(id):
			assert_eq(
				str(row.get("card_title", "")),
				str(SPEC_CARD_TITLES[id]),
				"%s 的 card_title 与 SPEC-05 §2 不一致" % id
			)
		if SPEC_CARD_APPLICATIONS.has(id):
			assert_eq(
				str(row.get("card_application", "")),
				str(SPEC_CARD_APPLICATIONS[id]),
				"%s 的 card_application 与 SPEC-05 §2 不一致" % id
			)


# AC1：inputs/outputs 中每个 id 可在 substances 或 items 中解析。
func test_inputs_and_outputs_resolve_to_substances_or_items() -> void:
	var known: Dictionary = {}
	for row in Fixture.rows_of("substances.json"):
		known[str(row.get("id", ""))] = true
	for row in Fixture.rows_of("items.json"):
		known[str(row.get("id", ""))] = true
	for row in _rows:
		var id: String = str(row.get("id", ""))
		for input_id in (row.get("inputs", []) as Array):
			assert_true(known.has(str(input_id)), "%s 的 input 无法解析：%s" % [id, str(input_id)])
		for output_id in (row.get("outputs", []) as Array):
			assert_true(known.has(str(output_id)), "%s 的 output 无法解析：%s" % [id, str(output_id)])


# inputs 2~3 项、outputs ≥1 项（SPEC-04 §3 字段约束）。
func test_input_and_output_arity_within_spec() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var inputs: Array = row.get("inputs", []) as Array
		var outputs: Array = row.get("outputs", []) as Array
		assert_between(inputs.size(), 1, 3, "%s 的 inputs 数量应为 1~3 项" % id)
		assert_gt(outputs.size(), 0, "%s 的 outputs 至少 1 项" % id)


# 校验规则：不存在两条配方拥有相同的 (inputs 排序, tool, condition) 三元组。
func test_no_ambiguous_input_tool_condition_triples() -> void:
	var seen: Dictionary = {}
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var inputs: Array[String] = []
		for input_id in (row.get("inputs", []) as Array):
			inputs.append(str(input_id))
		inputs.sort()
		var key: String = "%s|%s|%s" % [
			"+".join(inputs), str(row.get("tool", "")), str(row.get("condition", "")),
		]
		assert_false(seen.has(key), "配方三元组歧义：%s 与 %s" % [str(seen.get(key, "")), id])
		seen[key] = id


# unlock_tip 若填写必须存在于 tips.json。
func test_unlock_tip_resolves_when_present() -> void:
	var tip_ids: Dictionary = {}
	for tip in Fixture.rows_of("tips.json"):
		tip_ids[str(tip.get("id", ""))] = true
	for row in _rows:
		var unlock_tip: String = str(row.get("unlock_tip", ""))
		if unlock_tip.is_empty():
			continue
		assert_true(
			tip_ids.has(unlock_tip),
			"%s 的 unlock_tip 在 tips.json 中不存在：%s" % [str(row.get("id", "")), unlock_tip]
		)


# fail_messages.json：reason 枚举合法，且每个 reason 至少两条以支持确定性轮换（FR-G-07 AC2 前提）。
func test_fail_messages_reasons_valid_and_rotatable() -> void:
	var rows: Array[Dictionary] = Fixture.rows_of("fail_messages.json")
	assert_gt(rows.size(), 0, "fail_messages.json 不能为空")
	var allowed: Array[String] = ["no_match", "wrong_condition"]
	var by_reason: Dictionary = {}
	var seen: Dictionary = {}
	for row in rows:
		var id: String = str(row.get("id", ""))
		assert_false(seen.has(id), "fail_messages 重复 id：%s" % id)
		seen[id] = true
		var reason: String = str(row.get("reason", ""))
		assert_true(allowed.has(reason), "%s 的 reason 非法：%s" % [id, reason])
		assert_false(str(row.get("text", "")).is_empty(), "%s 的 text 为空" % id)
		by_reason[reason] = int(by_reason.get(reason, 0)) + 1
	assert_gt(int(by_reason.get("no_match", 0)), 1, "no_match 需 ≥2 条以支持轮换")
	assert_gt(int(by_reason.get("wrong_condition", 0)), 1, "wrong_condition 需 ≥2 条以支持轮换")
