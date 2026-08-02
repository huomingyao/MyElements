# IT-G14 / FR-G-14：粗盐提纯三步顺序流程（溶解 → 过滤 → 蒸发，跳步拒绝并给提示），
# 完成得 nacl + 物理变化卡片；肥皂水试湖水显示 sys_hardwater。
# 三步状态机是纯逻辑类（facility_salt_purifier.gd），可被直接实例化（SPEC-06 §3）。
extends GutTest

const PURIFIER_SCRIPT: String = "res://scenes/gameplay/facility_salt_purifier.gd"
const BENCH_SCENE: String = "res://scenes/gameplay/facility_bench.tscn"
const LAKE_SCENE: String = "res://scenes/gameplay/facility_lake_water.tscn"
const INVENTORY_SCRIPT: String = "res://scripts/gameplay/inventory.gd"

var gm: Node = null
var tip: Node = null
var recipe_db: Node = null


class FakePlayer:
	extends Node2D
	var inventory: RefCounted = null


func before_each() -> void:
	var root: Window = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	tip = root.get_node_or_null(^"KnowledgeTip")
	recipe_db = root.get_node_or_null(^"RecipeDB")
	assert_not_null(gm, "GameManager autoload 必须存在")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	assert_not_null(recipe_db, "RecipeDB autoload 必须存在")
	if gm == null or tip == null or recipe_db == null:
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	gm.set_zone("camp")
	tip.reload()
	recipe_db.reload()
	recipe_db.reset_unlocked()


func _new_inventory() -> RefCounted:
	return (load(INVENTORY_SCRIPT) as GDScript).new()


func _new_purifier() -> RefCounted:
	if not ResourceLoader.exists(PURIFIER_SCRIPT):
		fail_test("尚未实现 %s（FR-G-14 / TP-10）" % PURIFIER_SCRIPT)
		return null
	return (load(PURIFIER_SCRIPT) as GDScript).new()


func _make_player() -> FakePlayer:
	var player := FakePlayer.new()
	player.inventory = _new_inventory()
	add_child_autofree(player)
	return player


func _spawn(scene_path: String) -> Node:
	if not ResourceLoader.exists(scene_path):
		fail_test("尚未实现 %s（FR-G-14 / TP-10）" % scene_path)
		return null
	var node: Node = (load(scene_path) as PackedScene).instantiate()
	add_child_autofree(node)
	return node


# AC1：三步必须按顺序完成——上来就「蒸发」被拒绝，给提示（sys_purify），不给产物，状态不变。
func test_skip_to_evaporate_is_rejected_with_hint() -> void:
	var purifier: RefCounted = _new_purifier()
	if purifier == null:
		return
	var inventory: RefCounted = _new_inventory()
	inventory.add_item("crude_salt", 1)
	var result: Dictionary = purifier.advance("evaporate", inventory)
	assert_false(bool(result.get("ok", true)), "跳步应被拒绝")
	assert_eq(purifier.expected_step(), "dissolve", "跳步后仍应等待第一步 dissolve")
	assert_eq(inventory.count_of("nacl"), 0, "跳步不给产物")
	assert_eq(inventory.count_of("crude_salt"), 1, "跳步不消耗粗盐")
	assert_true(tip.is_shown("sys_purify"), "跳步时应给出正确顺序的提示字幕")


# AC1：溶解之后跳过「过滤」直接「蒸发」同样被拒绝。
func test_skip_middle_step_is_rejected() -> void:
	var purifier: RefCounted = _new_purifier()
	if purifier == null:
		return
	var inventory: RefCounted = _new_inventory()
	inventory.add_item("crude_salt", 1)
	purifier.advance("dissolve", inventory)
	var result: Dictionary = purifier.advance("evaporate", inventory)
	assert_false(bool(result.get("ok", true)), "跳过过滤应被拒绝")
	assert_eq(purifier.expected_step(), "filter", "拒绝后仍应等待 filter")
	assert_eq(inventory.count_of("nacl"), 0, "跳步不给产物")


# AC1：没有粗盐时连第一步都不能开始。
func test_start_requires_crude_salt() -> void:
	var purifier: RefCounted = _new_purifier()
	if purifier == null:
		return
	var inventory: RefCounted = _new_inventory()
	var result: Dictionary = purifier.advance("dissolve", inventory)
	assert_false(bool(result.get("ok", true)), "没有粗盐不应开始流程")
	assert_eq(purifier.expected_step(), "dissolve", "状态不应前进")


# AC1（每步一条字幕）：三次按序 advance 各入队一条字幕。
# 字幕引擎是串行队列（SPEC-03 §3）：第一条上台，其余排队，故断言「上台 + 排队 = 3」。
func test_each_step_shows_one_tip() -> void:
	var purifier: RefCounted = _new_purifier()
	if purifier == null:
		return
	var inventory: RefCounted = _new_inventory()
	inventory.add_item("crude_salt", 1)
	for step: String in ["dissolve", "filter", "evaporate"]:
		var result: Dictionary = purifier.advance(step, inventory)
		assert_true(bool(result.get("ok", false)), "按序执行 %s 应成功" % step)
	var on_stage: int = 1 if tip.current_tip_id() == "sys_purify" else 0
	assert_eq(on_stage + int(tip.queue_size()), 3, "三步应各产生一条字幕（上台 1 条 + 排队 2 条）")
	assert_true(tip.is_shown("sys_purify"), "提纯字幕应已触发")


# AC2：完成后获得 nacl，粗盐被消耗，卡片来自数据表且标注物理过程；配方登记解锁。
func test_full_sequence_yields_nacl_and_physical_card() -> void:
	var purifier: RefCounted = _new_purifier()
	if purifier == null:
		return
	var inventory: RefCounted = _new_inventory()
	inventory.add_item("crude_salt", 1)
	var result: Dictionary = {}
	for step: String in ["dissolve", "filter", "evaporate"]:
		result = purifier.advance(step, inventory)
	assert_true(bool(result.get("done", false)), "第三步后流程应完成")
	assert_eq(inventory.count_of("nacl"), 1, "完成后应得到 1 份 nacl")
	assert_eq(inventory.count_of("crude_salt"), 0, "完成后粗盐应被消耗")
	var card: Dictionary = result.get("card", {})
	assert_false(card.is_empty(), "完成后应返回知识卡片")
	var recipe: Dictionary = recipe_db.get_recipe("r_salt_purify")
	assert_eq(str(card.get("equation", "")), str(recipe.get("equation", "")),
		"卡片方程式应来自 recipes.json（标注为物理过程）")
	assert_true(bool(recipe.get("is_physical", false)), "r_salt_purify 在数据表中应标注 is_physical")
	assert_true(recipe_db.unlocked_recipes().has("r_salt_purify"), "完成后配方应登记解锁（图鉴用）")


# 实验台（bench）场景：连续三次 E 交互自动按序推进，最终得到 nacl。
func test_bench_interact_advances_full_flow() -> void:
	var bench: Node = _spawn(BENCH_SCENE)
	if bench == null:
		return
	var player: FakePlayer = _make_player()
	player.inventory.add_item("crude_salt", 1)
	for i: int in 3:
		bench.interact(player)
	assert_eq(player.inventory.count_of("nacl"), 1, "三次交互后应得到 nacl")
	assert_eq(player.inventory.count_of("crude_salt"), 0, "粗盐应被消耗")


# 实验台没有粗盐也没有进行中的流程时：给合成引导字幕（合成界面由 TP-07 接线）。
func test_bench_without_materials_shows_craft_hint() -> void:
	var bench: Node = _spawn(BENCH_SCENE)
	if bench == null:
		return
	bench.interact(_make_player())
	assert_true(tip.is_shown("sys_craft_hint"), "空实验台应给合成引导字幕 sys_craft_hint")


# AC2（包B-A1）：三步完成时实验台经 card_ready 信号把知识卡片转交世界（此前 advance 返回值被丢弃）。
func test_bench_emits_card_on_completion() -> void:
	var bench: Node = _spawn(BENCH_SCENE)
	if bench == null:
		return
	assert_true(bench.has_signal("card_ready"), "实验台应有 card_ready 信号（FR-G-14 AC2）")
	if not bench.has_signal("card_ready"):
		return
	var cards: Array = []
	bench.card_ready.connect(func(card: Dictionary) -> void: cards.append(card))
	var player: FakePlayer = _make_player()
	player.inventory.add_item("crude_salt", 1)
	for i: int in 3:
		bench.interact(player)
	assert_eq(cards.size(), 1, "三步完成应发出一次 card_ready")
	if cards.size() == 1:
		var recipe: Dictionary = recipe_db.get_recipe("r_salt_purify")
		assert_eq(str(cards[0].get("title", "")), str(recipe.get("card_title", "")),
			"卡片标题应来自 recipes.json 的 r_salt_purify")
		assert_false(str(cards[0].get("body", "")).is_empty(), "卡片现象应非空（说明这是物理变化）")
		assert_false(str(cards[0].get("footer", "")).is_empty(), "卡片底行应非空（card_footer）")


# AC2（包B-A1）：中间步骤不许弹卡片——前两次交互（溶解/过滤）不发 card_ready。
func test_bench_intermediate_steps_emit_no_card() -> void:
	var bench: Node = _spawn(BENCH_SCENE)
	if bench == null:
		return
	if not bench.has_signal("card_ready"):
		fail_test("实验台应有 card_ready 信号（FR-G-14 AC2）")
		return
	var cards: Array = []
	bench.card_ready.connect(func(card: Dictionary) -> void: cards.append(card))
	var player: FakePlayer = _make_player()
	player.inventory.add_item("crude_salt", 1)
	bench.interact(player)
	bench.interact(player)
	assert_eq(cards.size(), 0, "溶解/过滤两步不应弹出知识卡片")


# AC3：对湖水使用肥皂水 → 消耗 1 份肥皂水，显示 sys_hardwater。
func test_lake_water_with_soap_shows_hardwater_tip() -> void:
	var lake: Node = _spawn(LAKE_SCENE)
	if lake == null:
		return
	var player: FakePlayer = _make_player()
	player.inventory.add_item("soap_water", 1)
	lake.interact(player)
	assert_eq(player.inventory.count_of("soap_water"), 0, "肥皂水应被消耗")
	assert_true(tip.is_shown("sys_hardwater"), "应显示硬水字幕 sys_hardwater")


# AC3 边界：没有肥皂水时不显示硬水结论，给湖水提示（zone_salt 提到湖水是硬水）。
func test_lake_water_without_soap_shows_hint_only() -> void:
	var lake: Node = _spawn(LAKE_SCENE)
	if lake == null:
		return
	var player: FakePlayer = _make_player()
	lake.interact(player)
	assert_false(tip.is_shown("sys_hardwater"), "没有肥皂水不应显示硬水结论字幕")
	assert_true(tip.is_shown("zone_salt"), "没有肥皂水时应给湖水提示")
