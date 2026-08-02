# GameManager（SPEC-03 §2，FR-C-02/C-03/C-04/C-09）：三值、昼夜时钟、区域判定、死亡复活、全局标记。
# 时间只从 tick(delta) 进（SPEC-03 §2.2）：autoload 自己不跑 _process，测试可一次注入 600 秒。
extends Node

signal oxygen_changed(current: float, max_value: float)
signal energy_changed(current: float, max_value: float)
signal health_changed(current: float, max_value: float)
signal zone_changed(zone_id: String)
signal day_started(day_count: int)
signal night_started(day_count: int)
signal resources_respawned()
signal player_died(death_position: Vector2)
signal player_respawned()
signal flag_changed(key: String, value: bool)

# ==== 常量区 ====
# 可调数值一律进 balance.json（铁律 4）；这里只放键名、区域枚举与「数据表缺失」时的兜底默认值。

const ZONE_IDS: Array[String] = ["grassland", "camp", "saltlake", "mine", "academy"]
const ALLOWED_FLAGS: Array[String] = ["explosion_happened", "purity_check_unlocked"]
const DEFAULT_ZONE: String = "grassland"

# 有氧气回复的区域（SPEC-02 §4.1：回草原/营地缓慢回满）。
const SAFE_ZONES: Array[String] = ["grassland", "camp"]

# 首次进入区域的横幅字幕 id（SPEC-05 §3.1）；逻辑代码里不出现中文字面量（NFR-04）。
const ZONE_TIP_IDS: Dictionary = {
	"grassland": "zone_grass",
	"camp": "zone_camp",
	"saltlake": "zone_salt",
	"mine": "zone_mine",
	"academy": "zone_academy",
}

const BAL_OXYGEN_MAX: String = "stats.oxygen_max"
const BAL_ENERGY_MAX: String = "stats.energy_max"
const BAL_HEALTH_MAX: String = "stats.health_max"
const BAL_OXYGEN_DRAIN: String = "stats.oxygen_drain"
const BAL_OXYGEN_REGEN: String = "stats.oxygen_regen_safe"
const BAL_ENERGY_DRAIN: String = "stats.energy_drain"
const BAL_OXYGEN_ZERO_DAMAGE: String = "stats.oxygen_zero_health_drain"
const BAL_LOW_ENERGY_MULTIPLIER: String = "stats.low_energy_speed_multiplier"
const BAL_DAY_DURATION: String = "daynight.day_duration"
const BAL_NIGHT_DURATION: String = "daynight.night_duration"

const FALLBACK_STAT_MAX: float = 100.0
const FALLBACK_OXYGEN_DRAIN: float = 0.5
const FALLBACK_OXYGEN_REGEN: float = 1.0
const FALLBACK_ENERGY_DRAIN: float = 0.3
const FALLBACK_OXYGEN_ZERO_DAMAGE: float = 5.0
const FALLBACK_LOW_ENERGY_MULTIPLIER: float = 0.5
const FALLBACK_DAY_DURATION: float = 360.0
const FALLBACK_NIGHT_DURATION: float = 180.0

# 单次 tick 允许跨越的昼夜边界次数上限，防止极端 delta 或坏配置造成死循环。
const MAX_CLOCK_STEPS: int = 64

# 三值（0..max）——上限与初值读自 balance.json。
var oxygen: float = FALLBACK_STAT_MAX
var energy: float = FALLBACK_STAT_MAX
var health: float = FALLBACK_STAT_MAX
var oxygen_max: float = FALLBACK_STAT_MAX
var energy_max: float = FALLBACK_STAT_MAX
var health_max: float = FALLBACK_STAT_MAX

# 时间
var day_count: int = 1
var time_of_day: float = 0.0

# 全局标记（只允许通过 set_flag 写）
var explosion_happened: bool = false
var purity_check_unlocked: bool = false

var _balance: Dictionary = {}
var _ui_strings: Dictionary = {}
# 初值为空串而非 DEFAULT_ZONE（A4 / FR-C-03 AC3）：首次定位必须走「区域变化」路径发 zone_changed
# 并播出生区横幅；若初值即 grassland，world._reset_run 的首次 set_zone 会被同区去重吞掉。
# 空串期间氧气净速率按 DEFAULT_ZONE 结算（见 oxygen_net_rate），行为与旧初值一致。
var _zone: String = ""
var _night: bool = false
var _death_emitted: bool = false
var _respawn_position: Vector2 = Vector2.ZERO

# ==== 逻辑区 ====
# 本区不得出现裸速率数值，一律走 _balance_float() 或常量区（FR-C-02 AC4，UT-C02 grep 断言）。

func _ready() -> void:
	reload_config()
	reset_clock()
	reset_stats()


# 重新读取 balance.json / ui_strings.json（调参与测试用）。
func reload_config() -> void:
	_balance = DataLoader.load_table("balance.json", TYPE_DICTIONARY, {})
	_ui_strings = DataLoader.load_table("ui_strings.json", TYPE_DICTIONARY, {})
	oxygen_max = _balance_float(BAL_OXYGEN_MAX, FALLBACK_STAT_MAX)
	energy_max = _balance_float(BAL_ENERGY_MAX, FALLBACK_STAT_MAX)
	health_max = _balance_float(BAL_HEALTH_MAX, FALLBACK_STAT_MAX)


# 三值回满 + 复位死亡去重标记。
func reset_stats() -> void:
	oxygen = oxygen_max
	energy = energy_max
	health = health_max
	_death_emitted = false
	oxygen_changed.emit(oxygen, oxygen_max)
	energy_changed.emit(energy, energy_max)
	health_changed.emit(health, health_max)


# 时钟回到第一天清晨（测试与新开局用）。
func reset_clock() -> void:
	time_of_day = 0.0
	day_count = 1
	_night = false


# 唯一时间推进入口（SPEC-03 §2.2）：先推时钟，再结算三值。
# 由 scenes/main/world.gd 在 _process(delta) 里调用；autoload 自身不跑时钟。
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_advance_clock(delta)
	_settle_stats(delta)


# 昼夜推进：支持一次注入超过一个周期的大 delta，逐段跨越边界不丢信号。
func _advance_clock(delta: float) -> void:
	var remaining: float = delta
	var steps: int = 0
	while remaining > 0.0 and steps < MAX_CLOCK_STEPS:
		steps += 1
		var phase_length: float = _current_phase_length()
		if phase_length <= 0.0:
			# 坏配置（时长 <= 0）：只累加时间，不做相位翻转，避免死循环。
			push_warning("[game] 昼夜时长配置非法（%s）" % phase_length)
			time_of_day += remaining
			return
		var to_boundary: float = phase_length - time_of_day
		if remaining < to_boundary:
			time_of_day += remaining
			return
		remaining -= to_boundary
		time_of_day = 0.0
		_flip_phase()


func _current_phase_length() -> float:
	if _night:
		return _balance_float(BAL_NIGHT_DURATION, FALLBACK_NIGHT_DURATION)
	return _balance_float(BAL_DAY_DURATION, FALLBACK_DAY_DURATION)


# 相位翻转：入夜发 night_started；清晨天数 +1、发 day_started + resources_respawned（AC4）。
func _flip_phase() -> void:
	_night = not _night
	if _night:
		night_started.emit(day_count)
		return
	day_count += 1
	day_started.emit(day_count)
	resources_respawned.emit()

# 三值结算：氧气净速率（SPEC-02 §4.1）、能量全区一致消耗、缺氧持续掉血。
func _settle_stats(delta: float) -> void:
	var net_oxygen: float = oxygen_net_rate() * delta
	if not is_zero_approx(net_oxygen):
		modify_oxygen(net_oxygen)
	modify_energy(-_balance_float(BAL_ENERGY_DRAIN, FALLBACK_ENERGY_DRAIN) * delta)
	# 氧气归零后生命持续下降（FR-C-02 AC3）。
	if oxygen <= 0.0:
		modify_health(-_balance_float(BAL_OXYGEN_ZERO_DAMAGE, FALLBACK_OXYGEN_ZERO_DAMAGE) * delta)


# 当前区域的氧气净速率（正 = 回复，负 = 消耗）；供 HUD 与测试查询。
# _zone 尚未首次定位（空串）时按 DEFAULT_ZONE 结算，避免读不存在的点分键。
func oxygen_net_rate() -> float:
	var rate_zone: String = _zone if not _zone.is_empty() else DEFAULT_ZONE
	var drain: float = _balance_float(
		"%s.%s" % [BAL_OXYGEN_DRAIN, rate_zone], FALLBACK_OXYGEN_DRAIN)
	var regen: float = 0.0
	if SAFE_ZONES.has(rate_zone):
		regen = _balance_float(BAL_OXYGEN_REGEN, FALLBACK_OXYGEN_REGEN)
	return regen - drain


func is_night() -> bool:
	return _night


func current_zone() -> String:
	return _zone


# 区域触发器调用；同一区域重复调用不发信号（SPEC-03 §2.4）。
# 首次进入触发一次该区域横幅字幕（FR-C-03 AC3），走 KnowledgeTip.show_once 去重。
func set_zone(zone_id: String) -> void:
	if not ZONE_IDS.has(zone_id):
		push_warning("[game] 未知区域 id：%s（忽略）" % zone_id)
		return
	if zone_id == _zone:
		return
	_zone = zone_id
	zone_changed.emit(_zone)
	_show_zone_tip(_zone)


func _show_zone_tip(zone_id: String) -> void:
	var tip_id: String = str(ZONE_TIP_IDS.get(zone_id, ""))
	if tip_id.is_empty():
		return
	# 依赖方向铁律：autoload 之间可互相调用，但不摸具体场景节点。
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip == null:
		return
	tip.show_once(tip_id)


func modify_oxygen(delta: float) -> void:
	var next: float = clampf(oxygen + delta, 0.0, oxygen_max)
	if is_equal_approx(next, oxygen):
		return
	oxygen = next
	oxygen_changed.emit(oxygen, oxygen_max)


func modify_energy(delta: float) -> void:
	var next: float = clampf(energy + delta, 0.0, energy_max)
	if is_equal_approx(next, energy):
		return
	energy = next
	energy_changed.emit(energy, energy_max)


# 归零触发死亡流程；同帧多次伤害只发一次 player_died（SPEC-03 §2.4）。
func modify_health(delta: float) -> void:
	var next: float = clampf(health + delta, 0.0, health_max)
	if is_equal_approx(next, health):
		return
	health = next
	health_changed.emit(health, health_max)
	if health <= 0.0 and not _death_emitted:
		_death_emitted = true
		player_died.emit(_respawn_position)


func move_speed_multiplier() -> float:
	if energy <= 0.0:
		return _balance_float(BAL_LOW_ENERGY_MULTIPLIER, FALLBACK_LOW_ENERGY_MULTIPLIER)
	return 1.0

# 床调用：跳夜、生命回满、天数 +1、发 resources_respawned（FR-C-05）。
func sleep_until_morning() -> void:
	_night = false
	time_of_day = 0.0
	day_count += 1
	health = health_max
	health_changed.emit(health, health_max)
	day_started.emit(day_count)
	resources_respawned.emit()


# 复活：三值回满、位置回床（由场景监听 player_respawned 处理落点）。
func respawn_player() -> void:
	reset_stats()
	player_respawned.emit()


# 供死亡掉落使用：场景把玩家当前位置同步进来。
func set_respawn_reference_position(position: Vector2) -> void:
	_respawn_position = position


func set_flag(key: String, value: bool) -> void:
	if not ALLOWED_FLAGS.has(key):
		push_warning("[game] 不允许的标记 key：%s（忽略）" % key)
		return
	match key:
		"explosion_happened":
			if explosion_happened == value:
				return
			explosion_happened = value
		"purity_check_unlocked":
			if purity_check_unlocked == value:
				return
			purity_check_unlocked = value
	flag_changed.emit(key, value)


func get_flag(key: String) -> bool:
	match key:
		"explosion_happened":
			return explosion_happened
		"purity_check_unlocked":
			return purity_check_unlocked
	push_warning("[game] 未知标记 key：%s（返回 false）" % key)
	return false


# 读 balance.json 的点分键；缺键返回默认值 + 警告（FR-D-08 AC2）。
func get_balance(key: String, default_value: Variant) -> Variant:
	return DataLoader.dig(_balance, key, default_value)


# get_balance 的取浮点版本，省掉各处重复的 float() 转换。
func _balance_float(key: String, default_value: float) -> float:
	return float(get_balance(key, default_value))


# 读 ui_strings.json；缺 key 返回 key 本身 + 警告，界面上能看出漏了哪个 key。
func get_ui_string(key: String) -> String:
	if _ui_strings.has(key):
		var value: Variant = _ui_strings[key]
		if typeof(value) == TYPE_STRING and not (value as String).is_empty():
			return value
	push_warning("[ui] 缺少 ui_strings key：%s" % key)
	return key
