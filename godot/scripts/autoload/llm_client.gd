# LLMClient（SPEC-03 §6.2，FR-M-07/08/09）：DeepSeek 调用 / 超时重试 / 离线兜底。
# 安全约束（NFR-05）：key 优先读系统环境变量，其次 user://config.cfg；绝不写进 res://、绝不进日志。
# 唯一发包点在 _generate_reply() 内；测试用 set_transport() 注入传输层，不发真实请求。
extends Node

signal reply_started(mentor_id: String)
signal reply_chunk(mentor_id: String, text: String)
signal reply_finished(mentor_id: String, full_text: String, offline: bool)
signal mode_changed(offline: bool)

const RouterScript: GDScript = preload("res://scripts/mentor/mentor_router.gd")
const QaScript: GDScript = preload("res://scripts/mentor/qa_fallback.gd")

# ==== 常量区 ====
const CONFIG_PATH: String = "user://config.cfg"
const CONFIG_SECTION: String = "llm"
const CONFIG_KEY: String = "api_key"
# 环境变量名（key 不落任何文件时的首选来源，2026-08-03）。
const ENV_KEY: String = "DEEPSEEK_API"

# 网络常量（SPEC-03 §6.2）：OpenAI 兼容端点，属技术约束而非玩家可见文案。
const ENDPOINT: String = "https://api.deepseek.com/chat/completions"
const MODEL: String = "deepseek-v4-flash"
const HEADER_CONTENT_TYPE: String = "Content-Type: application/json"
const HEADER_AUTH_PREFIX: String = "Authorization: Bearer "

# 请求体字段（OpenAI 兼容）。
const B_MODEL: String = "model"
const B_MESSAGES: String = "messages"
const B_MAX_TOKENS: String = "max_tokens"
const B_TEMPERATURE: String = "temperature"
const M_ROLE: String = "role"
const M_CONTENT: String = "content"
const ROLE_SYSTEM: String = "system"
const ROLE_USER: String = "user"
const ROLE_ASSISTANT: String = "assistant"

# 历史元素字段（SPEC-03 §6.2「历史元素约定」：一个元素 = 一轮对话）。
const H_QUESTION: String = "question"
const H_ANSWER: String = "answer"

# 传输层返回形状（SPEC-03 §6.2）。
const K_RESULT: String = "result"
const K_CODE: String = "code"
const K_BODY: String = "body"
const HTTP_OK: int = 200

# 响应解析路径：choices[0].message.content。
const R_CHOICES: String = "choices"
const R_MESSAGE: String = "message"

# balance.json 的键与缺表时的内置默认值（缺键不崩，FR-D-08 AC2）。
const BAL_TIMEOUT: String = "llm.timeout_seconds"
const BAL_RETRY: String = "llm.retry_count"
const BAL_HISTORY_ROUNDS: String = "llm.history_rounds"
const BAL_MAX_TOKENS: String = "llm.max_tokens"
const BAL_TEMPERATURE: String = "llm.temperature"
const BAL_INPUT_MAX: String = "llm.input_max_chars"

const FALLBACK_TIMEOUT: float = 8.0
const FALLBACK_RETRY: int = 1
const FALLBACK_HISTORY_ROUNDS: int = 4
const FALLBACK_MAX_TOKENS: int = 300
const FALLBACK_TEMPERATURE: float = 0.7
const FALLBACK_INPUT_MAX: int = 200

const UI_OFFLINE_BADGE: String = "chat_offline_badge"
const GAME_MANAGER_PATH: NodePath = ^"/root/GameManager"

# ==== 状态区 ====
var _offline: bool = false
var _api_key: String = ""
var _attempts: int = 0
# 超时/重试可被测试调小（FR-M-08 AC1）；-1 表示"未覆盖，读 balance.json"。
var _timeout_override: float = -1.0
var _retry_override: int = -1
var _transport: Callable = Callable()
var _router: RefCounted = RouterScript.new()
var _qa: RefCounted = QaScript.new()


# ==== 逻辑区 ====
func _ready() -> void:
	_load_api_key()
	# 无 key 时自动进离线模式（FR-M-07 AC3），不崩溃、不提示 key 内容。
	if _api_key.is_empty():
		_offline = true


func _load_api_key() -> void:
	# 首选系统环境变量（key 不落任何文件）；缺省回退 user://config.cfg（NFR-05 两条路径都合规）。
	var from_env: String = OS.get_environment(ENV_KEY).strip_edges()
	if not from_env.is_empty():
		_api_key = from_env
		return
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(CONFIG_PATH)
	if err != OK:
		# 首启没有配置文件是正常情况，不当错误处理。
		_api_key = ""
		return
	_api_key = str(config.get_value(CONFIG_SECTION, CONFIG_KEY, ""))


func has_api_key() -> bool:
	return not _api_key.is_empty()


# key 只写 user://，不进 res://、不打进日志（NFR-05）。
func set_api_key(key: String) -> void:
	var trimmed: String = key.strip_edges()
	var config: ConfigFile = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value(CONFIG_SECTION, CONFIG_KEY, trimmed)
	var err: int = config.save(CONFIG_PATH)
	if err != OK:
		push_error("[llm] 配置写入失败（错误码 %d）" % err)
		return
	_api_key = trimmed
	if not _api_key.is_empty() and _offline:
		set_offline(false)


func is_offline() -> bool:
	return _offline


# 演示保险开关：手动切换立即生效（FR-M-08 AC4）。
func set_offline(value: bool) -> void:
	if _offline == value:
		return
	_offline = value
	mode_changed.emit(_offline)


# 传输层注入口（SPEC-03 §6.2 非契约辅助）：(payload) -> {result, code, body}。
# 测试注入后 _generate_reply() 不碰 HTTPRequest，因此不发真实请求。
func set_transport(transport: Callable) -> void:
	_transport = transport


func set_qa_fallback(qa: RefCounted) -> void:
	if qa != null:
		_qa = qa


func attempt_count() -> int:
	return _attempts


func timeout_seconds() -> float:
	if _timeout_override >= 0.0:
		return _timeout_override
	return float(_balance(BAL_TIMEOUT, FALLBACK_TIMEOUT))


func set_timeout_seconds(value: float) -> void:
	_timeout_override = maxf(value, 0.0)


func retry_count() -> int:
	if _retry_override >= 0:
		return _retry_override
	return int(_balance(BAL_RETRY, FALLBACK_RETRY))


func set_retry_count(value: int) -> void:
	_retry_override = maxi(value, 0)


# 玩家输入清理（FR-M-03）：截断 + 清控制字符，之后才允许进 prompt。
func sanitize_input(raw: String) -> String:
	var max_chars: int = int(_balance(BAL_INPUT_MAX, FALLBACK_INPUT_MAX))
	var out: String = ""
	for i in raw.length():
		var code: int = raw.unicode_at(i)
		# 丢弃 C0 控制符（含换行/制表）与 DEL。
		if code < 32 or code == 127:
			out += " "
			continue
		out += raw[i]
	out = out.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	if out.length() > max_chars:
		out = out.substr(0, max_chars)
	return out


# 组请求体（OpenAI 兼容）。system = 人设段 + 通用后缀（来自 mentors.json + SPEC-04 §6），
# 之后按轮展开历史，最后一条是本轮清理过的 user 输入。
# 人设为空（未知导师 id）时返回空字典——不许把通用后缀单独喂给 LLM。
func build_request_body(mentor_id: String, question: String, history: Array) -> Dictionary:
	var system_text: String = str(_router.system_prompt_for(mentor_id))
	if system_text.strip_edges().is_empty():
		return {}
	var clean: String = sanitize_input(question)
	if clean.is_empty():
		return {}
	var messages: Array = [{M_ROLE: ROLE_SYSTEM, M_CONTENT: system_text}]
	for round_value in _trim_history(history):
		if typeof(round_value) != TYPE_DICTIONARY:
			continue
		var round_dict: Dictionary = round_value
		var past_question: String = str(round_dict.get(H_QUESTION, ""))
		var past_answer: String = str(round_dict.get(H_ANSWER, ""))
		if past_question.is_empty() or past_answer.is_empty():
			continue
		messages.append({M_ROLE: ROLE_USER, M_CONTENT: past_question})
		messages.append({M_ROLE: ROLE_ASSISTANT, M_CONTENT: past_answer})
	messages.append({M_ROLE: ROLE_USER, M_CONTENT: clean})
	return {
		B_MODEL: MODEL,
		B_MESSAGES: messages,
		B_MAX_TOKENS: int(_balance(BAL_MAX_TOKENS, FALLBACK_MAX_TOKENS)),
		B_TEMPERATURE: float(_balance(BAL_TEMPERATURE, FALLBACK_TEMPERATURE)),
	}


# 唯一对外调用入口；失败自动兜底，不抛未捕获异常（FR-M-08 AC2）。
func ask(mentor_id: String, question: String, history: Array) -> String:
	_attempts = 0
	var clean: String = sanitize_input(question)
	if clean.is_empty():
		# 空输入不发起请求（FR-M-03 AC2）。
		return ""
	reply_started.emit(mentor_id)
	var text: String = ""
	if not _offline:
		text = await _generate_reply(mentor_id, clean, history)
	if text.strip_edges().is_empty():
		text = _offline_reply(clean)
		if not _offline:
			# 失败即转离线，避免后续每次提问都再等一轮超时（FR-M-08 AC2）。
			set_offline(true)
	reply_finished.emit(mentor_id, text, _offline)
	return text


# 历史只保留最近 N 轮，一个元素即一轮（SPEC-03 §6.2 历史元素约定）。
func _trim_history(history: Array) -> Array:
	var rounds: int = int(_balance(BAL_HISTORY_ROUNDS, FALLBACK_HISTORY_ROUNDS))
	if rounds <= 0 or history.size() <= rounds:
		return history.duplicate()
	return history.slice(history.size() - rounds, history.size())


# 唯一真实网络出口。失败（四种）一律返回空串交给 ask() 兜底，不抛异常。
# 发包只经 _send()，测试注入 transport 后完全不碰 HTTPRequest。
func _generate_reply(mentor_id: String, question: String, history: Array) -> String:
	var body: Dictionary = build_request_body(mentor_id, question, history)
	if body.is_empty():
		return ""
	var total_attempts: int = retry_count() + 1
	for i in range(total_attempts):
		_attempts += 1
		var response: Dictionary = await _send(body)
		var text: String = _content_of(response)
		if not text.strip_edges().is_empty():
			return text
	return ""


# 解析 choices[0].message.content。四种失败在这里统一收口成空串：
# 非 RESULT_SUCCESS（超时/网络错）、非 200、非法 JSON、缺字段。
func _content_of(response: Dictionary) -> String:
	if int(response.get(K_RESULT, -1)) != HTTPRequest.RESULT_SUCCESS:
		return ""
	if int(response.get(K_CODE, 0)) != HTTP_OK:
		return ""
	var json: JSON = JSON.new()
	if json.parse(str(response.get(K_BODY, ""))) != OK:
		return ""
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	var choices: Variant = (data as Dictionary).get(R_CHOICES, [])
	if typeof(choices) != TYPE_ARRAY or (choices as Array).is_empty():
		return ""
	var first: Variant = (choices as Array)[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	var message: Variant = (first as Dictionary).get(R_MESSAGE, {})
	if typeof(message) != TYPE_DICTIONARY:
		return ""
	return str((message as Dictionary).get(M_CONTENT, ""))


# 发一包。注入了 transport 就走它（测试路径），否则走真实 HTTPRequest。
func _send(body: Dictionary) -> Dictionary:
	if _transport.is_valid():
		var injected: Variant = await _transport.call(body)
		if typeof(injected) == TYPE_DICTIONARY:
			return injected
		return {}
	return await _http_send(body)


# 真实请求。超时由 HTTPRequest.timeout 负责，失败一律翻译成传输层返回形状。
func _http_send(body: Dictionary) -> Dictionary:
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = timeout_seconds()
	add_child(request)
	var headers: PackedStringArray = PackedStringArray([
		HEADER_CONTENT_TYPE, HEADER_AUTH_PREFIX + _api_key,
	])
	var err: int = request.request(
		ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(body)
	)
	if err != OK:
		# 只记错误码，不记 URL 之外的任何内容，绝不记 key（NFR-05）。
		push_warning("[llm] 请求发起失败（错误码 %d）" % err)
		request.queue_free()
		return {K_RESULT: HTTPRequest.RESULT_CANT_CONNECT, K_CODE: 0, K_BODY: ""}
	var result: Array = await request.request_completed
	request.queue_free()
	return {
		K_RESULT: int(result[0]),
		K_CODE: int(result[1]),
		K_BODY: (result[3] as PackedByteArray).get_string_from_utf8(),
	}


# 离线兜底（SPEC-03 §6.3）：兜底表答案 + 「（离线模式）」角标。
# 表里没有兜底行时只返回角标，保证离线回复永不为空串（UI 不出现空气泡）。
func _offline_reply(question: String) -> String:
	var badge: String = _ui_string(UI_OFFLINE_BADGE)
	var answer: String = str(_qa.answer(question)).strip_edges()
	if answer.is_empty():
		return badge
	return answer + badge


func _ui_string(key: String) -> String:
	var gm: Node = get_node_or_null(GAME_MANAGER_PATH)
	if gm == null:
		return key
	return gm.get_ui_string(key)


func _balance(key: String, default_value: Variant) -> Variant:
	var gm: Node = get_node_or_null(GAME_MANAGER_PATH)
	if gm == null:
		return default_value
	return gm.get_balance(key, default_value)
