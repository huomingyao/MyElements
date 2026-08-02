# UT-M09 / FR-M-09：离线兜底问答（SPEC-03 §6.3 + SPEC-04 §7 匹配规则）。
# AC1 命中关键词数最多者胜；AC2 平票取表中先出现者（确定可复现，不用随机）；
# AC3 零命中返回兜底行的 answer（SPEC-05 §5 末，keywords 为空数组的那一行）；
# AC4 分类器归 MentorRouter，本类只按关键词取答案，离线与联网共用同一条链。
# 「（离线模式）」由调用方追加，不许出现在 answer 里（SPEC-04 §7 匹配规则 5）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const QA_PATH: String = "res://scripts/mentor/qa_fallback.gd"
const FALLBACK_ID: String = "qa_no_match"
const OFFLINE_BADGE: String = "（离线模式）"

var _qa: RefCounted = null


func before_each() -> void:
	_qa = null
	if not ResourceLoader.exists(QA_PATH):
		fail_test("尚未实现 %s（FR-M-09 / SPEC-03 §6.3）" % QA_PATH)
		return
	_qa = (load(QA_PATH) as GDScript).new()
	assert_not_null(_qa, "QaFallback 应可直接实例化（SPEC-06 §3 可测性约束）")


# 缺实现或缺方法时记为断言失败并跳过，避免 before_each 崩掉后 GUT 误报通过。
func _skip_unless(method_names: Array) -> bool:
	if _qa == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not _qa.has_method(method_name):
			fail_test("QaFallback 应有 %s()（SPEC-03 §6.3）" % method_name)
			return true
	return false


func _answer_of(id: String) -> String:
	for row in Fixture.rows_of("qa_fallback.json"):
		if str(row.get("id", "")) == id:
			return str(row.get("answer", ""))
	return ""


# AC1：命中计数正确。空 keywords 恒不命中——兜底行因此只在零命中时被取用。
func test_match_score_counts_hits_and_empty_keywords_never_match() -> void:
	if _skip_unless(["match_score"]):
		return
	assert_eq(
		_qa.match_score("氢气爆炸前要验纯吗", ["氢气", "爆炸", "验纯"]), 3,
		"三个关键词全命中应计 3（AC1）"
	)
	assert_eq(_qa.match_score("氢气爆炸前要验纯吗", ["氧气", "助燃"]), 0, "一个都不含应计 0")
	assert_eq(_qa.match_score("怎么灭火", ["灭火", "原理"]), 1, "只含一个应计 1")
	assert_eq(_qa.match_score("怎么灭火", []), 0, "空 keywords 恒不命中（SPEC-04 §7 兜底行）")
	assert_eq(_qa.match_score("", ["灭火"]), 0, "空问题不命中任何关键词")
	assert_eq(_qa.match_score("怎么灭火", ["", "  "]), 0, "空白关键词不算命中（否则会命中一切）")


# AC1：命中数最多者胜出，不是"第一个命中者"胜出。
func test_answer_prefers_row_with_most_keyword_hits() -> void:
	if _skip_unless(["answer"]):
		return
	assert_eq(
		_qa.answer("氢气爆炸前要验纯吗"), _answer_of("qa_h2_explosion"),
		"三词全中应胜过只中一词的条目（AC1）"
	)
	assert_eq(_qa.answer("怎么灭火"), _answer_of("qa_extinguish"), "「灭火」应命中灭火原理")


# AC2：平票取表中先出现者。注入两行同分条目，结果必须稳定落在先出现的那行。
func test_tie_is_broken_by_table_order() -> void:
	if _skip_unless(["load_from", "answer"]):
		return
	_qa.load_from([
		{"id": "first", "keywords": ["硫"], "mentor_id": "chem", "answer": "先出现者"},
		{"id": "second", "keywords": ["硫"], "mentor_id": "chem", "answer": "后出现者"},
		{"id": FALLBACK_ID, "keywords": [], "mentor_id": "monitor", "answer": "兜底"},
	])
	for i in range(5):
		assert_eq(_qa.answer("硫在哪里"), "先出现者", "平票必须稳定取表中先出现者（AC2）")


# AC3：零命中返回兜底行的 answer——话术来自数据表，不是代码里的字面量。
func test_zero_hit_returns_fallback_row_answer() -> void:
	if _skip_unless(["answer"]):
		return
	var fallback: String = _answer_of(FALLBACK_ID)
	assert_false(fallback.strip_edges().is_empty(), "qa_fallback.json 应有兜底行 %s" % FALLBACK_ID)
	assert_eq(_qa.answer("请用英文背诵莎士比亚十四行诗"), fallback, "零命中应返回兜底行话术（AC3）")
	assert_eq(_qa.answer(""), fallback, "空问题也走兜底，不返回空串")
	assert_eq(_qa.answer("   "), fallback, "纯空白同样走兜底")


# 兜底行本身永不被关键词命中：它的 keywords 为空。
func test_fallback_row_is_never_matched_by_keywords() -> void:
	if _skip_unless(["load_from", "answer"]):
		return
	_qa.load_from([
		{"id": FALLBACK_ID, "keywords": [], "mentor_id": "monitor", "answer": "兜底"},
		{"id": "hit", "keywords": ["硫"], "mentor_id": "chem", "answer": "命中"},
	])
	assert_eq(_qa.answer("硫在哪里"), "命中", "兜底行在表首也不能抢走可命中的答案")


# 表里没有兜底行时不许崩，也不许凭空造话术——返回空串交调用方处置。
func test_missing_fallback_row_returns_empty_string() -> void:
	if _skip_unless(["load_from", "answer"]):
		return
	_qa.load_from([{"id": "hit", "keywords": ["硫"], "mentor_id": "chem", "answer": "命中"}])
	assert_eq(_qa.answer("与关键词无关的问题"), "", "无兜底行时返回空串，不硬编码话术（NFR-04）")
	_qa.load_from([])
	assert_eq(_qa.answer("任何问题"), "", "空表不崩且返回空串")


# 答案对应的导师 id 也要能取到（聊天框要显示是谁在说话）。
func test_mentor_id_of_matched_row_is_exposed() -> void:
	if _skip_unless(["load_from", "mentor_id_for"]):
		return
	_qa.load_from([
		{"id": "hit", "keywords": ["硫"], "mentor_id": "chem", "answer": "命中"},
		{"id": FALLBACK_ID, "keywords": [], "mentor_id": "monitor", "answer": "兜底"},
	])
	assert_eq(_qa.mentor_id_for("硫在哪里"), "chem", "命中行的 mentor_id")
	assert_eq(_qa.mentor_id_for("无关问题"), "monitor", "零命中归班主任（SPEC-05 §5）")


# 默认构造即读 data/qa_fallback.json，不必调用方手动注入（离线可用是 P0 铁律 2）。
func test_default_construction_loads_real_table() -> void:
	if _skip_unless(["answer"]):
		return
	assert_eq(
		_qa.answer("电解水正氧负氢是怎么回事"), _answer_of("qa_electrolysis"),
		"默认构造应已载入 data/qa_fallback.json"
	)


# 数据表里不许内嵌「（离线模式）」，角标由调用方追加（SPEC-04 §7 规则 5）。
func test_answers_never_embed_offline_badge() -> void:
	if _skip_unless(["answer"]):
		return
	var answer: String = _qa.answer("氢气爆炸前要验纯吗")
	assert_false(answer.is_empty(), "命中答案不应为空")
	assert_false(answer.contains(OFFLINE_BADGE), "答案不该内嵌离线角标，由调用方追加")
