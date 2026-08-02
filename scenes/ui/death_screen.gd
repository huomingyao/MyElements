# DeathScreen（FR-C-06 AC1/AC2，IT-C06，TP-11）：死亡画面。
# 监听 GameManager.player_died 弹出，并触发 sys_death 字幕（警示文案含复活指引，
# 故画面本身不再新增 ui_strings 键）；任意键/点击确认 → respawn_player() 复活。
# 文案全部走 ui_strings/tips 数据表（NFR-04），逻辑代码零中文。
extends CanvasLayer

# ==== 常量区 ====

const TIP_DEATH: String = "sys_death"
const UI_TITLE_KEY: String = "death_title"

# ==== 逻辑区 ====

var _open: bool = false

@onready var _title: Label = %TitleLabel


func _ready() -> void:
	visible = false
	_title.text = _ui_string(UI_TITLE_KEY)
	var gm: Node = _game_manager()
	if gm != null and not gm.player_died.is_connected(_on_player_died):
		gm.player_died.connect(_on_player_died)


# 任意键或点击确认复活；Dim 的 mouse_filter 为 IGNORE，点击能落到这里。
func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		confirm()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		confirm()
		get_viewport().set_input_as_handled()


func open() -> void:
	_open = true
	visible = true
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip != null:
		tip.show(TIP_DEATH)


func close() -> void:
	_open = false
	visible = false


func is_open() -> bool:
	return _open


# 确认复活：三值回满 + 发 player_respawned（落点由场景监听处理）；未死亡时调用无效。
func confirm() -> void:
	if not _open:
		return
	close()
	var gm: Node = _game_manager()
	if gm != null:
		gm.respawn_player()


func _on_player_died(_death_position: Vector2) -> void:
	open()


func _game_manager() -> Node:
	return get_node_or_null(^"/root/GameManager")


func _ui_string(key: String) -> String:
	var gm: Node = _game_manager()
	if gm == null:
		return key
	return str(gm.get_ui_string(key))
