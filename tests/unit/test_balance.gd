# UT-D08 / FR-D-08：balance.json 覆盖 SPEC-02 §4 全部参数键；缺键走默认值不崩溃；debug.* 默认 false。
extends GutTest

const BALANCE_PATH: String = "res://data/balance.json"

# SPEC-02 §4 参数表 + SPEC-04 §9 骨架的点分键 -> 期望基线值。
const REQUIRED_KEYS: Dictionary = {
	"stats.oxygen_max": 100.0,
	"stats.energy_max": 100.0,
	"stats.health_max": 100.0,
	"stats.oxygen_drain.grassland": 0.5,
	"stats.oxygen_drain.camp": 0.5,
	"stats.oxygen_drain.saltlake": 0.0,
	"stats.oxygen_drain.mine": 2.0,
	"stats.oxygen_drain.academy": 0.0,
	"stats.oxygen_regen_safe": 1.0,
	"stats.energy_drain": 0.3,
	"stats.health_regen_campfire": 1.0,
	"stats.oxygen_zero_health_drain": 5.0,
	"stats.low_energy_speed_multiplier": 0.5,
	"stats.hud_low_oxygen_threshold": 30.0,
	"stats.tutorial_oxygen_hint_at": 70.0,
	"daynight.day_duration": 360.0,
	"daynight.night_duration": 180.0,
	"daynight.night_brightness": 0.35,
	"daynight.dark_view_radius": 80.0,
	"daynight.torch_view_radius": 220.0,
	"damage.co_ghost_per_second": 8.0,
	"damage.acid_mist_per_hit": 10.0,
	"damage.hydrogen_explosion": 50.0,
	"damage.cuso4_pool_per_second": 5.0,
	"player.move_speed": 110.0,
	"player.jump_velocity": -300.0,
	"player.gravity": 900.0,
	"player.interact_radius": 28.0,
	"monsters.co_ghost_speed": 28.0,
	"monsters.acid_mist_speed": 90.0,
	"monsters.acid_mist_night_count_min": 2,
	"monsters.acid_mist_night_count_max": 3,
	"items.oxygen_tank_restore": 50.0,
	"items.trade_energy_restore": 20.0,
	"items.campfire_meal_restore": 40.0,
	"inventory.hotbar_slots": 8,
	"inventory.stack_limit": 99,
	"llm.timeout_seconds": 8.0,
	"llm.retry_count": 1,
	"llm.history_rounds": 4,
	"llm.max_tokens": 300,
	"llm.temperature": 0.7,
	"llm.input_max_chars": 200,
	"debug.force_purity_unlock": false,
	"debug.fast_daynight": false,
}


func _load_balance() -> Dictionary:
	var file: FileAccess = FileAccess.open(BALANCE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _dig(data: Dictionary, dotted_key: String) -> Variant:
	var node: Variant = data
	for part in dotted_key.split("."):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(part):
			return null
		node = (node as Dictionary)[part]
	return node


func test_balance_json_exists_and_parses() -> void:
	assert_true(FileAccess.file_exists(BALANCE_PATH), "缺少 %s" % BALANCE_PATH)
	assert_false(_load_balance().is_empty(), "balance.json 无法解析为非空对象")


# AC1：SPEC-02 §4 参数表中的每个值都在此文件中有对应键。
func test_every_spec02_parameter_key_exists() -> void:
	var data: Dictionary = _load_balance()
	if data.is_empty():
		fail_test("balance.json 不可用，无法校验键覆盖")
		return
	for key in REQUIRED_KEYS.keys():
		assert_not_null(_dig(data, key), "balance.json 缺键：%s" % key)


func test_baseline_values_match_spec() -> void:
	var data: Dictionary = _load_balance()
	if data.is_empty():
		fail_test("balance.json 不可用，无法校验基线值")
		return
	for key in REQUIRED_KEYS.keys():
		var actual: Variant = _dig(data, key)
		if actual == null:
			continue
		assert_eq(actual, REQUIRED_KEYS[key], "balance.json 基线值不符：%s" % key)


# SPEC-04 §9 + SPEC-09 §2：debug.* 默认必须全为 false。
func test_all_debug_flags_default_to_false() -> void:
	var data: Dictionary = _load_balance()
	var debug: Variant = data.get("debug", null)
	assert_typeof(debug, TYPE_DICTIONARY, "balance.json 缺少 debug 段")
	if typeof(debug) != TYPE_DICTIONARY:
		return
	assert_false((debug as Dictionary).is_empty(), "debug 段不许为空")
	for key in (debug as Dictionary).keys():
		assert_eq((debug as Dictionary)[key], false, "debug.%s 必须默认 false" % key)


# AC1 通过 GameManager.get_balance 的点分键读取路径也必须可用。
func test_game_manager_reads_every_key_through_get_balance() -> void:
	var gm: Node = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	if gm == null:
		fail_test("GameManager autoload 缺失")
		return
	for key in REQUIRED_KEYS.keys():
		var sentinel: String = "__MISSING__"
		assert_eq(gm.get_balance(key, sentinel), REQUIRED_KEYS[key],
			"GameManager.get_balance 读不到 %s" % key)


# AC2：缺键时使用代码内默认值并输出警告，不崩溃。
func test_missing_key_returns_default_without_crashing() -> void:
	var gm: Node = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	if gm == null:
		fail_test("GameManager autoload 缺失")
		return
	assert_eq(gm.get_balance("stats.no_such_key", 7.5), 7.5)
	assert_eq(gm.get_balance("no_such_section.no_such_key", -1), -1)
	assert_eq(gm.get_balance("", "fallback"), "fallback")
	# 中途踩到非字典节点时也必须返回默认值，而不是报错。
	assert_eq(gm.get_balance("stats.oxygen_max.deeper", "fallback"), "fallback")
