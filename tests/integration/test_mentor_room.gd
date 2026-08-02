# 导师室独立页（2026-08-02）：教室场景图 + 四位导师立绘卡（数据驱动 mentors.json）；
# 点击导师卡开聊；面板契约 open/close/is_open；文案全部来自数据表（NFR-04）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const ROOM_SCENE: String = "res://scenes/mentor/mentor_room.tscn"
const ROOM_SCRIPT: String = "res://scenes/mentor/mentor_room.gd"
const MENTOR_IDS: Array[String] = ["chem", "monitor", "assistant", "think"]

var _room: Node = null


func before_each() -> void:
	_room = null
	if not ResourceLoader.exists(ROOM_SCENE):
		fail_test("尚未实现 %s" % ROOM_SCENE)
		return
	_room = (load(ROOM_SCENE) as PackedScene).instantiate()
	add_child_autofree(_room)
	await wait_process_frames(2)


func _chat() -> Node:
	return _room.get_node_or_null(NodePath("%ChatPanel"))


# 四张导师卡齐全，卡名与 mentors.json 的 id 一一对应，姓名文案来自数据表。
func test_four_mentor_cards_built_from_data() -> void:
	if _room == null:
		return
	var rows: Array = Fixture.rows_of("mentors.json")
	assert_eq(rows.size(), 4, "mentors.json 应有 4 位导师")
	for row in rows:
		var mentor_id: String = str(row.get("id", ""))
		var card: Node = _room.mentor_card(mentor_id)
		assert_not_null(card, "应有导师卡 Mentor_%s" % mentor_id)
		if card == null:
			continue
		var label: Node = card.find_child("NameLabel", true, false)
		assert_not_null(label, "%s 卡应有 NameLabel" % mentor_id)
		if label != null:
			assert_true(
				str(label.text).contains(str(row.get("name", ""))),
				"%s 卡名应取自 mentors.json：%s" % [mentor_id, str(label.text)]
			)


# 立绘：四张卡都挂上了纹理（P4 美术接入验证）。
func test_cards_have_portrait_textures() -> void:
	if _room == null:
		return
	for mentor_id: String in MENTOR_IDS:
		var card: Node = _room.mentor_card(mentor_id)
		if card == null:
			continue
		var portrait: Node = card.find_child("Portrait", true, false)
		assert_not_null(portrait, "%s 卡应有 Portrait" % mentor_id)
		if portrait is TextureRect:
			assert_not_null((portrait as TextureRect).texture, "%s 立绘纹理应已加载" % mentor_id)


# 点击导师卡 → 聊天框以该导师开场。
func test_clicking_card_opens_chat() -> void:
	if _room == null:
		return
	var chat: Node = _chat()
	assert_not_null(chat, "导师室应内嵌聊天框")
	if chat == null:
		return
	for mentor_id: String in MENTOR_IDS:
		var card: Node = _room.mentor_card(mentor_id)
		if card == null:
			continue
		card.pressed.emit()
		assert_true(bool(chat.is_chat_open()), "点击 %s 应开聊" % mentor_id)
		chat.close_chat()
		assert_false(bool(chat.is_chat_open()), "收尾：聊天框应能关闭")


# 面板契约：open/close/is_open；close 连带收起开着的聊天框。
func test_panel_contract() -> void:
	if _room == null:
		return
	var chat: Node = _chat()
	_room.open()
	assert_true(_room.is_open(), "open() 后 is_open 应为真")
	assert_true(_room.visible, "open() 后页面应可见")
	var card: Node = _room.mentor_card("chem")
	if card != null and chat != null:
		card.pressed.emit()
		assert_true(bool(chat.is_chat_open()), "前置：聊天框开着")
	_room.close()
	assert_false(_room.is_open(), "close() 后 is_open 应为假")
	assert_false(_room.visible, "close() 后页面应隐藏")
	if chat != null:
		assert_false(bool(chat.is_chat_open()), "close() 应连带收起聊天框")


# NFR-04：逻辑代码里不许出现中文字面量（注释与日志除外）。
func test_room_script_has_no_hardcoded_chinese() -> void:
	var text: String = FileAccess.get_file_as_string(ROOM_SCRIPT)
	assert_false(text.is_empty(), "应能读到 %s" % ROOM_SCRIPT)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("push_warning(") or stripped.contains("push_error("):
			continue
		assert_false(_has_cjk(stripped), "逻辑代码里不许硬编码中文（NFR-04）：%s" % stripped)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
