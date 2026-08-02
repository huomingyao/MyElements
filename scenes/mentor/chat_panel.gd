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
# Esc 对应的输入动作（FR-C-01 输入映射）。
const ACTION_CLOSE: String = "pause"

const MODE_IDLE: String = "idle"
const MODE_TALK: String = "talk"
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
var _open: bool = false
var _busy: bool = false
var _typing: bool = false
var _avatar_mode: String = MODE_IDLE

@onready var _avatar: TextureRect = %MentorAvatar
@onready var _name_label: Label = %MentorName
@onready var _scroll: ScrollContainer = %HistoryScroll
@onready var _list: VBoxContainer = %HistoryList
@onready var _input: LineEdit = %InputLine
@onready var _send_button: Button = %SendButton
@onready var _close_button: Button = %CloseButton


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
	_input.text_submitted.connect(_on_text_submitted)
	_send_button.pressed.connect(_on_send_pressed)
	_close_button.pressed.connect(close_chat)
	send_requested.connect(_on_send_requested)


# 测试注入口（SPEC-06 §3）：注入带 set_reply_provider 的 router 后不发真实请求。
func set_router(router: RefCounted) -> void:
	_router = router


# 测试注入口：注入假客户端后不碰真实 LLMClient（也就完全不碰网络与 user://）。
func set_client(client: Node) -> void:
	_client = client


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


func is_typing() -> bool:
	return _typing


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
	await _type_all(messages)
	_busy = false
	_send_button.disabled = false


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(ACTION_CLOSE):
		close_chat()
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


# 逐字打字（AC2）：每帧追加一个字符，速度可调。
func _type_line(speaker: String, text: String) -> void:
	_typing = true
	var label: Label = _append_line(speaker, "", false)
	var shown: String = ""
	for i in text.length():
		if not _open:
			break
		shown += text[i]
		label.text = _line_text(speaker, shown)
		_scroll_to_bottom()
		var per_char: float = 1.0 / maxf(typing_chars_per_second, MIN_TYPING_SPEED)
		if per_char > 0.0001:
			await get_tree().create_timer(per_char).timeout
	_typing = false


func _append_line(speaker: String, text: String, is_player: bool) -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_player:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.text = _line_text(speaker, text)
	_list.add_child(label)
	_scroll_to_bottom()
	return label


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


func _scroll_to_bottom() -> void:
	_scroll.set_deferred("scroll_vertical", SCROLL_TO_BOTTOM)


func _ui_string(key: String) -> String:
	var gm: Node = get_node_or_null(GAME_MANAGER_PATH)
	if gm == null:
		return key
	return gm.get_ui_string(key)
