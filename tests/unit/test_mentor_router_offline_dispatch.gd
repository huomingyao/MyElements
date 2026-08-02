# 包A-导师链 A2 修复（FR-M-04 AC2 / SPEC-05 §4.3）：
# 离线时班主任首条回复必须是 mentors.json 里 dispatch[*].line 的调度语（带 @ 派活），
# qa_fallback 答案只由被派导师讲——班主任不许直接讲化学、双方不许重复输出同一答案。
# 回复来源用 set_reply_provider 注入（SPEC-06 §3），测试不发任何网络请求。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const ROUTER_PATH: String = "res://scripts/mentor/mentor_router.gd"

const MONITOR_ID: String = "monitor"
const KEY_MENTOR_ID: String = "mentor_id"
const KEY_TEXT: String = "text"
const KEY_OFFLINE: String = "offline"

var router: RefCounted = null


func before_each() -> void:
	if not ResourceLoader.exists(ROUTER_PATH):
		fail_test("尚未实现 %s" % ROUTER_PATH)
		return
	router = (load(ROUTER_PATH) as GDScript).new()
	assert_not_null(router, "MentorRouter 应可直接实例化（SPEC-03 §6.1）")


# 从数据表取某分类的调度语——断言基准来自 mentors.json，不在测试里另写一份文案。
func _dispatch_line(category: String) -> String:
	for row in Fixture.rows_of("mentors.json"):
		if str(row.get("id", "")) != MONITOR_ID:
			continue
		for entry_value in row.get("dispatch", []) as Array:
			var entry: Dictionary = entry_value
			if str(entry.get("category", "")) == category:
				return str(entry.get("line", ""))
	return ""


# 离线来源：自报 offline=true 且文本非空——正是 LLMClient._offline_reply() 的返回形状
# （qa_fallback 答案 + 离线角标），A2 死路的触发条件。
func _use_offline_provider(answer: String) -> void:
	router.set_reply_provider(func(_mentor_id: String, _q: String) -> Dictionary:
		return {KEY_TEXT: answer, KEY_OFFLINE: true})


func _text_of(message: Variant) -> String:
	return str((message as Dictionary).get(KEY_TEXT, ""))


# 核心回归：离线时班主任那条等于数据表调度语，而不是 qa 答案（修复前必失败）。
func test_offline_monitor_speaks_dispatch_line_not_qa_answer() -> void:
	if router == null:
		return
	_use_offline_provider("氢气混有空气时点燃会爆炸。2H₂+O₂=点燃=2H₂O（离线模式）")
	var messages: Array = await router.handle_message("为什么氢气会爆炸")
	assert_gt(messages.size(), 0, "应有回复")
	if messages.is_empty():
		return
	var monitor_msg: Dictionary = messages[0]
	assert_eq(str(monitor_msg.get(KEY_MENTOR_ID, "")), MONITOR_ID, "首条仍来自班主任")
	assert_eq(
		_text_of(monitor_msg), _dispatch_line("chemistry"),
		"离线班主任首条应是 mentors.json 的调度语（SPEC-05 §4.3），不是 qa 答案"
	)
	assert_true(bool(monitor_msg.get(KEY_OFFLINE, false)), "调度语属离线路径，offline 应为 true")


# FR-M-04 AC2：离线调度语带 @ 派活——第二条来自化学老师，链条完整。
func test_offline_dispatch_line_drives_the_chain() -> void:
	if router == null:
		return
	_use_offline_provider("某答案（离线模式）")
	var messages: Array = await router.handle_message("为什么氢气会爆炸")
	assert_eq(messages.size(), 2, "离线链 = 班主任调度语 + 被派导师答疑")
	if messages.size() < 2:
		return
	assert_eq(
		str((messages[1] as Dictionary).get(KEY_MENTOR_ID, "")), "chem",
		"化学类问题离线时应派给化学老师"
	)


# 被派导师的回复才走 qa_fallback 答案 + 离线标记（FR-M-08 AC3 角标由 LLMClient 追加）。
func test_offline_dispatched_mentor_carries_qa_answer_and_offline_flag() -> void:
	if router == null:
		return
	var answer: String = "氢气混有空气时点燃会爆炸。2H₂+O₂=点燃=2H₂O（离线模式）"
	_use_offline_provider(answer)
	var messages: Array = await router.handle_message("为什么氢气会爆炸")
	assert_eq(messages.size(), 2, "应有班主任 + 化学老师两条")
	if messages.size() < 2:
		return
	var chem_msg: Dictionary = messages[1]
	assert_eq(_text_of(chem_msg), answer, "被派导师才讲 qa_fallback 答案")
	assert_true(bool(chem_msg.get(KEY_OFFLINE, false)), "被派导师的离线标记应透传")


# 修复前的直接症状：班主任与被派导师重复输出同一 qa 答案。修后两者文本必须不同。
func test_offline_monitor_never_duplicates_dispatched_answer() -> void:
	if router == null:
		return
	var answer: String = "统一的兜底答案文本（离线模式）"
	_use_offline_provider(answer)
	var messages: Array = await router.handle_message("为什么氢气会爆炸")
	assert_eq(messages.size(), 2, "应有两条消息")
	if messages.size() < 2:
		return
	assert_ne(
		_text_of(messages[0]), _text_of(messages[1]),
		"班主任调度语与被派导师的答案不许是同一段文本"
	)


# SPEC-05 §4.3：四个分类的调度语模板在离线路径全部可达（修复前四条全死路）。
func test_offline_dispatch_lines_reachable_for_all_categories() -> void:
	if router == null:
		return
	_use_offline_provider("任意答案（离线模式）")
	var cases: Dictionary = {
		"有个怪过来了": "combat",
		"方程式怎么复习，我总是记不住": "learning",
		"氢气怎么验纯": "chemistry",
		"今天午饭吃什么": "other",
	}
	for question_value in cases:
		var question: String = str(question_value)
		var category: String = str(cases[question])
		var line: String = _dispatch_line(category)
		assert_false(line.is_empty(), "mentors.json 应有 %s 分类的调度语" % category)
		var messages: Array = await router.handle_message(question)
		assert_gt(messages.size(), 0, "「%s」应有回复" % question)
		if messages.is_empty():
			continue
		assert_eq(
			_text_of(messages[0]), line,
			"「%s」离线首条应是 %s 分类的调度语" % [question, category]
		)


# 在线路径回归：班主任说来源原文（LLM 的调度产出），不被替换成数据表调度语。
func test_online_monitor_speaks_source_text_unchanged() -> void:
	if router == null:
		return
	router.set_reply_provider(func(_mentor_id: String, _q: String) -> Dictionary:
		return {KEY_TEXT: "别慌。@化学老师 你来讲！", KEY_OFFLINE: false})
	var messages: Array = await router.handle_message("为什么氢气会爆炸")
	assert_gt(messages.size(), 0, "应有回复")
	if messages.is_empty():
		return
	assert_eq(
		_text_of(messages[0]), "别慌。@化学老师 你来讲！",
		"在线时班主任文本不许被替换"
	)
	assert_false(bool((messages[0] as Dictionary).get(KEY_OFFLINE, true)), "在线时 offline 应为 false")
