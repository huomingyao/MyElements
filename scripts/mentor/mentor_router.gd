# 班主任调度链（FR-M-03..M-06 / SPEC-03 §6.1）。
# 纯逻辑类：不进场景树、无 @onready、可直接 new()（SPEC-06 §3 / TP-14 备注）。
# 分类关键词、派活对象、调度语、人设全部读自 data/mentors.json——
# 代码里不许出现一个字的内容文本（FR-M-06 AC1，由 UT-M06 扫描 scripts/ 强制）。
extends RefCounted

const Suffix: GDScript = preload("res://scripts/mentor/prompt_suffix.gd")

# ==== 常量区 ====
const TABLE_FILE: String = "mentors.json"
const MONITOR_ID: String = "monitor"
# 零命中时的兜底分类；数据表里有 keywords 为空的那一项时以表为准。
const DEFAULT_CATEGORY: String = "other"
const AT_SIGN: String = "@"

const F_ID: String = "id"
const F_MENTION: String = "mention"
const F_DISPATCH: String = "dispatch"
const F_CATEGORY: String = "category"
const F_KEYWORDS: String = "keywords"
const F_TARGETS: String = "targets"
const F_LINE: String = "line"
const F_SYSTEM_PROMPT: String = "system_prompt"

const KEY_MENTOR_ID: String = "mentor_id"
const KEY_TEXT: String = "text"
const KEY_OFFLINE: String = "offline"

# 硬上限（SPEC-03 §6.1）：一次 handle_message 只许调度 1 次、最多返回 3 条消息。
# 由计数器与切片保证，不依赖 prompt 自觉。
const DISPATCH_LIMIT: int = 1
const MAX_MESSAGES: int = 3
const MAX_TARGETS: int = MAX_MESSAGES - 1

# 未注入 provider 时的回复来源（TP-15 会把在线/离线逻辑做全）。
const LLM_PATH: NodePath = ^"LLMClient"
const LLM_ASK: String = "ask"

# ==== 状态区 ====
var _by_id: Dictionary = {}
var _mention_to_id: Dictionary = {}
var _dispatch: Array = []
var _dispatch_count: int = 0
var _reply_provider: Callable = Callable()
var _suffix: RefCounted = Suffix.new()


# ==== 逻辑区 ====
func _init() -> void:
	load_from(DataLoader.load_table(TABLE_FILE, TYPE_ARRAY, []) as Array)


# 数据注入口（SPEC-06 §3）：测试传改过的行，行为随之改变，代码里不写死任何关键词。
func load_from(rows: Array) -> void:
	_by_id = DataLoader.index_by_id(rows)
	_mention_to_id = {}
	_dispatch = []
	for row_value in rows:
		if typeof(row_value) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_value
		var id: String = str(row.get(F_ID, ""))
		if id.is_empty():
			continue
		var mention: String = str(row.get(F_MENTION, "")).strip_edges()
		if not mention.is_empty() and not _mention_to_id.has(mention):
			_mention_to_id[mention] = id
		if id == MONITOR_ID:
			_dispatch = row.get(F_DISPATCH, []) as Array


# 回复来源注入口：provider 收 (mentor_id, question) 返回文本。测试用它避开网络。
func set_reply_provider(provider: Callable) -> void:
	_reply_provider = provider


func dispatch_count() -> int:
	return _dispatch_count


# 人设段 + 通用后缀（FR-M-06 AC3）。未知 id 返回空串，不许把后缀单独喂给 LLM。
func system_prompt_for(mentor_id: String) -> String:
	var row: Dictionary = _by_id.get(mentor_id, {}) as Dictionary
	return str(_suffix.append_to(str(row.get(F_SYSTEM_PROMPT, ""))))


# FR-M-04：按 dispatch 的数组顺序扫关键词，先命中者胜（顺序即优先级）。
func classify(question: String) -> String:
	var fallback: String = DEFAULT_CATEGORY
	var fallback_found: bool = false
	for entry_value in _dispatch:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var category: String = str(entry.get(F_CATEGORY, ""))
		if category.is_empty():
			continue
		var keywords: Array = entry.get(F_KEYWORDS, []) as Array
		if keywords.is_empty():
			if not fallback_found:
				fallback = category
				fallback_found = true
			continue
		for keyword_value in keywords:
			var keyword: String = str(keyword_value)
			if not keyword.is_empty() and question.contains(keyword):
				return category
	return fallback


# FR-M-04 AC3：只做查表。未知分类返回空数组；永不含班主任自己。
func route_targets(category: String) -> Array:
	var out: Array = []
	for target_value in _entry_of(category).get(F_TARGETS, []) as Array:
		var id: String = str(target_value)
		if id.is_empty() or id == MONITOR_ID or out.has(id):
			continue
		out.append(id)
	return out


# FR-M-05：@句柄 → 导师 id，按出现顺序、去重。映射来源是 mentors.json 的 mention。
func parse_mentions(text: String) -> Array:
	var out: Array = []
	if text.is_empty():
		return out
	var cursor: int = 0
	while true:
		var at: int = text.find(AT_SIGN, cursor)
		if at < 0:
			break
		cursor = at + AT_SIGN.length()
		var id: String = _mention_id_at(text, cursor)
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out


# FR-M-05：首条必来自班主任；最多 3 条；只解析班主任消息里的 @；调度计数硬上限 1。
func handle_message(question: String) -> Array:
	_dispatch_count = 0
	var messages: Array = []
	var clean: String = question.strip_edges()
	if clean.is_empty():
		return messages
	var category: String = classify(clean)
	var reply: String = str(await _reply_of(MONITOR_ID, clean))
	var offline: bool = reply.strip_edges().is_empty()
	var monitor_text: String = _dispatch_line(category) if offline else reply
	if monitor_text.strip_edges().is_empty():
		return messages
	messages.append(_message(MONITOR_ID, monitor_text, offline))
	for target_value in _targets_for(category, monitor_text):
		if messages.size() >= MAX_MESSAGES:
			break
		var target_id: String = str(target_value)
		var target_reply: String = str(await _reply_of(target_id, clean))
		if target_reply.strip_edges().is_empty():
			continue
		messages.append(_message(target_id, target_reply, false))
	return messages


# 派活对象：优先认班主任消息里的 @（真实链条由 LLM 的调度语驱动），
# 没有可用 @ 时退回数据表的 targets。班主任自己被剔除 → 循环 @ 不会递归（AC3）。
func _targets_for(category: String, monitor_text: String) -> Array:
	if _dispatch_count >= DISPATCH_LIMIT:
		return []
	var targets: Array = parse_mentions(monitor_text)
	targets.erase(MONITOR_ID)
	if targets.is_empty():
		targets = route_targets(category)
	if targets.is_empty():
		return []
	_dispatch_count += 1
	return targets.slice(0, MAX_TARGETS)


# 取 index 处最长匹配的 mention（避免句柄互为前缀时误判）。
func _mention_id_at(text: String, index: int) -> String:
	var best_id: String = ""
	var best_length: int = 0
	for mention_value in _mention_to_id:
		var mention: String = str(mention_value)
		if mention.length() <= best_length:
			continue
		if text.substr(index, mention.length()) == mention:
			best_id = str(_mention_to_id[mention])
			best_length = mention.length()
	return best_id


func _entry_of(category: String) -> Dictionary:
	for entry_value in _dispatch:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		if str(entry.get(F_CATEGORY, "")) == category:
			return entry
	return {}


# 回复为空时班主任那条走数据表里的调度语（离线兜底，文本仍在表里）。
func _dispatch_line(category: String) -> String:
	return str(_entry_of(category).get(F_LINE, ""))


func _message(mentor_id: String, text: String, offline: bool) -> Dictionary:
	return {KEY_MENTOR_ID: mentor_id, KEY_TEXT: text, KEY_OFFLINE: offline}


# 未注入 provider 时走 LLMClient（它内部负责清理、历史、离线兜底）。
func _reply_of(mentor_id: String, question: String) -> String:
	if _reply_provider.is_valid():
		return str(await _reply_provider.call(mentor_id, question))
	var llm: Object = _llm_client()
	if llm == null:
		return ""
	return str(await llm.call(LLM_ASK, mentor_id, question, []))


func _llm_client() -> Object:
	var loop: MainLoop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var node: Node = (loop as SceneTree).root.get_node_or_null(LLM_PATH)
	if node == null or not node.has_method(LLM_ASK):
		return null
	return node
