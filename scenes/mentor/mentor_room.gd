# 导师室页面（FR-M-01 独立页）：教室场景图 + 四位导师立绘卡（数据驱动 mentors.json，铁律 4）。
# 两种用法：主菜单学院门整页进入（独立模式，Esc/返回 回主菜单）；
# 世界内 T 键经 ui_manager 模态打开（面板契约 open/close/is_open，关闭走 close_requested）。
extends Control

# 请求关闭（世界内由 ui_manager 收口，与 craft 面板同一模式）。
signal close_requested

const RegistryScript: GDScript = preload("res://scenes/mentor/mentor_registry.gd")

const PORTRAITS: Dictionary = {
	"chem": "res://assets/art/mentor_room/portrait_chem.png",
	"monitor": "res://assets/art/mentor_room/portrait_monitor.png",
	"assistant": "res://assets/art/mentor_room/portrait_assistant.png",
	"think": "res://assets/art/mentor_room/portrait_think.png",
}
const ACTION_MENTOR_ROOM: String = "mentor_room"
const ACTION_PAUSE: String = "pause"
const MAIN_MENU_SCENE: String = "res://scenes/main/main_menu.tscn"
const UI_TITLE: String = "mentor_room_title"
const UI_HINT: String = "mentor_room_hint"
const UI_BACK: String = "mentor_room_back"
const UI_MANAGER_REL: NodePath = ^"UILayer/UIManager"
const PANEL_NAME: String = "mentor_room"

var _open: bool = false
var _standalone: bool = false

@onready var _chat: Control = %ChatPanel
@onready var _mentor_row: HBoxContainer = %MentorRow
@onready var _title: Label = %TitleLabel
@onready var _hint: Label = %HintLabel
@onready var _back: Button = %BackButton


func _ready() -> void:
	_standalone = _find_ui_manager() == null
	_build_mentor_cards()
	_apply_texts()
	_back.pressed.connect(_on_back_pressed)
	# 独立模式（整页进入）直接显示；世界内由 ui_manager 驱动 open()。
	_open = _standalone
	visible = _standalone


# ==== ui_manager 面板契约（SPEC-03 §8）====

func open() -> void:
	_open = true
	visible = true


func close() -> void:
	if _chat.is_chat_open():
		_chat.close_chat()
	_open = false
	visible = false


func is_open() -> bool:
	return _open


# 世界接线入口：注入共享 HydrogenEvent 给聊天框（FR-G-09 AC1）。
func set_hydrogen_event(event: RefCounted) -> void:
	_chat.set_hydrogen_event(event)


# ==== 导师立绘卡（数据驱动：顺序与文案全来自 mentors.json）====

func _build_mentor_cards() -> void:
	var registry: RefCounted = RegistryScript.new()
	for id_value: Variant in registry.mentor_ids():
		var mentor_id: String = str(id_value)
		var row: Dictionary = registry.record(mentor_id)
		_mentor_row.add_child(_make_card(mentor_id, row))


func _make_card(mentor_id: String, row: Dictionary) -> Button:
	var card := Button.new()
	card.name = "Mentor_%s" % mentor_id
	card.custom_minimum_size = Vector2(124, 190)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(116, 148)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = str(PORTRAITS.get(mentor_id, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		portrait.texture = load(path) as Texture2D
	box.add_child(portrait)
	var label := Label.new()
	label.name = "NameLabel"
	label.text = "%s·%s" % [str(row.get("name", "")), str(row.get("title", ""))]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	card.add_child(box)
	card.pressed.connect(_on_mentor_pressed.bind(mentor_id))
	return card


func mentor_card(mentor_id: String) -> Button:
	return _mentor_row.get_node_or_null("Mentor_%s" % mentor_id) as Button


func _on_mentor_pressed(mentor_id: String) -> void:
	_chat.open_chat(mentor_id)


# ==== 返回与热键 ====

func _on_back_pressed() -> void:
	if _standalone:
		if ResourceLoader.exists(MAIN_MENU_SCENE):
			get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return
	close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _standalone:
		if event.is_action_pressed(ACTION_PAUSE):
			_on_back_pressed()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_MENTOR_ROOM):
		var manager: Node = _find_ui_manager()
		if manager != null:
			manager.toggle(PANEL_NAME)
			get_viewport().set_input_as_handled()


func _find_ui_manager() -> Node:
	var node: Node = self
	while node != null:
		var candidate: Node = node.get_node_or_null(UI_MANAGER_REL)
		if candidate != null and candidate.has_method("toggle"):
			return candidate
		node = node.get_parent()
	return null


func _apply_texts() -> void:
	_title.text = _ui(UI_TITLE)
	_hint.text = _ui(UI_HINT)
	_back.text = _ui(UI_BACK)


func _ui(key: String) -> String:
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm == null:
		return key
	return gm.get_ui_string(key)
