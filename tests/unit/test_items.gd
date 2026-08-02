# UT-G12 / FR-G-12：八种道具按数据表生效。
# AC1 效果值全部读自 balance（改数值不改代码）；AC2 装备型不消耗、消耗型 -1；
# AC3 氧气瓶 +50 氧气、葡萄糖 +20 能量、硫火把提供照明半径（读 daynight.torch_view_radius）。
# 用 load() 按路径取脚本而不是 class_name：实现缺失时是断言失败而非编译错误（SPEC-06 §2）。
extends GutTest

const ITEM_EFFECTS_PATH: String = "res://scripts/gameplay/item_effects.gd"
const INVENTORY_PATH: String = "res://scripts/gameplay/inventory.gd"

# SPEC-05 §8 的八种道具与其类型（effect 枚举见 SPEC-04 §10）。
const EXPECTED_ITEMS: Dictionary = {
	"sulfur_torch": {"type": "equip", "effect": "light"},
	"neutral_spray": {"type": "consume", "effect": "kill_acid"},
	"carbon_mask": {"type": "equip", "effect": "immune_co"},
	"extinguisher": {"type": "consume", "effect": "extinguish"},
	"oxygen_tank": {"type": "consume", "effect": "restore_oxygen"},
	"glucose": {"type": "consume", "effect": "restore_energy"},
	"soap_water": {"type": "consume", "effect": "test_hardwater"},
	"stick": {"type": "material", "effect": "none"},
}


# 假喷雾目标：只实现 hit_by_spray()，证明 ItemEffects 不认识具体怪物类型。
class FakeSprayTarget:
	extends Node

	var hit_count: int = 0

	func hit_by_spray() -> void:
		hit_count += 1


var fx: RefCounted = null
var inv: RefCounted = null
var gm: Node = null
var tip: Node = null


func before_each() -> void:
	var root: Window = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	assert_not_null(gm, "GameManager autoload 必须存在")
	tip = root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if tip != null:
		tip.reload() # 复位字幕展示记录，避免跨测试污染
	if gm != null:
		gm.reset_stats()
	fx = null
	inv = null
	if not ResourceLoader.exists(ITEM_EFFECTS_PATH):
		fail_test("尚未实现 %s（FR-G-12 / TP-09）" % ITEM_EFFECTS_PATH)
		return
	fx = (load(ITEM_EFFECTS_PATH) as GDScript).new()
	assert_not_null(fx, "ItemEffects 应可直接实例化（SPEC-06 §3 纯逻辑可测性）")
	if not ResourceLoader.exists(INVENTORY_PATH):
		fail_test("缺少依赖 %s（TP-06）" % INVENTORY_PATH)
		return
	inv = (load(INVENTORY_PATH) as GDScript).new()


# AC1：八种道具全部从 items.json 读入，type/effect 与 SPEC-05 §8 一致。
func test_all_items_load_from_data_table() -> void:
	if fx == null:
		return
	for item_id: String in EXPECTED_ITEMS:
		var def: Dictionary = fx.get_item(item_id)
		assert_false(def.is_empty(), "items.json 应包含道具：%s" % item_id)
		if def.is_empty():
			continue
		assert_eq(str(def.get("type", "")), str(EXPECTED_ITEMS[item_id]["type"]),
			"%s 的 type 应与数据表一致" % item_id)
		assert_eq(str(def.get("effect", "")), str(EXPECTED_ITEMS[item_id]["effect"]),
			"%s 的 effect 应与数据表一致" % item_id)


# AC1：效果值读自 balance.json 的点分键——测试按数据表里的 key 动态取值交叉验证，
# 证明代码里没有写死数值（改 balance 即改效果，不需要改代码）。
func test_effect_values_come_from_balance_table() -> void:
	if fx == null:
		return
	var cases: Dictionary = {
		"oxygen_tank": 50.0,
		"glucose": 20.0,
		"sulfur_torch": 220.0,
	}
	for item_id: String in cases:
		var def: Dictionary = fx.get_item(item_id)
		var key: String = str(def.get("effect_value_key", ""))
		assert_false(key.is_empty(), "%s 应在 items.json 里配置 effect_value_key" % item_id)
		if key.is_empty():
			continue
		var from_balance: float = float(gm.get_balance(key, -1.0))
		assert_almost_eq(fx.effect_value(item_id), from_balance, 0.001,
			"%s 的效果值应读自 balance 键 %s" % [item_id, key])
		assert_almost_eq(fx.effect_value(item_id), float(cases[item_id]), 0.001,
			"%s 的效果值应与 SPEC-02 §5 一致" % item_id)


# AC2：装备型道具使用不消耗数量，进入已装备集合（持续生效）。
func test_equipment_is_not_consumed() -> void:
	if fx == null:
		return
	inv.add_item("carbon_mask", 1)
	var result: Dictionary = fx.use_item("carbon_mask", inv)
	assert_true(bool(result.get("success", false)), "口罩装备应成功")
	assert_false(bool(result.get("consumed", true)), "装备型不应消耗")
	assert_eq(inv.count_of("carbon_mask"), 1, "装备后数量应保持 1")
	assert_true(fx.is_equipped("carbon_mask"), "装备后应在已装备集合中")
	assert_true(fx.is_equipment("carbon_mask"), "口罩应识别为装备型")
	assert_false(fx.is_consumable("carbon_mask"), "口罩不应识别为消耗型")


# AC2：重复装备不叠加、不出错。
func test_equip_twice_does_not_duplicate() -> void:
	if fx == null:
		return
	assert_true(fx.equip("carbon_mask"), "首次装备应成功")
	assert_true(fx.equip("carbon_mask"), "重复装备应幂等成功")
	var equipped: Array = fx.equipped_ids()
	var count: int = 0
	for item_id: String in equipped:
		if item_id == "carbon_mask":
			count += 1
	assert_eq(count, 1, "已装备集合不应出现重复")


# AC2：喷雾为消耗型，命中目标后数量 -1。
func test_neutral_spray_is_consumed_on_hit() -> void:
	if fx == null:
		return
	var target: FakeSprayTarget = add_child_autofree(FakeSprayTarget.new())
	inv.add_item("neutral_spray", 2)
	var result: Dictionary = fx.use_item("neutral_spray", inv, target)
	assert_true(bool(result.get("success", false)), "喷雾应对目标使用成功")
	assert_true(bool(result.get("consumed", false)), "消耗型使用后应标记 consumed")
	assert_eq(inv.count_of("neutral_spray"), 1, "使用后数量应 -1")
	assert_eq(target.hit_count, 1, "目标应收到一次 hit_by_spray")
	assert_true(fx.is_consumable("neutral_spray"), "喷雾应识别为消耗型")


# AC2：灭火器为消耗型，使用后数量 -1。
func test_extinguisher_is_consumed() -> void:
	if fx == null:
		return
	inv.add_item("extinguisher", 1)
	var result: Dictionary = fx.use_item("extinguisher", inv)
	assert_true(bool(result.get("success", false)), "灭火器使用应成功")
	assert_eq(inv.count_of("extinguisher"), 0, "灭火器使用后数量应 -1")


# 喷雾没有命中目标时不使用成功、不消耗（不许对着空气浪费道具）。
func test_spray_without_target_fails_and_keeps_item() -> void:
	if fx == null:
		return
	inv.add_item("neutral_spray", 1)
	var result: Dictionary = fx.use_item("neutral_spray", inv)
	assert_false(bool(result.get("success", true)), "无目标时喷雾不应使用成功")
	assert_eq(inv.count_of("neutral_spray"), 1, "失败时不应消耗")


# 背包里没有该道具时使用失败，不崩溃。
func test_use_without_item_in_inventory_fails() -> void:
	if fx == null:
		return
	var target: FakeSprayTarget = add_child_autofree(FakeSprayTarget.new())
	var result: Dictionary = fx.use_item("neutral_spray", inv, target)
	assert_false(bool(result.get("success", true)), "背包无此道具应失败")
	assert_eq(target.hit_count, 0, "失败时目标不应被命中")


# AC3：氧气瓶 +50 氧气（数值读 balance，断言用 SPEC-02 §4.1 的口径交叉验证）。
func test_oxygen_tank_restores_50_oxygen() -> void:
	if fx == null:
		return
	gm.modify_oxygen(-60.0)
	assert_almost_eq(gm.oxygen, 40.0, 0.001, "前提：氧气降到 40")
	inv.add_item("oxygen_tank", 1)
	var result: Dictionary = fx.use_item("oxygen_tank", inv)
	assert_true(bool(result.get("success", false)), "氧气瓶使用应成功")
	assert_almost_eq(gm.oxygen, 90.0, 0.001, "氧气应 +50")
	assert_eq(inv.count_of("oxygen_tank"), 0, "氧气瓶应消耗")


# AC3：葡萄糖 +20 能量。
func test_glucose_restores_20_energy() -> void:
	if fx == null:
		return
	gm.modify_energy(-50.0)
	assert_almost_eq(gm.energy, 50.0, 0.001, "前提：能量降到 50")
	inv.add_item("glucose", 1)
	var result: Dictionary = fx.use_item("glucose", inv)
	assert_true(bool(result.get("success", false)), "葡萄糖使用应成功")
	assert_almost_eq(gm.energy, 70.0, 0.001, "能量应 +20")


# AC3：硫火把提供照明——效果值就是 balance 的 torch_view_radius（FR-P-03 的道具侧）。
func test_sulfur_torch_provides_light_radius() -> void:
	if fx == null:
		return
	inv.add_item("sulfur_torch", 1)
	var result: Dictionary = fx.use_item("sulfur_torch", inv)
	assert_true(bool(result.get("success", false)), "硫火把装备应成功")
	assert_almost_eq(float(result.get("value", 0.0)), 220.0, 0.001, "照明半径应为 220")
	assert_almost_eq(fx.effect_value("sulfur_torch"),
		float(gm.get_balance("daynight.torch_view_radius", -1.0)), 0.001,
		"照明半径应读自 balance")
	assert_true(fx.is_equipped("sulfur_torch"), "硫火把应进入已装备集合")
	assert_eq(inv.count_of("sulfur_torch"), 1, "装备型不应消耗")


# 使用带 tip_id 的道具要走字幕引擎（sys_energy_food 等知识字幕）。
func test_use_shows_tip_from_data_table() -> void:
	if fx == null:
		return
	inv.add_item("glucose", 1)
	fx.use_item("glucose", inv)
	assert_true(tip.is_shown("sys_energy_food"), "葡萄糖使用应触发 items.json 里配置的字幕")


# 防御性输入：未知 id、材料型道具使用失败且不崩溃。
func test_unknown_and_material_items_fail_gracefully() -> void:
	if fx == null:
		return
	var unknown: Dictionary = fx.use_item("not_an_item", inv)
	assert_false(bool(unknown.get("success", true)), "未知 id 应失败")
	inv.add_item("stick", 1)
	var material: Dictionary = fx.use_item("stick", inv)
	assert_false(bool(material.get("success", true)), "材料型道具不可使用")
	assert_eq(inv.count_of("stick"), 1, "失败时不应消耗")
	assert_true(fx.get_item("not_an_item").is_empty(), "未知 id 查询应返回空字典")


# 逻辑代码不许出现中文文案（NFR-04；push_warning/push_error/print 诊断日志除外）。
func test_source_has_no_chinese_literals() -> void:
	if not ResourceLoader.exists(ITEM_EFFECTS_PATH):
		return
	var file: FileAccess = FileAccess.open(ITEM_EFFECTS_PATH, FileAccess.READ)
	assert_not_null(file, "item_effects.gd 应可读")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("#"):
			continue
		if line.contains("push_warning(") or line.contains("push_error(") or line.contains("print("):
			continue
		var code: String = line
		var comment_at: int = code.find("#")
		if comment_at >= 0:
			code = code.substr(0, comment_at)
		for i: int in code.length():
			var c: int = code.unicode_at(i)
			assert_false(c >= 0x4E00 and c <= 0x9FFF, "逻辑代码出现中文字面量：%s" % line)
