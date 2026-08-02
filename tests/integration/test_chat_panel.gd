# IT-M02 / FR-M-02：底部聊天框 UI。
# 断言：打开时世界不暂停不切场景（AC1）；逐字打字 + 立绘 talk/idle 切换（AC2）；
# 记录可滚动且保留全部消息（AC3）；Esc/关闭按钮收起（AC4）。
# 安全：输入先过 LLMClient.sanitize_input（注入假客户端，不发真实请求）；
# LLM 返回只做文本渲染。回复来源用 MentorRouter.set_reply_provider 注入 stub。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")
const RouterScript: GDScript = preload("res://scripts/mentor/mentor_router.gd")

const PANEL_PATH: String = "res://scenes/mentor/chat_panel.tscn"

const N_AVATAR: String = "MentorAvatar"
const N_NAME: String = "MentorName"
const N_SCROLL: String = "HistoryScroll"
const N_LIST: String = "HistoryList"
const N_INPUT: String = "InputLine"
const N_SEND: String = "SendButton"
const N_CLOSE: String = "CloseButton"

const INSTANT_SPEED: float = 100000.0
const TYPE_TIMEOUT_FRAMES: int = 1200


# 假客户端：只记录 sanitize_input 收到了什么，模仿其清理规则，绝不碰网络与磁盘。
class FakeClient:
	extends Node

	var sanitized_calls: Array = []

	func sanitize_input(raw: String) -> String:
		sanitized_calls.append(raw)
		var out: String = ""
		for i in raw.length():
			var code: int = raw.unicode_at(i)
			if code < 32 or code == 127:
				out += " "
				continue
			out += raw[i]
		return out.strip_edges()


var _panel: Node = null
var _client: Node = null
var _router: RefCounted = null
var _provider_calls: Array = []
var _replies: Dictionary = {}


func before_each() -> void:
	_panel = null
	_client = null
	_router = null
	_provider_calls = []
	if not ResourceLoader.exists(PANEL_PATH):
		fail_test("尚未实现 %s（FR-M-02 / TP-13）" % PANEL_PATH)
		return
	_client = FakeClient.new()
	add_child_autofree(_client)
	_router = RouterScript.new()
	_replies = {
		"monitor": "别慌。@化学老师 你来把原理讲透！",
		"chem": "氢气混有空气时点燃会爆炸。2H₂+O₂=点燃=2H₂O",
	}
	var provider: Callable = func(mentor_id: String, _question: String) -> String:
		_provider_calls.append(mentor_id)
		return str(_replies.get(mentor_id, ""))
	_router.set_reply_provider(provider)
	_panel = (load(PANEL_PATH) as PackedScene).instantiate()
	if not _panel.has_method("set_client") or not _panel.has_method("set_router"):
		fail_test("ChatPanel 应有 set_client()/set_router() 注入口（可测性约束）")
		_panel.free()
		_panel = null
		return
	_panel.set_client(_client)
	_panel.set_router(_router)
	_panel.typing_chars_per_second = INSTANT_SPEED
	add_child_autofree(_panel)
	await wait_process_frames(1)


# 缺实现/缺方法时记断言失败并跳过，避免 before_each 崩掉后 GUT 误报通过。
func _skip_unless(method_names: Array) -> bool:
	if _panel == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not _panel.has_method(method_name):
			fail_test("ChatPanel 应有 %s()" % method_name)
			return true
	return false


func _node(unique_name: String) -> Node:
	var found: Node = _panel.get_node_or_null(NodePath("%%%s" % unique_name))
	assert_not_null(found, "ChatPanel 应有唯一名节点 %%%s" % unique_name)
	return found


func _wait_typing_done() -> void:
	var frames: int = 0
	while bool(_panel.is_typing()) and frames < TYPE_TIMEOUT_FRAMES:
		await wait_process_frames(1)
		frames += 1
	assert_false(_panel.is_typing(), "打字应在有限帧内完成")


func _history_texts() -> Array:
	var out: Array = []
	var list: Node = _panel.get_node_or_null(NodePath("%%%s" % N_LIST))
	if list == null:
		return out
	for child in list.get_children():
		out.append(str(child.get("text")))
	return out


func _mentor_name(id: String) -> String:
	for row_value in Fixture.rows_of("mentors.json"):
		var row: Dictionary = row_value
		if str(row.get("id", "")) == id:
			return str(row.get("name", ""))
	return ""


# AC1：打开聊天框世界不暂停、不切换场景。
func test_open_chat_keeps_world_running_same_scene() -> void:
	if _skip_unless(["open_chat", "is_chat_open"]):
		return
	var scene_before: Node = get_tree().current_scene
	assert_false(get_tree().paused, "前置：世界本就不应暂停")
	_panel.open_chat("chem")
	assert_true(_panel.is_chat_open(), "open_chat 后聊天框应处于打开状态")
	assert_true(_panel.visible, "打开后应可见")
	assert_false(get_tree().paused, "聊天框打开时世界不暂停（AC1）")
	assert_eq(get_tree().current_scene, scene_before, "不切换场景（AC1）")
	await _panel.send_text("为什么氢气会爆炸")
	assert_false(get_tree().paused, "收发消息全过程中世界也不暂停（AC1）")
	assert_eq(get_tree().current_scene, scene_before, "收发消息不切换场景（AC1）")


# AC2：回复逐字打字；打字期间立绘为 talk，结束切回 idle。
func test_typing_switches_avatar_talk_then_idle() -> void:
	if _skip_unless(["open_chat", "send_text", "is_typing", "avatar_mode"]):
		return
	_panel.open_chat("chem")
	_panel.typing_chars_per_second = 2.0
	_panel.submit("为什么氢气会爆炸")
	await wait_process_frames(4)
	assert_true(_panel.is_typing(), "慢速下长回复应仍在逐字打字")
	assert_eq(_panel.avatar_mode(), "talk", "打字期间立绘应为 talk（AC2）")
	_panel.typing_chars_per_second = INSTANT_SPEED
	await _wait_typing_done()
	assert_eq(_panel.avatar_mode(), "idle", "打字结束立绘应切回 idle（AC2）")


# AC2：逐字效果是渐进的——打字中途的文本比完整回复短。
func test_text_grows_gradually_while_typing() -> void:
	if _skip_unless(["open_chat", "send_text", "is_typing"]):
		return
	_panel.open_chat("chem")
	_panel.typing_chars_per_second = 2.0
	_panel.submit("为什么氢气会爆炸")
	await wait_process_frames(4)
	var mid_texts: Array = _history_texts()
	var longest_mid: int = 0
	for text_value in mid_texts:
		longest_mid = maxi(longest_mid, str(text_value).length())
	var full_len: int = str(_replies["monitor"]).length()
	assert_true(
		longest_mid < full_len,
		"打字中途显示的字符应少于完整回复（逐字效果）：%d vs %d" % [longest_mid, full_len]
	)
	_panel.typing_chars_per_second = INSTANT_SPEED
	await _wait_typing_done()


# AC3：对话记录放在 ScrollContainer 里（可滚动），且保留本次会话全部消息。
func test_history_scrollable_and_keeps_whole_session() -> void:
	if _skip_unless(["open_chat", "send_text", "history_count"]):
		return
	var scroll: Node = _node(N_SCROLL)
	if scroll == null:
		return
	assert_true(scroll is ScrollContainer, "对话记录应可滚动（AC3）")
	_panel.open_chat("chem")
	await _panel.send_text("第一问")
	var first_count: int = int(_panel.history_count())
	# 玩家一条 + 班主任一条 + 化学老师一条。
	assert_true(first_count >= 3, "一轮问答至少留下 3 条记录，实际 %d" % first_count)
	await _panel.send_text("第二问")
	assert_true(
		int(_panel.history_count()) > first_count,
		"第二轮后全部历史消息都应保留（AC3）"
	)


# AC3 + FR-M-04：首条回复来自班主任，记录中导师姓名来自 mentors.json（数据驱动）。
func test_first_reply_is_monitor_and_names_from_data() -> void:
	if _skip_unless(["open_chat", "send_text"]):
		return
	_panel.open_chat("chem")
	await _panel.send_text("为什么氢气会爆炸")
	assert_true(_provider_calls.size() >= 1, "应向回复来源请求过")
	assert_eq(_provider_calls[0], "monitor", "首接必须是班主任（FR-M-04 AC1）")
	var monitor_name: String = _mentor_name("monitor")
	var chem_name: String = _mentor_name("chem")
	assert_false(monitor_name.is_empty(), "mentors.json 应有 monitor.name")
	var texts: Array = _history_texts()
	var joined: String = "\n".join(texts)
	assert_true(joined.contains(monitor_name), "记录中应出现数据表里的班主任姓名")
	assert_true(joined.contains(chem_name), "记录中应出现数据表里的化学老师姓名")
	assert_true(joined.contains(str(_replies["chem"])), "记录中应有化学老师的回复全文")


# AC4：Esc 收起聊天框，玩家恢复操作。
func test_esc_closes_chat() -> void:
	if _skip_unless(["open_chat", "is_chat_open"]):
		return
	_panel.open_chat("chem")
	var event: InputEventAction = InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	_panel._unhandled_input(event)
	assert_false(_panel.is_chat_open(), "Esc 应收起聊天框（AC4）")
	assert_false(_panel.visible, "收起后不可见")


# AC4：关闭按钮收起聊天框。
func test_close_button_closes_chat() -> void:
	if _skip_unless(["open_chat", "is_chat_open"]):
		return
	_panel.open_chat("chem")
	var button: Node = _node(N_CLOSE)
	if button == null:
		return
	button.pressed.emit()
	assert_false(_panel.is_chat_open(), "关闭按钮应收起聊天框（AC4）")
	assert_false(_panel.visible)


# 安全（FR-M-03）：玩家输入先交给 LLMClient.sanitize_input，显示文本不含换行。
func test_input_is_sanitized_before_sending() -> void:
	if _skip_unless(["open_chat", "send_text"]):
		return
	_panel.open_chat("chem")
	await _panel.send_text("氢气\n爆炸?")
	assert_eq(
		_client.sanitized_calls, ["氢气\n爆炸?"],
		"原始输入应先交给 sanitize_input（安全红线）"
	)
	var texts: Array = _history_texts()
	assert_false(texts.is_empty(), "应有历史记录")
	for text_value in texts:
		assert_false(str(text_value).contains("\n"), "显示文本不许含控制字符")


# 安全（FR-M-03 AC2）：清理后为空的输入不发起任何请求。
func test_empty_after_sanitize_sends_nothing() -> void:
	if _skip_unless(["open_chat", "send_text"]):
		return
	_panel.open_chat("chem")
	await _panel.send_text("\n\t  ")
	assert_eq(_provider_calls.size(), 0, "清理后为空不发起请求（FR-M-03 AC2）")


# 立绘未交付（P4 排队中）时用生成占位图，不崩溃、不留空白。
func test_missing_avatar_falls_back_to_placeholder() -> void:
	if _skip_unless(["open_chat"]):
		return
	_panel.open_chat("chem")
	var avatar: TextureRect = _node(N_AVATAR) as TextureRect
	if avatar == null:
		return
	assert_not_null(avatar.texture, "立绘缺失时应显示占位图（SPEC-04 §1 兜底约定）")


# 输入框占位符来自 ui_strings.chat_placeholder（NFR-04）。
func test_input_placeholder_from_ui_strings() -> void:
	if _panel == null:
		return
	var input: LineEdit = _node(N_INPUT) as LineEdit
	if input == null:
		return
	var expected: String = str(Fixture.read_object("ui_strings.json").get("chat_placeholder", ""))
	assert_false(expected.is_empty(), "ui_strings.json 应有 chat_placeholder")
	assert_eq(input.placeholder_text, expected, "占位符应来自 ui_strings.chat_placeholder")


# NFR-04：导师场景全部逻辑脚本零中文字面量（诊断日志与注释除外，按 SPEC-01 §10 口径）。
func test_mentor_scripts_have_no_hardcoded_chinese() -> void:
	var paths: Array = [
		"res://scenes/mentor/academy.gd",
		"res://scenes/mentor/mentor_npc.gd",
		"res://scenes/mentor/chat_panel.gd",
		"res://scenes/mentor/mentor_registry.gd",
		"res://scenes/mentor/mentor_art.gd",
	]
	for path_value in paths:
		var path: String = str(path_value)
		if not FileAccess.file_exists(path):
			fail_test("缺少实现文件 %s" % path)
			continue
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var stripped: String = str(line).strip_edges()
			if stripped.begins_with("#"):
				continue
			var is_log: bool = (
				stripped.contains("push_warning(")
				or stripped.contains("push_error(")
				or stripped.contains("print(")
			)
			if is_log:
				continue
			assert_false(
				_has_cjk(stripped),
				"逻辑代码里不许硬编码中文（NFR-04，%s）：%s" % [path, stripped]
			)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
