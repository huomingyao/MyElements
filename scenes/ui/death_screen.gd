# DeathScreen（FR-C-06 AC1/AC2，IT-C06，TP-11）：死亡画面。
# 监听 GameManager.player_died 弹出，并触发 sys_death 字幕；任意键/点击确认 → respawn_player() 复活。
# 信息区（优化包C-5）：标题 + 坚持天数统计（GameManager.day_count）+ 死亡后果说明
# （掉落可捡回）+ 复活操作提示。player_died 只带死亡点坐标、无死因参数（SPEC-03 冻结），
# 故不展示死因；掉落包生成在死亡点，后果说明按「回倒下的地方捡回」表述。
# 文案全部走 ui_strings/tips 数据表（NFR-04），逻辑代码零中文。
extends CanvasLayer

# ==== 常量区 ====

const TIP_DEATH: String = "sys_death"
const UI_TITLE_KEY: String = "death_title"
const UI_INFO_KEY: String = "death_info"
const UI_DAY_KEY: String = "death_day"
const UI_HINT_KEY: String = "death_hint"
# Esc 对应的输入动作（FR-C-01 输入映射）：暂停语义键不算「任意键确认」。
const ACTION_PAUSE: String = "pause"

# ==== 逻辑区 ====

var _open: bool = false

@onready var _title: Label = %TitleLabel
@onready var _info: Label = %InfoLabel
@onready var _day: Label = %DayLabel
@onready var _hint: Label = %HintLabel


func _ready() -> void:
	visible = false
	_title.text = _ui_string(UI_TITLE_KEY)
	_info.text = _ui_string(UI_INFO_KEY)
	_hint.text = _ui_string(UI_HINT_KEY)
	var gm: Node = _game_manager()
	if gm != null and not gm.player_died.is_connected(_on_player_died):
		gm.player_died.connect(_on_player_died)


# 任意键或点击确认复活；Dim 的 mouse_filter 为 IGNORE，点击能落到这里。
func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	# Esc 不确认复活（收口 W1）：暂停语义键交给 ui_manager 裁决，这里吞掉防误触。
	if event.is_action_pressed(ACTION_PAUSE):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		confirm()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		confirm()
		get_viewport().set_input_as_handled()


func open() -> void:
	_open = true
	_refresh_day_label()
	visible = true
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip != null:
		tip.show(TIP_DEATH)


# 天数统计在弹出时刷新（同一局可能多次死亡，天数会推进）。
func _refresh_day_label() -> void:
	var gm: Node = _game_manager()
	var day: int = int(gm.get("day_count")) if gm != null else 1
	_day.text = _ui_string(UI_DAY_KEY).format({"n": day})


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
