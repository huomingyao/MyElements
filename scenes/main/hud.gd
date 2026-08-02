# HUD（FR-C-07，SPEC-03 §8）：左上三条数值条 + 已收集计数 + 时间/天数指示。
# AC1：数值条只由 GameManager 信号驱动，本脚本没有 _process 轮询（IT-C07 grep 断言）。
# 文案走 get_ui_string（NFR-04）；低氧阈值走 balance.json（铁律 4）。
extends Control

# ==== 常量区 ====

const BAL_LOW_OXYGEN: String = "stats.hud_low_oxygen_threshold"
const FALLBACK_LOW_OXYGEN: float = 30.0
const TIP_OXYGEN_LOW: String = "sys_oxygen_low"
# 氧气首次跌破教程阈值（70）时的一次性引导横幅（FR-U-02 AC2，SPEC-05 §3.2）。
const BAL_TUTORIAL_OXYGEN: String = "stats.tutorial_oxygen_hint_at"
const FALLBACK_TUTORIAL_OXYGEN: float = 70.0
const TIP_OXYGEN_TUTORIAL: String = "sys_oxygen_tutorial"
const UI_COLLECTED_COUNTER: String = "collected_counter"
const UI_TIME_DAY: String = "hud_day"
const UI_TIME_NIGHT: String = "hud_night"

# 低氧闪烁（Tween 驱动，不占 _process）。
const FLASH_ALPHA_LOW: float = 0.35
const FLASH_HALF_PERIOD: float = 0.4

# ==== 逻辑区 ====

var _gm: Node = null
var _oxygen_warning: bool = false
var _flash_tween: Tween = null
# 一次性标记（FR-U-02 AC2）：跌破后回升再跌破不重复，不依赖字幕引擎的 once。
var _tutorial_hint_shown: bool = false

@onready var _oxygen_bar: ProgressBar = %OxygenBar
@onready var _energy_bar: ProgressBar = %EnergyBar
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _collected_label: Label = %CollectedLabel
@onready var _time_label: Label = %TimeLabel


func _ready() -> void:
	set_collected(0)
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm != null:
		set_game_manager(gm)


func _exit_tree() -> void:
	_stop_flash()


# 可注入的 GameManager 引用（SPEC-06 §3 可测性）：重连信号并同步一次当前值。
func set_game_manager(gm: Node) -> void:
	if _gm != null:
		_disconnect_gm()
	_gm = gm
	_gm.oxygen_changed.connect(_on_oxygen_changed)
	_gm.energy_changed.connect(_on_energy_changed)
	_gm.health_changed.connect(_on_health_changed)
	_gm.day_started.connect(_on_day_started)
	_gm.night_started.connect(_on_night_started)
	_sync_from_gm()


func _disconnect_gm() -> void:
	var pairs: Array = [
		["oxygen_changed", _on_oxygen_changed],
		["energy_changed", _on_energy_changed],
		["health_changed", _on_health_changed],
		["day_started", _on_day_started],
		["night_started", _on_night_started],
	]
	for pair in pairs:
		var signal_name: String = str(pair[0])
		var handler: Callable = pair[1]
		if _gm.is_connected(signal_name, handler):
			_gm.disconnect(signal_name, handler)


# 进场时同步一次当前值（此后全靠信号，不轮询）。
func _sync_from_gm() -> void:
	_on_oxygen_changed(_gm.oxygen, _gm.oxygen_max)
	_on_energy_changed(_gm.energy, _gm.energy_max)
	_on_health_changed(_gm.health, _gm.health_max)
	_update_time(_gm.day_count, _gm.is_night())


func _on_oxygen_changed(current: float, max_value: float) -> void:
	_oxygen_bar.max_value = max_value
	_oxygen_bar.value = current
	_show_tutorial_hint_once(current)
	_set_oxygen_warning(current < _low_oxygen_threshold())


# FR-U-02 AC2：氧气首次跌破教程阈值时引导一次（横幅走数据表，HUD 内一次性标记）。
func _show_tutorial_hint_once(current: float) -> void:
	if _tutorial_hint_shown:
		return
	if current >= _tutorial_oxygen_threshold():
		return
	_tutorial_hint_shown = true
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip != null:
		tip.show(TIP_OXYGEN_TUTORIAL)


func _tutorial_oxygen_threshold() -> float:
	if _gm == null:
		return FALLBACK_TUTORIAL_OXYGEN
	return float(_gm.get_balance(BAL_TUTORIAL_OXYGEN, FALLBACK_TUTORIAL_OXYGEN))


func _on_energy_changed(current: float, max_value: float) -> void:
	_energy_bar.max_value = max_value
	_energy_bar.value = current


func _on_health_changed(current: float, max_value: float) -> void:
	_health_bar.max_value = max_value
	_health_bar.value = current


# AC3：低于阈值进入闪烁并提醒一次；同一低氧时段不重复，回升后再低重新提醒。
func _set_oxygen_warning(active: bool) -> void:
	if active == _oxygen_warning:
		return
	_oxygen_warning = active
	if active:
		_show_low_oxygen_tip()
		_start_flash()
	else:
		_stop_flash()


func is_oxygen_warning() -> bool:
	return _oxygen_warning


func _low_oxygen_threshold() -> float:
	if _gm == null:
		return FALLBACK_LOW_OXYGEN
	return float(_gm.get_balance(BAL_LOW_OXYGEN, FALLBACK_LOW_OXYGEN))


func _show_low_oxygen_tip() -> void:
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip != null:
		tip.show(TIP_OXYGEN_LOW)


func _start_flash() -> void:
	_stop_flash()
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_property(_oxygen_bar, "modulate:a", FLASH_ALPHA_LOW, FLASH_HALF_PERIOD)
	_flash_tween.tween_property(_oxygen_bar, "modulate:a", 1.0, FLASH_HALF_PERIOD)


func _stop_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	if is_instance_valid(_oxygen_bar):
		_oxygen_bar.modulate.a = 1.0


# AC2：已收集计数，格式串来自 ui_strings.json（「已收集 {n}/16」）。
func set_collected(count: int) -> void:
	_collected_label.text = _ui(UI_COLLECTED_COUNTER).format({"n": count})


func collected_text() -> String:
	return _collected_label.text


func _on_day_started(day_count: int) -> void:
	_update_time(day_count, false)


func _on_night_started(day_count: int) -> void:
	_update_time(day_count, true)


func _update_time(day_count: int, night: bool) -> void:
	var key: String = UI_TIME_NIGHT if night else UI_TIME_DAY
	_time_label.text = _ui(key).format({"n": day_count})


func time_text() -> String:
	return _time_label.text


func _ui(key: String) -> String:
	var gm: Node = _gm if _gm != null else get_node_or_null(^"/root/GameManager")
	if gm == null:
		return key
	return gm.get_ui_string(key)
