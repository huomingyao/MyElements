# UT-M08 / FR-M-08：超时与失败兜底（SPEC-03 §6.2）。
# AC1 超时 8 秒 + 重试 1 次，常量可在测试中调小；
# AC2 四种失败（超时/网络错/非 200/畸形 body）都走兜底且不抛未捕获异常；
# AC3 离线回答带「（离线模式）」；AC4 手动开关立即生效。
# 全程用注入的传输层，**不发真实请求**（TP-15 安全约束）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const BADGE_KEY: String = "chat_offline_badge"
const FALLBACK_ID: String = "qa_no_match"

# 传输层返回形状（SPEC-03 §6.2）：{result, code, body}。
const K_RESULT: String = "result"
const K_CODE: String = "code"
const K_BODY: String = "body"

var _llm: Node = null
var _calls: Array = []
var _saved_offline: bool = false
var _saved_timeout: float = 0.0
var _saved_retry: int = 0


func before_each() -> void:
	_calls = []
	_llm = Engine.get_main_loop().root.get_node_or_null(^"LLMClient")
	assert_not_null(_llm, "LLMClient autoload 必须存在")
	if _llm == null:
		return
	for method_name in ["set_transport", "attempt_count", "set_timeout_seconds", "set_retry_count"]:
		if not _llm.has_method(method_name):
			fail_test("LLMClient 应有 %s()（SPEC-03 §6.2 非契约辅助）" % method_name)
			_llm = null
			return
	_saved_offline = _llm.is_offline()
	_saved_timeout = _llm.timeout_seconds()
	_saved_retry = _llm.retry_count()
	# 测试里把超时调到极小，避免单测等 8 秒（FR-M-08 AC1「常量可在测试中调小」）。
	_llm.set_timeout_seconds(0.05)
	_llm.set_offline(false)


func after_each() -> void:
	if _llm == null:
		return
	_llm.set_transport(Callable())
	_llm.set_timeout_seconds(_saved_timeout)
	_llm.set_retry_count(_saved_retry)
	_llm.set_offline(_saved_offline)


# 记录每次发包并返回固定结果，测试据此断言重试次数。
func _respond_with(response: Dictionary) -> Callable:
	return func(payload: Dictionary) -> Dictionary:
		_calls.append(payload)
		return response


func _ok_body(text: String) -> String:
	return JSON.stringify({"choices": [{"message": {"content": text}}]})


func _badge() -> String:
	return str(Fixture.read_object("ui_strings.json").get(BADGE_KEY, ""))


func _fallback_answer() -> String:
	for row in Fixture.rows_of("qa_fallback.json"):
		if str(row.get("id", "")) == FALLBACK_ID:
			return str(row.get("answer", ""))
	return ""


# 四种失败逐一验证：都返回兜底文本、都带角标、都不抛异常、都进离线模式。
func _assert_falls_back(response: Dictionary, label: String) -> void:
	_calls = []
	_llm.set_offline(false)
	_llm.set_retry_count(0)
	_llm.set_transport(_respond_with(response))
	var reply: String = await _llm.ask("chem", "氢气怎么验纯", [])
	assert_true(reply.contains(_badge()), "%s：回复应带离线角标（AC3）→ %s" % [label, reply])
	assert_true(_llm.is_offline(), "%s：失败后应转入离线模式" % label)
	assert_gt(reply.strip_edges().length(), _badge().length(), "%s：兜底回复不能只有角标" % label)


# AC2：超时走兜底。
func test_timeout_falls_back() -> void:
	if _llm == null:
		return
	await _assert_falls_back(
		{K_RESULT: HTTPRequest.RESULT_TIMEOUT, K_CODE: 0, K_BODY: ""}, "超时"
	)


# AC2：连不上（网络错）走兜底。
func test_network_error_falls_back() -> void:
	if _llm == null:
		return
	await _assert_falls_back(
		{K_RESULT: HTTPRequest.RESULT_CANT_CONNECT, K_CODE: 0, K_BODY: ""}, "网络错"
	)


# AC2：非 200（如 401 key 失效、429 限流）走兜底。
func test_non_200_falls_back() -> void:
	if _llm == null:
		return
	await _assert_falls_back(
		{K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 401, K_BODY: "{}"}, "非 200"
	)
	await _assert_falls_back(
		{K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 429, K_BODY: "{}"}, "限流"
	)


# AC2：畸形 body（非法 JSON / 缺 choices / content 为空）走兜底。
func test_malformed_body_falls_back() -> void:
	if _llm == null:
		return
	await _assert_falls_back(
		{K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 200, K_BODY: "not a json at all"},
		"非法 JSON"
	)
	await _assert_falls_back(
		{K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 200, K_BODY: '{"choices": []}'},
		"缺 choices"
	)
	await _assert_falls_back(
		{K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 200, K_BODY: _ok_body("   ")},
		"content 空白"
	)


# AC1：失败后重试次数受 retry_count 限制——1 次重试即总共发 2 包，不许无限重试。
func test_retry_count_limits_attempts() -> void:
	if _llm == null:
		return
	_calls = []
	_llm.set_retry_count(1)
	_llm.set_transport(_respond_with({K_RESULT: HTTPRequest.RESULT_TIMEOUT, K_CODE: 0, K_BODY: ""}))
	await _llm.ask("chem", "氢气怎么验纯", [])
	assert_eq(_calls.size(), 2, "重试 1 次 = 总共发 2 包（AC1）")
	assert_eq(_llm.attempt_count(), 2, "attempt_count 应等于实际发包次数")

	_calls = []
	_llm.set_offline(false)
	_llm.set_retry_count(0)
	await _llm.ask("chem", "氢气怎么验纯", [])
	assert_eq(_calls.size(), 1, "retry_count=0 时只发 1 包")


# AC1：成功时不重试，也不进离线模式。
func test_success_does_not_retry_and_stays_online() -> void:
	if _llm == null:
		return
	_calls = []
	_llm.set_retry_count(1)
	_llm.set_transport(_respond_with(
		{K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 200, K_BODY: _ok_body("配平了吗？")}
	))
	var reply: String = await _llm.ask("chem", "氢气怎么验纯", [])
	assert_eq(reply, "配平了吗？", "成功时返回 content 原文")
	assert_eq(_calls.size(), 1, "成功不该重试")
	assert_false(_llm.is_offline(), "成功不该转离线")
	assert_false(reply.contains(_badge()), "联网回复不该带离线角标")


# AC1：第一包失败、重试成功时返回成功结果，且不进离线模式。
func test_retry_success_recovers() -> void:
	if _llm == null:
		return
	_calls = []
	_llm.set_retry_count(1)
	_llm.set_transport(func(payload: Dictionary) -> Dictionary:
		_calls.append(payload)
		if _calls.size() == 1:
			return {K_RESULT: HTTPRequest.RESULT_TIMEOUT, K_CODE: 0, K_BODY: ""}
		return {K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 200, K_BODY: _ok_body("万物皆由元素构成。")}
	)
	var reply: String = await _llm.ask("chem", "氢气怎么验纯", [])
	assert_eq(reply, "万物皆由元素构成。", "重试成功应返回第二包的结果")
	assert_eq(_calls.size(), 2, "第一包失败后应只补发 1 包")
	assert_false(_llm.is_offline(), "重试成功不该转离线")


# AC3：离线回答 = 兜底表答案 + 角标，且答案来自数据表而非硬编码。
func test_offline_reply_is_table_answer_plus_badge() -> void:
	if _llm == null:
		return
	_calls = []
	_llm.set_offline(true)
	_llm.set_transport(_respond_with({K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 200, K_BODY: _ok_body("不该被调用")}))
	var reply: String = await _llm.ask("chem", "氢气爆炸前要验纯吗", [])
	assert_eq(_calls.size(), 0, "离线模式不该发包（AC4）")
	assert_true(reply.contains(_badge()), "离线回答应带角标（AC3）：%s" % reply)
	assert_true(reply.contains("验纯"), "离线回答应来自 qa_fallback.json 的命中行：%s" % reply)


# AC3：零命中的离线回答用兜底行话术 + 角标。
func test_offline_zero_hit_uses_fallback_row() -> void:
	if _llm == null:
		return
	_llm.set_offline(true)
	var expected: String = _fallback_answer()
	assert_false(expected.is_empty(), "qa_fallback.json 应有兜底行 %s" % FALLBACK_ID)
	var reply: String = await _llm.ask("monitor", "请背诵莎士比亚十四行诗", [])
	assert_true(reply.begins_with(expected), "零命中应用兜底行话术：%s" % reply)
	assert_true(reply.ends_with(_badge()), "角标应在末尾（SPEC-04 §7 规则 5）：%s" % reply)


# AC4：手动开关立即生效——同一次会话内切回在线立刻发包。
func test_manual_switch_takes_effect_immediately() -> void:
	if _llm == null:
		return
	_calls = []
	_llm.set_transport(_respond_with(
		{K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 200, K_BODY: _ok_body("在线回答")}
	))
	_llm.set_offline(true)
	await _llm.ask("chem", "氢气怎么验纯", [])
	assert_eq(_calls.size(), 0, "离线时不发包")

	_llm.set_offline(false)
	var reply: String = await _llm.ask("chem", "氢气怎么验纯", [])
	assert_eq(_calls.size(), 1, "切回在线后立即发包（AC4）")
	assert_eq(reply, "在线回答", "切回在线后走网络结果")


# AC4：mode_changed 信号在切换时发出，且只在状态真变化时发。
func test_mode_changed_signal_fires_on_switch_only() -> void:
	if _llm == null:
		return
	var seen: Array = []
	var handler: Callable = func(offline: bool) -> void:
		seen.append(offline)
	_llm.mode_changed.connect(handler)
	_llm.set_offline(true)
	_llm.set_offline(true)
	_llm.set_offline(false)
	_llm.mode_changed.disconnect(handler)
	assert_eq(seen, [true, false], "重复设置同值不该重复发信号：%s" % str(seen))


# AC2：整个失败链路不许抛未捕获异常，也不许返回空串（UI 会显示空气泡）。
func test_failure_never_returns_empty_reply() -> void:
	if _llm == null:
		return
	_llm.set_retry_count(0)
	for response in [
		{K_RESULT: HTTPRequest.RESULT_TIMEOUT, K_CODE: 0, K_BODY: ""},
		{K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 500, K_BODY: ""},
		{K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 200, K_BODY: "{"},
	]:
		_llm.set_offline(false)
		_llm.set_transport(_respond_with(response as Dictionary))
		var reply: String = await _llm.ask("chem", "氢气怎么验纯", [])
		assert_false(reply.strip_edges().is_empty(), "失败兜底回复不许为空：%s" % str(response))


# NFR-05：失败路径的诊断信息里不许出现 key。这里断言实现代码没有把 key 拼进日志调用。
func test_api_key_never_reaches_logs() -> void:
	var text: String = FileAccess.get_file_as_string("res://scripts/autoload/llm_client.gd")
	assert_false(text.is_empty(), "应能读到 llm_client.gd")
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		var is_log: bool = (
			stripped.contains("push_error(")
			or stripped.contains("push_warning(")
			or stripped.contains("print(")
		)
		if is_log:
			assert_false(
				stripped.contains("_api_key"),
				"日志调用不许带 key（NFR-05）：%s" % stripped
			)
