# 暂停菜单（FR-C-08 AC2）：Esc 打开/关闭；可继续或返回主菜单。
# 只负责面板显隐与导航；游戏树暂停（get_tree().paused）由 world/ui_manager 统一裁决（SPEC-03 §8）。
extends Control

# ==== 常量区 ====

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main/main_menu.tscn"
const UI_CONTINUE: String = "pause_continue"
const UI_TO_MENU: String = "pause_to_menu"

# ==== 逻辑区 ====

signal pause_toggled(open: bool)

var _navigator: Callable = Callable()

@onready var _continue_button: Button = %ContinueButton
@onready var _menu_button: Button = %MenuButton


func _ready() -> void:
	visible = false
	_continue_button.text = _ui(UI_CONTINUE)
	_menu_button.text = _ui(UI_TO_MENU)
	_continue_button.pressed.connect(close)
	_menu_button.pressed.connect(return_to_main_menu)


func _ui(key: String) -> String:
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm == null:
		return key
	return gm.get_ui_string(key)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


# 注入场景切换出口（测试用）；签名 func(path: String) -> void。
func set_navigator(navigator: Callable) -> void:
	_navigator = navigator


func open() -> void:
	if visible:
		return
	visible = true
	pause_toggled.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	pause_toggled.emit(false)


func return_to_main_menu() -> void:
	close()
	if _navigator.is_valid():
		_navigator.call(MAIN_MENU_SCENE_PATH)
		return
	if ResourceLoader.exists(MAIN_MENU_SCENE_PATH):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	else:
		push_warning("[pause] 主菜单场景缺失：%s（忽略）" % MAIN_MENU_SCENE_PATH)
