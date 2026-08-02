# UT-C09 / FR-C-09：五个 autoload 存在，且 SPEC-03 列出的方法名与参数数量一致（反射断言）。
extends GutTest

# 名称 -> { "methods": {方法名: 参数个数}, "signals": [...], "props": [...] }
const CONTRACT: Dictionary = {
	"GameManager": {
		"methods": {
			"tick": 1,
			"is_night": 0, "current_zone": 0, "set_zone": 1,
			"modify_oxygen": 1, "modify_energy": 1, "modify_health": 1,
			"move_speed_multiplier": 0, "sleep_until_morning": 0, "respawn_player": 0,
			"set_flag": 2, "get_flag": 1, "get_balance": 2, "get_ui_string": 1,
		},
		"signals": [
			"oxygen_changed", "energy_changed", "health_changed", "zone_changed",
			"day_started", "night_started", "resources_respawned",
			"player_died", "player_respawned", "flag_changed",
		],
		"props": [
			"oxygen", "energy", "health", "oxygen_max", "energy_max", "health_max",
			"day_count", "time_of_day", "explosion_happened", "purity_check_unlocked",
		],
	},
	"KnowledgeTip": {
		"methods": {"show": 1, "show_once": 1, "show_custom": 3, "is_shown": 1, "clear_queue": 0},
		"signals": ["tip_shown", "tip_finished"],
		"props": [],
	},
	"RecipeDB": {
		"methods": {
			"get_substance": 1, "all_substances": 0, "try_craft": 3,
			"get_recipe": 1, "unlocked_recipes": 0, "get_fail_message": 1, "reload": 0,
		},
		"signals": [],
		"props": [],
	},
	"LLMClient": {
		"methods": {"ask": 3, "is_offline": 0, "set_offline": 1, "has_api_key": 0, "set_api_key": 1},
		"signals": ["reply_started", "reply_chunk", "reply_finished", "mode_changed"],
		"props": [],
	},
	"WorldMap": {
		"methods": {"open": 0, "close": 0, "is_unlocked": 1, "all_zones": 0, "get_zone": 1},
		"signals": [],
		"props": [],
	},
}


func _get_autoload(name: String) -> Node:
	var root: Node = Engine.get_main_loop().root
	return root.get_node_or_null(NodePath(name))


func _method_arg_count(node: Node, method_name: String) -> int:
	for entry in node.get_method_list():
		if entry["name"] == method_name:
			return entry["args"].size()
	return -1


# AC1：五个 autoload 均已注册且可在任意场景访问。
func test_all_five_autoloads_are_registered() -> void:
	for name in CONTRACT.keys():
		assert_not_null(_get_autoload(name), "autoload 缺失：%s" % name)


# AC2：SPEC-03 中列出的每个公开方法都存在，签名一致（方法名 + 参数数量）。
func test_every_contract_method_exists_with_matching_arity() -> void:
	for name in CONTRACT.keys():
		var node: Node = _get_autoload(name)
		if node == null:
			fail_test("autoload 缺失，无法校验方法：%s" % name)
			continue
		var methods: Dictionary = CONTRACT[name]["methods"]
		for method_name in methods.keys():
			var expected: int = methods[method_name]
			var actual: int = _method_arg_count(node, method_name)
			assert_eq(actual, expected,
				"%s.%s() 参数数量不符（-1 表示方法不存在）" % [name, method_name])


func test_every_contract_signal_exists() -> void:
	for name in CONTRACT.keys():
		var node: Node = _get_autoload(name)
		if node == null:
			fail_test("autoload 缺失，无法校验信号：%s" % name)
			continue
		for signal_name in CONTRACT[name]["signals"]:
			assert_true(node.has_signal(signal_name),
				"%s 缺少信号：%s" % [name, signal_name])


func test_game_manager_exposes_contract_state_fields() -> void:
	var node: Node = _get_autoload("GameManager")
	if node == null:
		fail_test("GameManager 缺失")
		return
	var names: Array = []
	for entry in node.get_property_list():
		names.append(entry["name"])
	for prop in CONTRACT["GameManager"]["props"]:
		assert_has(names, prop, "GameManager 缺少状态字段：%s" % prop)


# AC3：骨架阶段方法可返回占位值，但不得抛异常，调用方能正常运行。
func test_contract_methods_do_not_crash_when_called_with_placeholder_args() -> void:
	var gm: Node = _get_autoload("GameManager")
	var tip: Node = _get_autoload("KnowledgeTip")
	var db: Node = _get_autoload("RecipeDB")
	var llm: Node = _get_autoload("LLMClient")
	var map: Node = _get_autoload("WorldMap")
	if gm == null or tip == null or db == null or llm == null or map == null:
		fail_test("autoload 未全部注册，无法执行调用冒烟")
		return

	assert_typeof(gm.is_night(), TYPE_BOOL)
	assert_typeof(gm.current_zone(), TYPE_STRING)
	assert_typeof(gm.move_speed_multiplier(), TYPE_FLOAT)
	assert_typeof(gm.get_flag("no_such_flag"), TYPE_BOOL)
	assert_eq(gm.get_balance("no.such.key", 42.0), 42.0, "缺键必须返回默认值")
	assert_typeof(gm.get_ui_string("no_such_ui_key"), TYPE_STRING)

	assert_typeof(tip.is_shown("no_such_tip"), TYPE_BOOL)
	tip.clear_queue()

	assert_typeof(db.get_substance("no_such_substance"), TYPE_DICTIONARY)
	assert_typeof(db.all_substances(), TYPE_ARRAY)
	assert_typeof(db.get_recipe("no_such_recipe"), TYPE_DICTIONARY)
	assert_typeof(db.unlocked_recipes(), TYPE_ARRAY)
	var craft: Dictionary = db.try_craft([], "portable", "none")
	for field in ["success", "recipe_id", "outputs", "card", "fail_reason", "fail_tip_id", "requires_pure_check"]:
		assert_has(craft, field, "try_craft 返回缺字段：%s" % field)

	assert_typeof(llm.is_offline(), TYPE_BOOL)
	assert_typeof(llm.has_api_key(), TYPE_BOOL)

	assert_typeof(map.is_unlocked("grassland"), TYPE_BOOL)
	assert_typeof(map.all_zones(), TYPE_ARRAY)
	assert_typeof(map.get_zone("grassland"), TYPE_DICTIONARY)
