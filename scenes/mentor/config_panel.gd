# ConfigPanel（FR-M-10 / SPEC-03 §6.4）：配置面板占位。
# 只做三件事：把输入框里的 key 转交给 LLMClient、转发手动离线开关、显示一个不生效的性格滑块。
# 安全（NFR-05）：本文件不落盘、不回显、不记录 key——写入只归 LLMClient.set_api_key()。
# 文案（NFR-04）：界面短语一律走 GameManager.get_ui_string()，本文件零中文字面量。
extends Control

# ==== 常量区 ====
const UI_CONFIG_NOTE: String = "config_note"
const GAME_MANAGER_PATH: NodePath = ^"/root/GameManager"
const LLM_CLIENT_PATH: NodePath = ^"/root/LLMClient"

# ==== 状态区 ====
# 测试注入的假客户端（SPEC-03 §6.4 非契约辅助）；未注入时 _ready() 取 autoload。
var _client: Node = null

@onready var _key_input: LineEdit = %KeyInput
@onready var _apply_button: Button = %ApplyButton
@onready var _offline_toggle: CheckButton = %OfflineToggle
@onready var _slider: HSlider = %PersonalitySlider
@onready var _note: Label = %NoteLabel


# ==== 逻辑区 ====
func _ready() -> void:
	if _client == null:
		_client = get_node_or_null(LLM_CLIENT_PATH)
	# key 绝不明文显示（NFR-05）。
	_key_input.secret = true
	_note.text = note_text()
	_apply_button.pressed.connect(_on_apply_pressed)
	_offline_toggle.toggled.connect(set_offline_toggle)
	_sync_offline_toggle()


# 测试注入口（SPEC-03 §6.4 非契约辅助）：注入后不碰真实 autoload，也就不碰真实 config.cfg。
func set_client(client: Node) -> void:
	_client = client
	if is_node_ready():
		_sync_offline_toggle()


# 把输入框里的 key 交给 LLMClient（只写 user://config.cfg）。
# 空串视为「不改动」——避免误清掉玩家已配好的 key。返回是否真的转发了。
func apply_api_key() -> bool:
	if _client == null or not _client.has_method("set_api_key"):
		return false
	var typed: String = _key_input.text.strip_edges()
	if typed.is_empty():
		return false
	_client.set_api_key(typed)
	# 用完立刻清空输入框，屏幕上不留 key（NFR-05）。
	_key_input.text = ""
	return true


# 手动离线开关（FR-M-08 AC4）：切换立即生效。
func set_offline_toggle(value: bool) -> void:
	if _client == null or not _client.has_method("set_offline"):
		return
	_client.set_offline(value)


# 性格滑块当前值。**只读展示，任何模块都不许消费它**（FR-M-10 AC2）。
func personality() -> float:
	return _slider.value


func note_text() -> String:
	var gm: Node = get_node_or_null(GAME_MANAGER_PATH)
	if gm == null:
		return UI_CONFIG_NOTE
	return gm.get_ui_string(UI_CONFIG_NOTE)


func _on_apply_pressed() -> void:
	apply_api_key()


# 打开面板时显示状态跟随客户端真实状态，且不反向写回。
func _sync_offline_toggle() -> void:
	if _client == null or not _client.has_method("is_offline"):
		return
	_offline_toggle.set_pressed_no_signal(_client.is_offline())
