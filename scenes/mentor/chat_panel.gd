# 底部聊天框（FR-M-02）：左侧导师半身立绘 + 名称，右侧对话记录 + 输入框。
# 世界不暂停、不切场景（AC1，本脚本绝不碰 get_tree().paused）；
# 回复逐字打字，打字期间立绘 talk、结束回 idle（AC2）；
# 记录可滚动且保留全部消息（AC3）；Esc 或关闭按钮收起（AC4）。
# 安全：输入先过 LLMClient.sanitize_input（FR-M-03）；LLM 返回只做文本渲染。
# 文案：占位符走 get_ui_string，导师姓名走 mentors.json，本文件零中文字面量（NFR-04）。
extends Control

signal all_messages_finished()
signal chat_closed()
# fire-and-forget 入口：UI 提交只发信号，异步处理在信号处理器里 await，
# 避免「直接调用协程不加 await」的运行时错误。
signal send_requested(raw: String)

# ==== 常量区 ====
const RouterScript: GDScript = preload("res://scripts/mentor/mentor_router.gd")
const RegistryScript: GDScript = preload("res://scenes/mentor/mentor_registry.gd")
const Art: GDScript = preload("res://scenes/mentor/mentor_art.gd")

const GAME_MANAGER_PATH: NodePath = ^"/root/GameManager"
const LLM_CLIENT_PATH: NodePath = ^"/root/LLMClient"

const UI_PLACEHOLDER_KEY: String = "chat_placeholder"
const UI_SEND_KEY: String = "chat_send"
const UI_CLOSE_KEY: String = "chat_close"
# 设置入口按钮文案（包A-3：ConfigPanel 可达性，FR-M-10）。
const UI_CONFIG_KEY: String = "chat_config"
# 玩家行前缀（2026-08-03 着色增强）：与导师名对称的「我」标签，文案在 ui_strings。
const UI_PLAYER_LABEL_KEY: String = "chat_player_label"

# 对话行配色（表现参数，非调参项）：导师名金色加粗、玩家行淡蓝，一眼区分问答双方。
const COLOR_MENTOR_NAME: String = "#ffd54a"
const COLOR_PLAYER: String = "#8fd3ff"
# ui_manager 面板名（SPEC-03 §8）：本聊天框与配置面板。
const PANEL_CONFIG: String = "config"
# 世界总装里的裁决器（world.tscn 的 UILayer/UIManager），按祖先链惰性解析。
const UI_MANAGER_REL: NodePath = ^"UILayer/UIManager"
# Esc 对应的输入动作（FR-C-01 输入映射）。
const ACTION_CLOSE: String = "pause"
# 打字跳过的确认键（项目默认输入映射）。
const ACTION_SKIP: String = "ui_accept"

const MODE_IDLE: String = "idle"
const MODE_TALK: String = "talk"
# ui_manager 无参 open() 的默认导师：班主任首接（FR-M-04）。
const DEFAULT_MENTOR_ID: String = "monitor"
# 立绘显示尺寸（占位期生成图也按这个尺寸）。
const AVATAR_SIZE: Vector2i = Vector2i(96, 96)
# 打字速度默认值（字/秒）。balance.json 归 P1 单写（SPEC-07 §3.2），
# 故本调参项暂留场景常量区，调参阶段一眼可改。
const DEFAULT_TYPING_SPEED: float = 40.0
const MIN_TYPING_SPEED: float = 1.0
# 滚到底的写法：设一个远超最大值的值，引擎自动 clamp。
const SCROLL_TO_BOTTOM: int = 1000000

const K_MENTOR_ID: String = "mentor_id"
const K_TEXT: String = "text"

# ==== 状态区 ====
# 打字速度暴露为公共变量：测试可调大跳过等待（SPEC-06 §3 可测性约束）。
var typing_chars_per_second: float = DEFAULT_TYPING_SPEED

var _router: RefCounted = null
var _registry: RefCounted = null
var _client: Node = null
var _hydrogen: RefCounted = null
var _open: bool = false
var _busy: bool = false
var _typing: bool = false
var _avatar_mode: String = MODE_IDLE
# ui_manager 无参 open() 的开场导师：academy 按被交互的导师注入（包A-4）；
# 空串时维持原语义——班主任首接（FR-M-04）。
var _pending_mentor_id: String = ""
# 打字跳过：请求标记 + 当前行的完整文本与标签引用（skip_typing 同步补全用）。
var _skip_typing: bool = false
var _typing_label: RichTextLabel = null
var _typing_speaker: String = ""
var _typing_full: String = ""

@onready var _avatar: TextureRect = %MentorAvatar
@onready var _name_label: Label = %MentorName
@onready var _scroll: ScrollContainer = %HistoryScroll
@onready var _list: VBoxContainer = %HistoryList
@onready var _input: LineEdit = %InputLine
@onready var _send_button: Button = %SendButton
@onready var _close_button: Button = %CloseButton
@onready var _config_button: Button = %ConfigButton


# ==== 逻辑区 ====
func _ready() -> void:
	visible = false
	if _router == null:
		_router = RouterScript.new()
	if _registry == null:
		_registry = RegistryScript.new()
	if _client == null:
		_client = get_node_or_null(LLM_CLIENT_PATH)
	_input.placeholder_text = _ui_string(UI_PLACEHOLDER_KEY)
	_send_button.text = _ui_string(UI_SEND_KEY)
	_close_button.text = _ui_string(UI_CLOSE_KEY)
	_config_button.text = _ui_string(UI_CONFIG_KEY)
	_input.text_submitted.connect(_on_text_submitted)
	_send_button.pressed.connect(_on_send_pressed)
	_close_button.pressed.connect(close_chat)
	_config_button.pressed.connect(_on_config_pressed)
	send_requested.connect(_on_send_requested)


# 测试注入口（SPEC-06 §3）：注入带 set_reply_provider 的 router 后不发真实请求。
func set_router(router: RefCounted) -> void:
	_router = router


# 测试注入口：注入假客户端后不碰真实 LLMClient（也就完全不碰网络与 user://）。
func set_client(client: Node) -> void:
	_client = client


# 世界接线入口（FR-G-09 AC1）：注入共享的 HydrogenEvent；未注入时惰性自建。
func set_hydrogen_event(event: RefCounted) -> void:
	_hydrogen = event


func open_chat(mentor_id: String) -> void:
	_open = true
	visible = true
	_show_mentor(mentor_id, MODE_IDLE)
	_input.grab_focus()


func close_chat() -> void:
	_open = false
	visible = false
	_typing = false
	_avatar_mode = MODE_IDLE
	chat_closed.emit()


func is_chat_open() -> bool:
	return _open


# ==== ui_manager 面板契约（SPEC-03 §8，收口 W1）====
# ui_manager 统一按 open/close/is_open 驱动注册面板；这里委托到既有聊天方法，
# 不改 open_chat/close_chat/is_chat_open 签名。无参 open() 按班主任首接落默认导师，
# academy 注入过 pending 导师时以被交互的导师开场（包A-4）。
func open() -> void:
	var mentor_id: String = _pending_mentor_id
	_pending_mentor_id = ""
	if mentor_id.is_empty():
		mentor_id = DEFAULT_MENTOR_ID
	open_chat(mentor_id)


# academy 在 ui_manager.open("chat") 前注入被交互的导师（一次性，open() 消费即清）。
func set_pending_mentor(mentor_id: String) -> void:
	_pending_mentor_id = mentor_id


func close() -> void:
	close_chat()


func is_open() -> bool:
	return is_chat_open()


func is_typing() -> bool:
	return _typing


# 打字跳过（优化包C-4）：打字进行中点击面板或按确认键，当前行立即补全显示。
# 同步把全行写上屏，不等逐字循环走到下一个字符。
func skip_typing() -> void:
	if not _typing:
		return
	_skip_typing = true
	if _typing_label != null and is_instance_valid(_typing_label):
		_finalize_mentor_line(_typing_label, _typing_speaker, _typing_full)
		_scroll_to_bottom()


func avatar_mode() -> String:
	return _avatar_mode


func history_count() -> int:
	return _list.get_child_count()


# 非异步提交入口（UI 与测试共用）：发信号后即返回，不阻塞调用方。
func submit(raw: String) -> void:
	send_requested.emit(raw)


# 发送一条提问：清理 → 上屏 → 走 MentorRouter 调度链 → 逐条逐字打出回复。
# 打字中忽略新发送（按钮同步禁用），并发安全。
func send_text(raw: String) -> void:
	var clean: String = _sanitize(raw)
	if clean.is_empty():
		# 空输入不发起请求（FR-M-03 AC2）。
		return
	if _busy:
		return
	_busy = true
	_send_button.disabled = true
	_append_line("", clean, true)
	if _router == null:
		_router = RouterScript.new()
	var messages: Array = await _router.handle_message(clean)
	_maybe_unlock_purity(clean)
	await _type_all(messages)
	_busy = false
	_send_button.disabled = false


# 问过氢气/爆炸/验纯相关问题 → 解锁验纯步骤（FR-G-09 AC1，SPEC-02 §4.5 的导师回调）。
func _maybe_unlock_purity(question: String) -> void:
	if _hydrogen == null:
		_hydrogen = (load("res://scripts/gameplay/hydrogen_event.gd") as GDScript).new()
	if _hydrogen.question_mentions_hydrogen(question):
		_hydrogen.unlock_purity_check()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(ACTION_CLOSE):
		close_chat()
		get_viewport().set_input_as_handled()
		return
	# 打字进行中：点击面板或按确认键跳过当前行的逐字等待（优化包C-4）。
	if _typing:
		if event.is_action_pressed(ACTION_SKIP):
			skip_typing()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			skip_typing()
			get_viewport().set_input_as_handled()


# 逐条打出本轮全部回复；每条先说的人换成立绘 talk，说完回 idle。
func _type_all(messages: Array) -> void:
	for message_value in messages:
		if not _open:
			return
		if typeof(message_value) != TYPE_DICTIONARY:
			continue
		var message: Dictionary = message_value
		var mentor_id: String = str(message.get(K_MENTOR_ID, ""))
		var text: String = str(message.get(K_TEXT, ""))
		if text.strip_edges().is_empty():
			continue
		_show_mentor(mentor_id, MODE_TALK)
		await _type_line(_display_name(mentor_id), text)
		_show_mentor(mentor_id, MODE_IDLE)
	all_messages_finished.emit()


# 逐字打字（AC2）：每帧追加一个字符，速度可调；收到跳过请求时立即补全整行。
# 打字中途行保持纯文本（不含 bbcode），整行说完才着色——
# 跳过打字的中途长度断言依赖纯文本态（2026-08-03 着色增强的回归约束）。
func _type_line(speaker: String, text: String) -> void:
	_typing = true
	_skip_typing = false
	var label: RichTextLabel = _append_line(speaker, "", false)
	_typing_label = label
	_typing_speaker = speaker
	_typing_full = text
	var shown: String = ""
	for i in text.length():
		if not _open:
			break
		if _skip_typing:
			# skip_typing() 已同步补全上屏，这里只结束等待。
			break
		shown += text[i]
		label.text = _line_text(speaker, shown)
		_scroll_to_bottom()
		var per_char: float = 1.0 / maxf(typing_chars_per_second, MIN_TYPING_SPEED)
		if per_char > 0.0001:
			await get_tree().create_timer(per_char).timeout
	if _open and not _skip_typing:
		_finalize_mentor_line(label, speaker, text)
	_typing_label = null
	_typing_full = ""
	_skip_typing = false
	_typing = false


# 对话行（2026-08-03 着色增强）：RichText + bbcode。
# 玩家行右对齐、整体着色、带「我」前缀，一次成稿；导师行先纯文本打字、说完着色。
func _append_line(speaker: String, text: String, is_player: bool) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_player:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.text = _player_line_bbcode(text)
	else:
		label.text = _line_text(speaker, text)
	_list.add_child(label)
	_scroll_to_bottom()
	return label


# 导师行定稿：姓名金色加粗 + 正文，双方内容都过 bbcode 转义（注入安全）。
func _finalize_mentor_line(label: RichTextLabel, speaker: String, full_text: String) -> void:
	if label == null or not is_instance_valid(label):
		return
	if speaker.is_empty():
		label.text = _escape_bbcode(full_text)
	else:
		label.text = "[color=%s][b]%s[/b][/color]: %s" % [
			COLOR_MENTOR_NAME, _escape_bbcode(speaker), _escape_bbcode(full_text)
		]


# 玩家行成稿：整体淡蓝 + 「我」前缀加粗（前缀文案在 ui_strings，NFR-04）。
func _player_line_bbcode(text: String) -> String:
	var prefix: String = _ui_string(UI_PLAYER_LABEL_KEY)
	var body: String = _escape_bbcode(text)
	if prefix.is_empty():
		return "[color=%s]%s[/color]" % [COLOR_PLAYER, body]
	return "[color=%s][b]%s[/b]: %s[/color]" % [COLOR_PLAYER, _escape_bbcode(prefix), body]


# bbcode 注入防护：玩家输入与 LLM 回复里的方括号一律转义，只作文本渲染。
func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


func _line_text(speaker: String, text: String) -> String:
	if speaker.is_empty():
		return text
	return "%s: %s" % [speaker, text]


# 立绘与名称跟随当前说话的导师（班主任首接时立绘就是班主任，FR-M-04）。
func _show_mentor(mentor_id: String, mode: String) -> void:
	_avatar_mode = mode
	_name_label.text = _display_name(mentor_id)
	var path: String = (
		_registry.avatar_talk_of(mentor_id)
		if mode == MODE_TALK
		else _registry.avatar_idle_of(mentor_id)
	)
	_avatar.texture = Art.texture_or_placeholder(path, AVATAR_SIZE, mentor_id + mode)


func _display_name(mentor_id: String) -> String:
	var full: String = "%s %s" % [_registry.name_of(mentor_id), _registry.title_of(mentor_id)]
	return full.strip_edges()


# 玩家输入统一经 LLMClient.sanitize_input 清理（安全红线：截断 + 去控制字符）。
func _sanitize(raw: String) -> String:
	if _client != null and _client.has_method("sanitize_input"):
		return str(_client.sanitize_input(raw))
	return raw.strip_edges()


func _on_send_pressed() -> void:
	_submit(_input.text)


func _on_text_submitted(text: String) -> void:
	_submit(text)


func _submit(raw: String) -> void:
	_input.clear()
	submit(raw)


func _on_send_requested(raw: String) -> void:
	await send_text(raw)


# 设置入口（包A-3：FR-M-10 可达性）：经 ui_manager 打开配置面板，参与互斥裁决
# （config 打开时本面板被 close_active 关掉）；无 ui_manager（单测独立实例化）时不动作。
func _on_config_pressed() -> void:
	var manager: Node = _find_ui_manager()
	if manager == null:
		return
	manager.open(PANEL_CONFIG)


# 沿祖先链找世界总装里的 UIManager；独立实例化（测试）时找不到返回 null。
func _find_ui_manager() -> Node:
	var node: Node = self
	while node != null:
		var candidate: Node = node.get_node_or_null(UI_MANAGER_REL)
		if candidate != null and candidate.has_method("open"):
			return candidate
		node = node.get_parent()
	return null


func _scroll_to_bottom() -> void:
	_scroll.set_deferred("scroll_vertical", SCROLL_TO_BOTTOM)


func _ui_string(key: String) -> String:
	var gm: Node = get_node_or_null(GAME_MANAGER_PATH)
	if gm == null:
		return key
	return gm.get_ui_string(key)
