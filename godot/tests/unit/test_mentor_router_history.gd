# 包A-导师链 FR-M-07 AC2 接线修复：MentorRouter 内部维护每导师最近 4 轮历史，
# 经 LLMClient.ask 的第三参（冻结签名不变）传给请求体——修复前恒传空数组。
# 全程用注入的传输层截获 payload，**不发真实请求**（SPEC-03 §6.2 / TP-15 安全约束）。
extends GutTest

const ROUTER_PATH: String = "res://scripts/mentor/mentor_router.gd"

# 传输层返回形状（SPEC-03 §6.2）：{result, code, body}。
const K_RESULT: String = "result"
const K_CODE: String = "code"
const K_BODY: String = "body"
const B_MESSAGES: String = "messages"
const M_ROLE: String = "role"
const M_CONTENT: String = "content"
const ROLE_SYSTEM: String = "system"
const ROLE_USER: String = "user"
const ROLE_ASSISTANT: String = "assistant"

# FR-M-07 AC2 的「最近 4 轮」；与 balance.json 的 llm.history_rounds 默认值一致。
const HISTORY_LIMIT: int = 4
# mentors.json 里 chem 的人设标志（区分发给哪位导师的 payload）。
const CHEM_PERSONA_MARK: String = "袁仲衡"

var _llm: Node = null
var _router: RefCounted = null
var _calls: Array = []
var _chem_seq: int = 0
var _monitor_seq: int = 0
var _saved_offline: bool = false
var _saved_retry: int = 0
var _saved_timeout: float = 0.0


func before_each() -> void:
	_calls = []
	_chem_seq = 0
	_monitor_seq = 0
	_router = null
	_llm = Engine.get_main_loop().root.get_node_or_null(^"LLMClient")
	assert_not_null(_llm, "LLMClient autoload 必须存在")
	if _llm == null:
		return
	_saved_offline = _llm.is_offline()
	_saved_retry = _llm.retry_count()
	_saved_timeout = _llm.timeout_seconds()
	_llm.set_offline(false)
	_llm.set_retry_count(0)
	_llm.set_timeout_seconds(0.05)
	_llm.set_transport(_transport)
	_router = (load(ROUTER_PATH) as GDScript).new()
	assert_not_null(_router, "MentorRouter 应可直接实例化（SPEC-03 §6.1）")


func after_each() -> void:
	if _llm == null:
		return
	_llm.set_transport(Callable())
	_llm.set_offline(_saved_offline)
	_llm.set_retry_count(_saved_retry)
	_llm.set_timeout_seconds(_saved_timeout)


# 截获每个发包 payload，按人设段区分导师并返回该导师专属的递增回答。
func _transport(payload: Dictionary) -> Dictionary:
	_calls.append(payload)
	var answer: String = ""
	if _is_chem(payload):
		_chem_seq += 1
		answer = "化学回答%d" % _chem_seq
	else:
		_monitor_seq += 1
		answer = "班主任回答%d" % _monitor_seq
	return {
		K_RESULT: HTTPRequest.RESULT_SUCCESS,
		K_CODE: 200,
		K_BODY: JSON.stringify({"choices": [{"message": {"content": answer}}]}),
	}


func _is_chem(payload: Dictionary) -> bool:
	var messages: Array = payload.get(B_MESSAGES, []) as Array
	if messages.is_empty():
		return false
	return str((messages.front() as Dictionary).get(M_CONTENT, "")).contains(CHEM_PERSONA_MARK)


func _chem_payloads() -> Array:
	var out: Array = []
	for payload_value in _calls:
		var payload: Dictionary = payload_value
		if _is_chem(payload):
			out.append(payload)
	return out


func _contents_of(payload: Dictionary) -> Array:
	var out: Array = []
	for message_value in payload.get(B_MESSAGES, []) as Array:
		out.append(str((message_value as Dictionary).get(M_CONTENT, "")))
	return out


func _roles_of(payload: Dictionary) -> Array:
	var out: Array = []
	for message_value in payload.get(B_MESSAGES, []) as Array:
		out.append(str((message_value as Dictionary).get(M_ROLE, "")))
	return out


# AC2 接线：第二轮提问时，发给化学老师的 payload 必须带上一轮的问与答（修复前恒为空）。
func test_previous_round_is_sent_in_next_request() -> void:
	if _llm == null or _router == null:
		return
	await _router.handle_message("氢气怎么验纯")
	await _router.handle_message("氧气支持燃烧吗")
	var chem: Array = _chem_payloads()
	assert_eq(chem.size(), 2, "两轮化学类提问应各问化学老师一次")
	if chem.size() < 2:
		return
	var contents: Array = _contents_of(chem[1])
	assert_true(contents.has("氢气怎么验纯"), "第二轮请求应带第一轮问题：%s" % str(contents))
	assert_true(contents.has("化学回答1"), "第二轮请求应带第一轮回答：%s" % str(contents))


# 历史元素展开形状（SPEC-03 §6.2）：每轮 = user(question) + assistant(answer)，按时间序。
func test_history_expands_as_user_then_assistant_pairs() -> void:
	if _llm == null or _router == null:
		return
	await _router.handle_message("氢气怎么验纯")
	await _router.handle_message("氧气支持燃烧吗")
	var chem: Array = _chem_payloads()
	if chem.size() < 2:
		fail_test("化学老师应被问过两次")
		return
	var roles: Array = _roles_of(chem[1])
	assert_eq(roles.front(), ROLE_SYSTEM, "首条仍是 system")
	assert_eq(str(roles[1]), ROLE_USER, "历史轮先 user：%s" % str(roles))
	assert_eq(str(roles[2]), ROLE_ASSISTANT, "历史轮后 assistant：%s" % str(roles))
	assert_eq(roles.back(), ROLE_USER, "末条是本轮 user")


# 每导师独立记账：化学老师的上下文里不许混入班主任的问答。
func test_history_is_kept_per_mentor() -> void:
	if _llm == null or _router == null:
		return
	await _router.handle_message("氢气怎么验纯")
	await _router.handle_message("氧气支持燃烧吗")
	var chem: Array = _chem_payloads()
	if chem.size() < 2:
		fail_test("化学老师应被问过两次")
		return
	var contents: Array = _contents_of(chem[1])
	assert_false(contents.has("班主任回答1"), "化学老师的请求不该带班主任的回答：%s" % str(contents))


# 硬上限：第 6 轮请求最多带最近 4 轮历史，最早一轮已被裁掉（FR-M-07 AC2）。
func test_history_is_capped_at_four_rounds() -> void:
	if _llm == null or _router == null:
		return
	for i in range(6):
		await _router.handle_message("氢气问题%d" % (i + 1))
	var chem: Array = _chem_payloads()
	assert_eq(chem.size(), 6, "六轮化学类提问应各问化学老师一次")
	if chem.size() < 6:
		return
	var last_payload: Dictionary = chem[5]
	var messages: Array = last_payload.get(B_MESSAGES, []) as Array
	assert_eq(
		messages.size(), 1 + HISTORY_LIMIT * 2 + 1,
		"第 6 轮请求应为 system + 4 轮×2 + 本轮 user，实际：%s" % str(_roles_of(last_payload))
	)
	var contents: Array = _contents_of(last_payload)
	assert_false(contents.has("氢气问题1"), "最早一轮应被裁掉：%s" % str(contents))
	assert_true(contents.has("氢气问题5"), "最近一轮历史应保留：%s" % str(contents))
	assert_true(contents.has("化学回答5"), "最近一轮回答应保留：%s" % str(contents))


# 离线期间的兜底问答不进历史：切回在线后上下文只含真实在线问答。
func test_offline_fallback_rounds_are_not_recorded() -> void:
	if _llm == null or _router == null:
		return
	await _router.handle_message("氢气怎么验纯")
	_llm.set_offline(true)
	await _router.handle_message("氧气支持燃烧吗")
	_llm.set_offline(false)
	await _router.handle_message("盐怎么提纯")
	var chem: Array = _chem_payloads()
	# 离线轮不发包：chem 只收到第 1、3 两轮。
	assert_eq(chem.size(), 2, "离线轮不该发包")
	if chem.size() < 2:
		return
	var contents: Array = _contents_of(chem[1])
	assert_true(contents.has("氢气怎么验纯"), "在线轮历史应保留")
	assert_false(contents.has("氧气支持燃烧吗"), "离线兜底轮不许进历史：%s" % str(contents))
