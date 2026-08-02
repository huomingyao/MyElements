# IT-M07 / FR-M-07：DeepSeek 请求体组装（SPEC-03 §6.2）。
# 断言请求体含 system+user、max_tokens≈300、temperature=0.7；历史仅 4 轮；
# 无 key 时进离线不崩溃；**key 不出现在日志中**（NFR-05）。
# 全程注入传输层，**不发真实请求**（TP-15 安全约束）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const K_RESULT: String = "result"
const K_CODE: String = "code"
const K_BODY: String = "body"

const ROLE_SYSTEM: String = "system"
const ROLE_USER: String = "user"
const ROLE_ASSISTANT: String = "assistant"

var _llm: Node = null
var _calls: Array = []
var _saved_offline: bool = false
var _saved_retry: int = 0
var _saved_timeout: float = 0.0


func before_each() -> void:
	_calls = []
	_llm = Engine.get_main_loop().root.get_node_or_null(^"LLMClient")
	assert_not_null(_llm, "LLMClient autoload 必须存在")
	if _llm == null:
		return
	for method_name in ["set_transport", "build_request_body"]:
		if not _llm.has_method(method_name):
			fail_test("LLMClient 应有 %s()（SPEC-03 §6.2 非契约辅助）" % method_name)
			_llm = null
			return
	_saved_offline = _llm.is_offline()
	_saved_retry = _llm.retry_count()
	_saved_timeout = _llm.timeout_seconds()
	_llm.set_timeout_seconds(0.05)
	_llm.set_retry_count(0)
	_llm.set_offline(false)
	_llm.set_transport(func(payload: Dictionary) -> Dictionary:
		_calls.append(payload)
		return {K_RESULT: HTTPRequest.RESULT_SUCCESS, K_CODE: 200, K_BODY: JSON.stringify(
			{"choices": [{"message": {"content": "配平了吗？"}}]}
		)}
	)


func after_each() -> void:
	if _llm == null:
		return
	_llm.set_transport(Callable())
	_llm.set_timeout_seconds(_saved_timeout)
	_llm.set_retry_count(_saved_retry)
	_llm.set_offline(_saved_offline)


func _balance(key: String, default_value: Variant) -> Variant:
	var gm: Node = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	if gm == null:
		return default_value
	return gm.get_balance(key, default_value)


func _rounds(count: int) -> Array:
	var out: Array = []
	for i in range(count):
		out.append({"question": "问题%d" % i, "answer": "回答%d" % i})
	return out


func _messages_of(body: Dictionary) -> Array:
	return body.get("messages", []) as Array


func _roles_of(body: Dictionary) -> Array:
	var out: Array = []
	for message_value in _messages_of(body):
		out.append(str((message_value as Dictionary).get("role", "")))
	return out


# AC1：请求体含 system（人设+后缀）与 user（清理后的问题），且 system 在最前。
func test_body_contains_system_and_user_messages() -> void:
	if _llm == null:
		return
	var body: Dictionary = _llm.build_request_body("chem", "氢气怎么验纯", [])
	var roles: Array = _roles_of(body)
	assert_eq(roles.front(), ROLE_SYSTEM, "首条必须是 system：%s" % str(roles))
	assert_eq(roles.back(), ROLE_USER, "末条必须是本轮 user：%s" % str(roles))
	var messages: Array = _messages_of(body)
	var system_text: String = str((messages.front() as Dictionary).get("content", ""))
	assert_false(system_text.strip_edges().is_empty(), "system 内容不该为空")
	# 人设来自 mentors.json，通用后缀来自 prompt_suffix.gd（SPEC-04 §6）。
	assert_true(system_text.contains("袁仲衡"), "system 应含 mentors.json 的人设段：%s" % system_text)
	assert_true(system_text.contains("初中化学"), "system 应含通用后缀（SPEC-04 §6）")
	assert_eq(
		str((messages.back() as Dictionary).get("content", "")), "氢气怎么验纯",
		"user 内容应是清理后的问题原文"
	)


# AC1：max_tokens≈300、temperature=0.7，取自 balance.json 而非写死。
func test_body_uses_balance_max_tokens_and_temperature() -> void:
	if _llm == null:
		return
	var body: Dictionary = _llm.build_request_body("chem", "氢气怎么验纯", [])
	var max_tokens: int = int(_balance("llm.max_tokens", -1))
	var temperature: float = float(_balance("llm.temperature", -1.0))
	assert_eq(max_tokens, 300, "balance.json 的 llm.max_tokens 应为 300")
	assert_almost_eq(temperature, 0.7, 0.001, "balance.json 的 llm.temperature 应为 0.7")
	assert_eq(int(body.get("max_tokens", -1)), max_tokens, "请求体 max_tokens 应取自 balance.json")
	assert_almost_eq(
		float(body.get("temperature", -1.0)), temperature, 0.001,
		"请求体 temperature 应取自 balance.json"
	)
	assert_false(str(body.get("model", "")).is_empty(), "请求体应带 model（OpenAI 兼容）")


# AC1：历史只带最近 4 轮，每轮展开为 user+assistant 两条。
func test_history_is_limited_to_four_rounds() -> void:
	if _llm == null:
		return
	var rounds: int = int(_balance("llm.history_rounds", 4))
	assert_eq(rounds, 4, "balance.json 的 llm.history_rounds 应为 4")
	var body: Dictionary = _llm.build_request_body("chem", "本轮问题", _rounds(rounds + 3))
	var messages: Array = _messages_of(body)
	# 1 条 system + 4 轮×2 条 + 1 条本轮 user。
	assert_eq(messages.size(), 1 + rounds * 2 + 1, "历史应被裁到 %d 轮：%s" % [rounds, str(_roles_of(body))])
	var contents: Array = []
	for message_value in messages:
		contents.append(str((message_value as Dictionary).get("content", "")))
	assert_false(str(contents).contains("问题0"), "最早的历史轮应被裁掉")
	assert_true(str(contents).contains("问题%d" % (rounds + 2)), "最近一轮历史应保留")
	assert_eq(
		str((messages[1] as Dictionary).get("role", "")), ROLE_USER, "每轮先 user"
	)
	assert_eq(
		str((messages[2] as Dictionary).get("role", "")), ROLE_ASSISTANT, "每轮后 assistant"
	)


# 历史条数不足 4 轮时照原样带上，不补空轮。
func test_short_history_is_passed_through() -> void:
	if _llm == null:
		return
	var body: Dictionary = _llm.build_request_body("chem", "本轮问题", _rounds(1))
	assert_eq(_messages_of(body).size(), 1 + 2 + 1, "1 轮历史 = system + 2 条 + 本轮 user")


# 玩家输入必须先过 sanitize_input 才进请求体（NFR-05 / FR-M-03）。
func test_user_content_is_sanitized_before_entering_body() -> void:
	if _llm == null:
		return
	var body: Dictionary = _llm.build_request_body("chem", "氢气\n\n怎么\t验纯  ", [])
	var user_text: String = str((_messages_of(body).back() as Dictionary).get("content", ""))
	assert_false(user_text.contains("\n"), "换行应已清理：%s" % user_text)
	assert_false(user_text.contains("\t"), "制表符应已清理：%s" % user_text)
	assert_eq(user_text, "氢气 怎么 验纯", "应为 sanitize_input 的结果")


# 未知导师 id 不崩溃：system 为空时不发请求，直接走兜底（不许把后缀单独喂给 LLM）。
func test_unknown_mentor_id_does_not_crash() -> void:
	if _llm == null:
		return
	_calls = []
	var reply: String = await _llm.ask("no_such_mentor", "氢气怎么验纯", [])
	assert_eq(_calls.size(), 0, "无人设时不该发请求")
	assert_false(reply.strip_edges().is_empty(), "未知导师也要有兜底回复，不许空串")


# ask() 走完整链路时传给传输层的 payload 就是 build_request_body 的结果。
func test_ask_sends_built_body_to_transport() -> void:
	if _llm == null:
		return
	_calls = []
	var reply: String = await _llm.ask("chem", "氢气怎么验纯", _rounds(2))
	assert_eq(reply, "配平了吗？", "应返回 stub 的 content")
	assert_eq(_calls.size(), 1, "成功时只发 1 包")
	var sent: Dictionary = _calls.front() as Dictionary
	assert_eq(_roles_of(sent).front(), ROLE_SYSTEM, "发出的 payload 首条应是 system")
	assert_eq(int(sent.get("max_tokens", -1)), int(_balance("llm.max_tokens", -1)))


# AC3：无 key 时进离线不崩溃。
# 不读也不写真实的 user://config.cfg（里面是玩家的 key）——另起一个实例走一遍 _ready()，
# 断言启动后的离线状态恒等于「没有 key」，两个方向都覆盖，且与本机是否配了 key 无关。
func test_no_api_key_goes_offline_without_crash() -> void:
	if _llm == null:
		return
	var fresh: Node = (load("res://scripts/autoload/llm_client.gd") as GDScript).new()
	add_child_autofree(fresh)
	await wait_process_frames(1)
	assert_eq(
		fresh.is_offline(), not fresh.has_api_key(),
		"启动后的离线状态应等于「没有 key」（FR-M-07 AC3）"
	)
	# 离线实例照样能回答，且不发任何请求（未注入传输层，走真实分支也不会发包）。
	fresh.set_offline(true)
	var reply: String = await fresh.ask("chem", "氢气爆炸前要验纯吗", [])
	assert_false(reply.strip_edges().is_empty(), "离线也要有回复，不许空串或崩溃")


# NFR-05：key 不出现在日志中，也不出现在 res:// 任何文件里。
func test_api_key_absent_from_logs_and_res_files() -> void:
	var llm_text: String = FileAccess.get_file_as_string("res://scripts/autoload/llm_client.gd")
	assert_false(llm_text.is_empty(), "应能读到 llm_client.gd")
	assert_true(llm_text.contains("user://config.cfg"), "key 只从 user://config.cfg 读")
	for line in llm_text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		var is_log: bool = (
			stripped.contains("push_error(")
			or stripped.contains("push_warning(")
			or stripped.contains("print(")
		)
		assert_false(
			is_log and stripped.contains("_api_key"),
			"日志里不许带 key（NFR-05）：%s" % stripped
		)
	# 数据表里也不许出现 api_key 字段（key 绝不进 res://）。
	assert_false(
		Fixture.read_object("balance.json").has("api_key"),
		"balance.json 不该有 api_key"
	)
