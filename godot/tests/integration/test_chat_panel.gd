# IT-M02 / FR-M-02：底部聊天框 UI。
# 断言：打开时世界不暂停不切场景（AC1）；逐字打字 + 立绘 talk/idle 切换（AC2）；
# 记录可滚动且保留全部消息（AC3）；Esc/关闭按钮收起（AC4）。
# 安全：输入先过 LLMClient.sanitize_input（注入假客户端，不发真实请求）；
# LLM 返回只做文本渲染。回复来源用 MentorRouter.set_reply_provider 注入 stub。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")
const RouterScript: GDScript = preload("res://scripts/mentor/mentor_router.gd")

const PANEL_PATH: String = "res://scenes/mentor/chat_panel.tscn"
const UI_MANAGER_SCRIPT: String = "res://scenes/main/ui_manager.gd"

const N_AVATAR: String = "MentorAvatar"
const N_NAME: String = "MentorName"
const N_SCROLL: String = "HistoryScroll"
const N_LIST: String = "HistoryList"
const N_INPUT: String = "InputLine"
const N_SEND: String = "SendButton"
const N_CLOSE: String = "CloseButton"
const N_CONFIG: String = "ConfigButton"

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


# 配置面板替身：open/close/is_open 契约（SPEC-03 §8），断言设置入口的裁决行为。
class FakeConfigPanel:
	extends Control
	var _open: bool = false

	func open() -> void:
		_open = true
		visible = true

	func close() -> void:
		_open = false
		visible = false

	func is_open() -> bool:
		return _open


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


# AC2：逐字效果是渐进的——打字中途的当前行文本比完整回复短。
# 只看最后一行（正在打字的导师行）；玩家提问行已是着色成稿，不参与长度比较（2026-08-03 着色增强）。
func test_text_grows_gradually_while_typing() -> void:
	if _skip_unless(["open_chat", "send_text", "is_typing"]):
		return
	_panel.open_chat("chem")
	_panel.typing_chars_per_second = 2.0
	_panel.submit("为什么氢气会爆炸")
	await wait_process_frames(4)
	var mid_texts: Array = _history_texts()
	assert_false(mid_texts.is_empty(), "应有历史记录")
	var typing_line: String = str(mid_texts[mid_texts.size() - 1])
	var full_len: int = str(_replies["monitor"]).length()
	assert_true(
		typing_line.length() < full_len,
		"打字中途当前行字符应少于完整回复（逐字效果）：%d vs %d" % [typing_line.length(), full_len]
	)
	_panel.typing_chars_per_second = INSTANT_SPEED
	await _wait_typing_done()


# 优化包C-4：打字进行中点击面板或按确认键，当前行立即显示完整文本，不再等逐字打完。
# 输入处理是同步的：事件送达的同一帧文本就必须补全（修复前文本仍是逐字残段，断言必失败）。
func test_click_during_typing_skips_to_full_line() -> void:
	if _skip_unless(["open_chat", "send_text", "is_typing"]):
		return
	# 单条长回复：不带 @，派活对象的回复置空，保证本轮只有班主任一条。
	_replies = {"monitor": "这是一段足够长的回复，用来验证打字机可以被跳过而立即显示完整内容，不用干等好几秒。"}
	_panel.open_chat("monitor")
	_panel.typing_chars_per_second = 2.0
	_panel.submit("今天午饭吃什么")
	await wait_process_frames(4)
	assert_true(_panel.is_typing(), "前置：慢速下长回复应仍在逐字打字")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_panel._unhandled_input(click)
	var texts: Array = _history_texts()
	assert_false(texts.is_empty(), "应有历史记录")
	assert_true(
		str(texts[texts.size() - 1]).contains(str(_replies["monitor"])),
		"点击跳过的同一帧当前行就应显示完整文本"
	)
	_panel.typing_chars_per_second = INSTANT_SPEED
	await _wait_typing_done()
	_panel.close_chat()


# 确认键（ui_accept）同样能跳过打字。
func test_accept_key_during_typing_skips_to_full_line() -> void:
	if _skip_unless(["open_chat", "send_text", "is_typing"]):
		return
	_replies = {"monitor": "另一段足够长的回复，用来验证确认键也能跳过打字机，立即显示完整内容。"}
	_panel.open_chat("monitor")
	_panel.typing_chars_per_second = 2.0
	_panel.submit("今天晚饭吃什么")
	await wait_process_frames(4)
	assert_true(_panel.is_typing(), "前置：慢速下应仍在逐字打字")
	var key: InputEventAction = InputEventAction.new()
	key.action = "ui_accept"
	key.pressed = true
	_panel._unhandled_input(key)
	var texts: Array = _history_texts()
	assert_false(texts.is_empty(), "应有历史记录")
	assert_true(
		str(texts[texts.size() - 1]).contains(str(_replies["monitor"])),
		"确认键跳过的同一帧当前行就应显示完整文本"
	)
	_panel.typing_chars_per_second = INSTANT_SPEED
	await _wait_typing_done()
	_panel.close_chat()


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


# ui_manager 面板契约（SPEC-03 §8，收口 W1）：open/close/is_open 委托既有聊天方法，
# 不改其签名；无参 open() 按「班主任首接」（FR-M-04）落到默认导师 monitor。
# 契约缺失时 ui_manager.open("chat")/close_active() 会在运行时报错。
func test_ui_manager_panel_contract_delegates_to_chat_methods() -> void:
	if _skip_unless(["open", "close", "is_open", "is_chat_open"]):
		return
	assert_false(_panel.is_open(), "初始契约 is_open 应为假")
	_panel.open()
	assert_true(_panel.is_open(), "契约 open() 应打开聊天框")
	assert_true(_panel.is_chat_open(), "open() 应委托到 open_chat")
	assert_true(_panel.visible, "打开后应可见")
	var name_label: Label = _node(N_NAME) as Label
	if name_label != null:
		var monitor_name: String = _mentor_name("monitor")
		assert_false(monitor_name.is_empty(), "mentors.json 应有 monitor（班主任）")
		assert_true(name_label.text.contains(monitor_name),
			"无参 open() 应按班主任首接落到 monitor（FR-M-04）：%s" % name_label.text)
	_panel.close()
	assert_false(_panel.is_open(), "契约 close() 应关闭聊天框")
	assert_false(_panel.is_chat_open(), "close() 应委托到 close_chat")
	assert_false(_panel.visible, "关闭后应隐藏")


# ==== 包A-3：设置入口（FR-M-10 可达性）====

# 在带 UILayer/UIManager 的世界骨架里新挂一个聊天框（裁决查找按祖先链，须先入骨架再 _ready）。
func _spawn_rig_with_panel() -> Dictionary:
	var rig: Node = Node.new()
	add_child_autofree(rig)
	var ui_layer: Node = Node.new()
	ui_layer.name = "UILayer"
	rig.add_child(ui_layer)
	var manager: Node = (load(UI_MANAGER_SCRIPT) as GDScript).new()
	manager.name = "UIManager"
	ui_layer.add_child(manager)
	var client: Node = FakeClient.new()
	rig.add_child(client)
	var router: RefCounted = RouterScript.new()
	router.set_reply_provider(func(_m: String, _q: String) -> String: return "回复")
	var panel: Node = (load(PANEL_PATH) as PackedScene).instantiate()
	panel.set_client(client)
	panel.set_router(router)
	panel.typing_chars_per_second = INSTANT_SPEED
	rig.add_child(panel)
	return {"rig": rig, "manager": manager, "panel": panel}


# 设置按钮经 ui_manager 打开 config 面板；互斥：config 打开时聊天框被关掉（SPEC-03 §8）。
func test_config_button_opens_config_panel_via_ui_manager() -> void:
	var rig: Dictionary = _spawn_rig_with_panel()
	await wait_process_frames(1)
	var manager: Node = rig["manager"]
	var panel: Node = rig["panel"]
	var config: Control = FakeConfigPanel.new()
	add_child_autofree(config)
	manager.register_panel("chat", panel, false)
	manager.register_panel("config", config, true)
	manager.open("chat")
	assert_true(manager.is_open("chat"), "前提：聊天框经 ui_manager 打开")
	var button: Node = panel.get_node_or_null(^"%ConfigButton")
	assert_not_null(button, "聊天框应有 %%ConfigButton 设置入口（FR-M-10 可达性）")
	if button == null:
		return
	button.pressed.emit()
	assert_true(manager.is_open("config"), "设置按钮应经 ui_manager 打开 config 面板")
	assert_true((config as FakeConfigPanel).is_open(), "config 面板应被打开")
	assert_false(panel.is_chat_open(), "互斥：config 打开时聊天框应被 ui_manager 关掉（SPEC-03 §8）")


# 设置按钮文案来自 ui_strings.chat_config（NFR-04）。
func test_config_button_text_comes_from_ui_strings() -> void:
	if _panel == null:
		return
	var button: Node = _node(N_CONFIG)
	if button == null:
		return
	var expected: String = str(Fixture.read_object("ui_strings.json").get("chat_config", ""))
	assert_false(expected.is_empty(), "ui_strings.json 应有 chat_config")
	assert_eq(str(button.get("text")), expected, "设置按钮文案应来自 ui_strings.chat_config")


# 无 ui_manager（独立实例化）时按设置按钮不崩溃、不改变聊天框状态。
func test_config_button_is_safe_without_ui_manager() -> void:
	if _skip_unless(["open_chat", "is_chat_open"]):
		return
	_panel.open_chat("chem")
	var button: Node = _node(N_CONFIG)
	if button == null:
		return
	button.pressed.emit()
	assert_true(_panel.is_chat_open(), "无裁决器时设置按钮不应影响聊天框")


# pending 导师（包A-4）：academy 注入被交互的导师后，无参 open() 以该导师开场；
# 未注入时维持原语义——班主任首接（FR-M-04）。
func test_pending_mentor_is_consumed_by_open() -> void:
	if _skip_unless(["open", "is_open", "set_pending_mentor"]):
		return
	_panel.set_pending_mentor("chem")
	_panel.open()
	var name_label: Label = _node(N_NAME) as Label
	if name_label != null:
		assert_true(
			name_label.text.contains(_mentor_name("chem")),
			"pending 导师应作为开场导师：%s" % name_label.text
		)
	_panel.close()
	# 消费即清：再次 open() 落回班主任首接。
	_panel.open()
	if name_label != null:
		assert_true(
			name_label.text.contains(_mentor_name("monitor")),
			"pending 消费后应落回班主任首接（FR-M-04）：%s" % name_label.text
		)
	_panel.close()


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


# ==== 问答显示着色增强（2026-08-03，FR-M-02 呈现层优化）====
# 导师行：RichText + 导师名加粗着色；玩家行：右对齐 + 区分色 + 「我」前缀；
# bbcode 注入必须转义；打字中途保持纯文本（跳过打字的长度断言依赖它）。

# 导师回复行用 RichTextLabel，导师名加粗 + 着色，正文完整可解析。
func test_mentor_line_is_richtext_with_colored_bold_name() -> void:
	if _skip_unless(["open_chat", "send_text"]):
		return
	_panel.open_chat("chem")
	await _panel.send_text("为什么氢气会爆炸")
	var list: Node = _node(N_LIST)
	if list == null:
		return
	var mentor_line: Node = null
	for child in list.get_children():
		if str(child.get("text")).contains(str(_replies["chem"])):
			mentor_line = child
	assert_not_null(mentor_line, "记录中应有化学老师的回复行")
	if mentor_line == null:
		return
	assert_true(mentor_line is RichTextLabel, "对话行应为 RichTextLabel（着色增强）")
	if not (mentor_line is RichTextLabel):
		return
	var rich: RichTextLabel = mentor_line as RichTextLabel
	assert_true(rich.bbcode_enabled, "对话行应启用 bbcode")
	var raw: String = rich.text
	var chem_name: String = _mentor_name("chem")
	assert_true(raw.contains("[b]"), "导师名应加粗：%s" % raw)
	assert_true(raw.contains("[color="), "导师名应着色：%s" % raw)
	var parsed: String = rich.get_parsed_text()
	assert_true(parsed.contains(chem_name), "解析文本应含导师姓名：%s" % parsed)
	assert_true(parsed.contains(str(_replies["chem"])), "解析文本应含回复全文：%s" % parsed)


# 玩家提问行：右对齐 + 着色 + 带玩家前缀（ui_strings 的 chat_player_label），与导师行一眼区分。
func test_player_line_is_right_aligned_colored_with_prefix() -> void:
	if _skip_unless(["open_chat", "send_text"]):
		return
	_panel.open_chat("chem")
	await _panel.send_text("为什么氢气会爆炸")
	var list: Node = _node(N_LIST)
	if list == null or list.get_child_count() == 0:
		return
	var first: Node = list.get_child(0)
	assert_true(first is RichTextLabel, "玩家行应为 RichTextLabel（着色增强）")
	if not (first is RichTextLabel):
		return
	var rich: RichTextLabel = first as RichTextLabel
	assert_eq(rich.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "玩家行应右对齐")
	assert_true(rich.text.contains("[color="), "玩家行应着色：%s" % rich.text)
	var gm: Node = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	var prefix: String = ""
	if gm != null:
		prefix = str(gm.get_ui_string("chat_player_label"))
	assert_false(prefix.is_empty(), "ui_strings 应有 chat_player_label（玩家行前缀）")
	assert_true(rich.get_parsed_text().contains(prefix), "玩家行解析文本应带前缀：%s" % rich.get_parsed_text())
	assert_true(rich.get_parsed_text().contains("为什么氢气会爆炸"), "玩家行应含提问原文")


# 安全：玩家输入与 LLM 回复里的 bbcode 方括号必须转义，不许被解析成格式。
func test_bbcode_in_content_is_escaped() -> void:
	if _skip_unless(["open_chat", "send_text"]):
		return
	_replies["monitor"] = "看这里[b]加粗注入[/b]别上当"
	_panel.open_chat("monitor")
	await _panel.send_text("提问带[b]方括号[/b]试试")
	var list: Node = _node(N_LIST)
	if list == null:
		return
	for child in list.get_children():
		if not (child is RichTextLabel):
			continue
		var rich: RichTextLabel = child as RichTextLabel
		assert_true(
			rich.text.contains("[lb]") or not rich.text.contains("[b]"),
			"内容里的方括号应转义为 [lb]：%s" % rich.text
		)
		assert_false(
			rich.get_parsed_text().is_empty(),
			"转义后解析文本不应为空"
		)


# 回归：打字中途行保持纯文本（不含 bbcode 标签），完成行才着色——
# 跳过打字的长度断言（test_click/accept_during_typing）依赖纯文本中途态。
func test_mid_typing_line_stays_plain_until_finished() -> void:
	if _skip_unless(["open_chat", "send_text", "is_typing"]):
		return
	_replies = {"monitor": "一段足够长的回复内容，用来验证打字中途不提前注入格式标签，保持纯文本。"}
	_panel.open_chat("monitor")
	_panel.typing_chars_per_second = 2.0
	_panel.submit("随便问点什么")
	await wait_process_frames(4)
	assert_true(_panel.is_typing(), "前置：慢速下应仍在逐字打字")
	var texts: Array = _history_texts()
	assert_false(texts.is_empty(), "应有历史记录")
	# 只断言最后一行（正在打字的导师行）；玩家提问行一次成稿、本来就着色。
	var typing_line: String = str(texts[texts.size() - 1])
	assert_false(typing_line.contains("[color="), "打字中途不应含颜色标签：%s" % typing_line)
	assert_false(typing_line.contains("[b]"), "打字中途不应含加粗标签：%s" % typing_line)
	_panel.typing_chars_per_second = INSTANT_SPEED
	await _wait_typing_done()
