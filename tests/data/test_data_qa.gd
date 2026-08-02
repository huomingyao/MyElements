# UT-D05 / FR-D-05：qa_fallback.json ≥20 条（当前 25 条）、answer 非空、
# 涉及反应的答案含化学方程式。
# 断言依据：SPEC-04 §7 校验规则 + SPEC-05 §5 内容表。
# 第 25 条是零命中兜底行：keywords 为空数组，永不参与包含匹配（SPEC-04 §7 兜底行约定），
# 它的存在让零命中话术也留在数据表里，不必硬编码进代码（NFR-04）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const MIN_COUNT: int = 20
const EXPECTED_COUNT: int = 25
const MENTOR_IDS: Array[String] = ["chem", "monitor", "assistant", "think"]
const OFFLINE_BADGE: String = "（离线模式）"
const EQUATION_MARKS: Array[String] = ["=", "→"]

# 零命中兜底行（SPEC-05 §5 末）：keywords 必须为空，其余行必须非空。
const FALLBACK_ID: String = "qa_no_match"
const FALLBACK_MENTOR_ID: String = "monitor"

# SPEC-05 §5 表格顺序（22 条化学知识 + 2 条战斗补充 + 1 条零命中兜底）。
const SPEC_IDS: Array[String] = [
	"qa_h2_explosion", "qa_o2", "qa_co", "qa_burn_condition", "qa_extinguish",
	"qa_water_purify", "qa_electrolysis", "qa_catalyst", "qa_metal_activity", "qa_rust",
	"qa_neutralize", "qa_ph", "qa_co2_test", "qa_metathesis", "qa_mass_conservation",
	"qa_nutrition", "qa_hardwater", "qa_salt_purify", "qa_allotrope", "qa_air",
	"qa_make_o2", "qa_next_step", "qa_fight_co", "qa_fight_acid", "qa_no_match",
]

# SPEC-05 §5：id -> [keywords..., mentor_id]，关键词按表中「/」拆分。
const SPEC_KEYWORDS_MENTOR: Dictionary = {
	"qa_h2_explosion": [["氢气", "爆炸", "验纯"], "chem"],
	"qa_o2": [["氧气", "性质", "助燃"], "chem"],
	"qa_co": [["一氧化碳", "煤气", "中毒"], "chem"],
	"qa_burn_condition": [["燃烧", "条件", "着火"], "chem"],
	"qa_extinguish": [["灭火", "原理"], "chem"],
	"qa_water_purify": [["水", "净化", "过滤"], "chem"],
	"qa_electrolysis": [["电解水", "正氧负氢"], "chem"],
	"qa_catalyst": [["催化剂", "二氧化锰"], "chem"],
	"qa_metal_activity": [["金属活动性", "置换"], "chem"],
	"qa_rust": [["铁生锈", "防锈"], "chem"],
	"qa_neutralize": [["中和", "酸碱"], "chem"],
	"qa_ph": [["pH", "酸碱度", "石蕊"], "chem"],
	"qa_co2_test": [["二氧化碳", "检验", "石灰水"], "chem"],
	"qa_metathesis": [["复分解", "条件"], "chem"],
	"qa_mass_conservation": [["质量守恒", "配平"], "chem"],
	"qa_nutrition": [["营养素", "食物"], "chem"],
	"qa_hardwater": [["硬水", "软水", "肥皂"], "chem"],
	"qa_salt_purify": [["粗盐", "提纯", "食盐"], "chem"],
	"qa_allotrope": [["同素异形体", "金刚石", "石墨"], "chem"],
	"qa_air": [["空气成分", "氮气"], "chem"],
	"qa_make_o2": [["实验室制氧气"], "chem"],
	"qa_next_step": [["下一步", "怎么办", "该做什么"], "assistant"],
	"qa_fight_co": [["CO幽灵", "幽灵", "灰色怪"], "think"],
	"qa_fight_acid": [["酸雾", "酸雾怪", "黄绿"], "think"],
}

# SPEC-05 §5 中明确写出方程式的条目（答案必须含该方程式原文）。
const SPEC_EQUATIONS: Dictionary = {
	"qa_h2_explosion": "2H₂+O₂=点燃=2H₂O",
	"qa_co": "2C+O₂=点燃=2CO",
	"qa_electrolysis": "2H₂O=通电=2H₂↑+O₂↑",
	"qa_metal_activity": "Fe+CuSO₄=Cu+FeSO₄",
	"qa_neutralize": "HCl+NaOH=NaCl+H₂O",
	"qa_co2_test": "CO₂+Ca(OH)₂=CaCO₃↓+H₂O",
	"qa_fight_acid": "HCl+NaOH=NaCl+H₂O",
}

var _rows: Array[Dictionary] = []
var _by_id: Dictionary = {}


func before_each() -> void:
	_rows = Fixture.rows_of("qa_fallback.json")
	_by_id = {}
	for row in _rows:
		_by_id[str(row.get("id", ""))] = row


# AC1：条目数 ≥20，当前内容表提供 25 条（24 条可命中 + 1 条兜底）。
func test_qa_count_at_least_twenty_and_matches_spec() -> void:
	assert_gte(_rows.size(), MIN_COUNT, "qa_fallback.json 至少 20 条")
	assert_eq(_rows.size(), EXPECTED_COUNT, "SPEC-05 §5 当前提供 25 条")


# AC1：id 唯一，且集合与 SPEC-05 §5 一致。
func test_qa_ids_unique_and_match_spec() -> void:
	var seen: Dictionary = {}
	for row in _rows:
		var id: String = str(row.get("id", ""))
		assert_false(id.is_empty(), "存在 id 为空的问答条目")
		assert_false(seen.has(id), "重复 qa id：%s" % id)
		seen[id] = true
	for spec_id in SPEC_IDS:
		assert_true(seen.has(spec_id), "SPEC-05 §5 的条目缺失：%s" % spec_id)
	assert_eq(seen.size(), SPEC_IDS.size(), "qa id 集合与 SPEC-05 §5 不一致")


# AC2：keywords 是数组、每项非空字符串；answer 非空。
# 兜底行例外：keywords 必须为空数组（SPEC-04 §7），否则它会参与匹配。
func test_keywords_and_answers_non_empty() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var keywords: Variant = row.get("keywords", null)
		assert_eq(typeof(keywords), TYPE_ARRAY, "%s 的 keywords 必须是数组" % id)
		if id == FALLBACK_ID:
			assert_eq((keywords as Array).size(), 0, "兜底行 %s 的 keywords 必须为空" % id)
		else:
			assert_gt((keywords as Array).size(), 0, "%s 的 keywords 不能为空" % id)
		for keyword in (keywords as Array):
			assert_false(str(keyword).strip_edges().is_empty(), "%s 含空关键词" % id)
		assert_false(str(row.get("answer", "")).strip_edges().is_empty(), "%s 的 answer 为空" % id)


# 兜底行有且只有一条，且归班主任（SPEC-05 §5 末）。
func test_exactly_one_fallback_row_owned_by_monitor() -> void:
	var fallback_ids: Array[String] = []
	for row in _rows:
		if (row.get("keywords", []) as Array).is_empty():
			fallback_ids.append(str(row.get("id", "")))
	assert_eq(fallback_ids.size(), 1, "空 keywords 的兜底行应恰好一条：%s" % str(fallback_ids))
	assert_eq(fallback_ids, [FALLBACK_ID] as Array[String], "兜底行 id 应是 %s" % FALLBACK_ID)
	assert_eq(
		str(_by_id.get(FALLBACK_ID, {}).get("mentor_id", "")), FALLBACK_MENTOR_ID,
		"零命中话术归班主任（SPEC-05 §5）"
	)


# 关键词与 mentor_id 逐条对齐 SPEC-05 §5（匹配结果可复现的前提）。
func test_keywords_and_mentor_match_spec_verbatim() -> void:
	for id in SPEC_KEYWORDS_MENTOR:
		var row: Dictionary = _by_id.get(id, {})
		assert_false(row.is_empty(), "条目缺失：%s" % id)
		var expected: Array = SPEC_KEYWORDS_MENTOR[id]
		var expected_keywords: Array = expected[0]
		var actual_keywords: Array = row.get("keywords", []) as Array
		assert_eq(actual_keywords.size(), expected_keywords.size(), "%s 的关键词条数与 SPEC-05 §5 不一致" % id)
		for i in range(mini(actual_keywords.size(), expected_keywords.size())):
			assert_eq(str(actual_keywords[i]), str(expected_keywords[i]), "%s 的第 %d 个关键词不一致" % [id, i + 1])
		assert_eq(str(row.get("mentor_id", "")), str(expected[1]), "%s 的 mentor_id 与 SPEC-05 §5 不一致" % id)


# mentor_id 若填写必须在 mentors.json 中存在（交叉引用）。
func test_mentor_id_resolves_to_mentors_table() -> void:
	var mentor_ids: Dictionary = {}
	for mentor in Fixture.rows_of("mentors.json"):
		mentor_ids[str(mentor.get("id", ""))] = true
	for row in _rows:
		var mentor_id: String = str(row.get("mentor_id", ""))
		if mentor_id.is_empty():
			continue
		assert_true(
			mentor_ids.has(mentor_id),
			"%s 的 mentor_id 在 mentors.json 中不存在：%s" % [str(row.get("id", "")), mentor_id]
		)


# AC3：涉及反应的答案含化学方程式（SPEC-06 §4.5：含 = 或 →）。
func test_reaction_answers_contain_equations() -> void:
	for id in SPEC_EQUATIONS:
		var answer: String = str(_by_id.get(id, {}).get("answer", ""))
		var equation: String = str(SPEC_EQUATIONS[id])
		assert_true(answer.contains(equation), "%s 的 answer 缺方程式：%s" % [id, equation])
		var has_mark: bool = false
		for mark in EQUATION_MARKS:
			if answer.contains(mark):
				has_mark = true
		assert_true(has_mark, "%s 的 answer 缺方程式标记（= 或 →）" % id)


# 「（离线模式）」由调用方追加，不许写进 answer（SPEC-04 §7 匹配规则 5）。
func test_answers_do_not_embed_offline_badge() -> void:
	for row in _rows:
		var answer: String = str(row.get("answer", ""))
		assert_false(
			answer.contains(OFFLINE_BADGE),
			"%s 的 answer 不该内嵌离线角标" % str(row.get("id", ""))
		)


# 答案里不许出现 @ 调度语（离线回答已是终点，协作链不再转发）。
func test_answers_contain_no_at_dispatch() -> void:
	for row in _rows:
		var answer: String = str(row.get("answer", ""))
		assert_false(answer.contains("@"), "%s 的 answer 不该含 @ 调度语" % str(row.get("id", "")))
