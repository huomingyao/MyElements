# IT-G13 / FR-G-13：营地设施——过滤器（水→纯净水 + sys_filter）、
# 电解器（纯净水→H₂+O₂ 按体积比 1:2 + sys_electrolysis）、
# 篝火（进食 +40 能量 + 旁边生命缓慢回复）。
# 设施只实现 SPEC-03 §5 三方法约定，玩家不认识它们的具体类型。
extends GutTest

const FILTER_SCENE: String = "res://scenes/gameplay/facility_filter.tscn"
const ELECTROLYZER_SCENE: String = "res://scenes/gameplay/facility_electrolyzer.tscn"
const CAMPFIRE_SCENE: String = "res://scenes/gameplay/facility_campfire.tscn"
const INVENTORY_SCRIPT: String = "res://scripts/gameplay/inventory.gd"

var gm: Node = null
var tip: Node = null
var recipe_db: Node = null


# 假玩家：只携带一个 inventory（TP-06 的纯逻辑背包），设施不认识它的具体类型。
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
	tip.reload()  # 真实 tips.json：字幕 id 必须来自数据表
	recipe_db.reload()
	recipe_db.reset_unlocked()


func _make_player() -> FakePlayer:
	var player := FakePlayer.new()
	player.inventory = (load(INVENTORY_SCRIPT) as GDScript).new()
	add_child_autofree(player)
	return player


func _spawn(scene_path: String) -> Node:
	if not ResourceLoader.exists(scene_path):
		fail_test("尚未实现 %s（FR-G-13 / TP-10）" % scene_path)
		return null
	var node: Node = (load(scene_path) as PackedScene).instantiate()
	add_child_autofree(node)
	return node


# SPEC-03 §5：三个设施都实现三方法约定，交互系统无需认识具体类型（FR-P-02 AC3 的延伸）。
func test_facilities_implement_interact_contract() -> void:
	for scene_path: String in [FILTER_SCENE, ELECTROLYZER_SCENE, CAMPFIRE_SCENE]:
		var facility: Node = _spawn(scene_path)
		if facility == null:
			continue
		assert_true(facility.has_method("get_interact_prompt"), "%s 缺 get_interact_prompt" % scene_path)
		assert_true(facility.has_method("can_interact"), "%s 缺 can_interact" % scene_path)
		assert_true(facility.has_method("interact"), "%s 缺 interact" % scene_path)
		assert_true(str(facility.get_interact_prompt()) != "", "%s 的提示 id 不应为空" % scene_path)


# AC1：过滤器交互：水 → 纯净水，触发净水四步字幕 sys_filter。
func test_filter_converts_water_to_clean_water() -> void:
	var filter: Node = _spawn(FILTER_SCENE)
	if filter == null:
		return
	var player: FakePlayer = _make_player()
	player.inventory.add_item("h2o", 1)
	filter.interact(player)
	assert_eq(player.inventory.count_of("h2o"), 0, "过滤后原料水应被消耗")
	assert_eq(player.inventory.count_of("h2o_clean"), 1, "过滤后应得到 1 份纯净水")
	assert_true(tip.is_shown("sys_filter"), "过滤后应触发净水四步字幕 sys_filter")


# AC1 边界：没有水时不产纯净水，并给数据表内的提示（不许静默失败）。
func test_filter_without_water_gives_hint_and_no_output() -> void:
	var filter: Node = _spawn(FILTER_SCENE)
	if filter == null:
		return
	var player: FakePlayer = _make_player()
	filter.interact(player)
	assert_eq(player.inventory.count_of("h2o_clean"), 0, "没有水时不许产出纯净水")
	assert_true(tip.is_shown("zone_river"), "没有水时应提示去河边取水（zone_river）")


# AC2：电解器交互：纯净水 → H₂ + O₂，按体积比 1:2 给量，触发 sys_electrolysis。
func test_electrolyzer_gives_h2_o2_at_one_to_two_ratio() -> void:
	var electrolyzer: Node = _spawn(ELECTROLYZER_SCENE)
	if electrolyzer == null:
		return
	var player: FakePlayer = _make_player()
	player.inventory.add_item("h2o_clean", 1)
	electrolyzer.interact(player)
	assert_eq(player.inventory.count_of("h2o_clean"), 0, "电解后纯净水应被消耗")
	assert_eq(player.inventory.count_of("o2"), 1, "氧气应给 1 份")
	assert_eq(player.inventory.count_of("h2"), 2, "氢气应给 2 份（正氧负氢，体积比 1:2）")
	assert_eq(player.inventory.count_of("oxygen_tank"), 1,
		"电解成功应额外灌装 1 个氧气瓶（D4 / SPEC-02 §5）")
	assert_true(tip.is_shown("sys_electrolysis"), "电解后应触发 sys_electrolysis 字幕")


# AC2 边界：没有纯净水时不产气体，并提示先净水（sys_filter）。
func test_electrolyzer_without_clean_water_gives_hint_and_no_gas() -> void:
	var electrolyzer: Node = _spawn(ELECTROLYZER_SCENE)
	if electrolyzer == null:
		return
	var player: FakePlayer = _make_player()
	electrolyzer.interact(player)
	assert_eq(player.inventory.count_of("h2"), 0, "没有纯净水时不许产氢气")
	assert_eq(player.inventory.count_of("o2"), 0, "没有纯净水时不许产氧气")
	assert_eq(player.inventory.count_of("oxygen_tank"), 0, "没有纯净水时不许灌装氧气瓶")
	assert_true(tip.is_shown("sys_filter"), "没有纯净水时应提示先过滤（sys_filter）")


# AC3：篝火交互进食，能量精确 +balance 里的 campfire_meal_restore（+40）。
func test_campfire_meal_restores_energy_from_balance() -> void:
	var campfire: Node = _spawn(CAMPFIRE_SCENE)
	if campfire == null:
		return
	var player: FakePlayer = _make_player()
	var meal: float = float(gm.get_balance("items.campfire_meal_restore", -1.0))
	assert_almost_eq(meal, 40.0, 0.001, "篝火进食回复量应读自 balance（40）")
	gm.energy = 50.0
	campfire.interact(player)
	assert_almost_eq(gm.energy, 50.0 + meal, 0.001, "进食后能量应精确 +40")
	assert_true(tip.is_shown("sys_energy_food"), "进食应触发六大营养素字幕 sys_energy_food")


# AC3：能量接近上限时进食 clamp 到上限，不溢出。
func test_campfire_meal_clamps_at_energy_max() -> void:
	var campfire: Node = _spawn(CAMPFIRE_SCENE)
	if campfire == null:
		return
	var player: FakePlayer = _make_player()
	gm.energy = 90.0
	campfire.interact(player)
	assert_almost_eq(gm.energy, gm.energy_max, 0.001, "能量不应超过上限")


# AC3：篝火旁边生命缓慢回复（balance stats.health_regen_campfire = 1.0/s）。
# 时间用 apply_aura(delta) 注入（SPEC-06 §3 可测性约束），不等真实秒数。
func test_campfire_aura_heals_nearby_player() -> void:
	var campfire: Node = _spawn(CAMPFIRE_SCENE)
	if campfire == null:
		return
	var player: FakePlayer = _make_player()
	var rate: float = float(gm.get_balance("stats.health_regen_campfire", -1.0))
	assert_almost_eq(rate, 1.0, 0.001, "篝火回血速率应读自 balance（1.0/s）")
	gm.health = 50.0
	campfire.body_entered_heal_aura(player)
	campfire.apply_aura(5.0)
	assert_almost_eq(gm.health, 50.0 + rate * 5.0, 0.001, "篝火旁 5 秒应回复 5 点生命")
	campfire.body_exited_heal_aura(player)
	campfire.apply_aura(5.0)
	assert_almost_eq(gm.health, 55.0, 0.001, "离开篝火范围后不应继续回血")


# AC3 边界：不在篝火范围内不回血。
func test_campfire_aura_does_not_heal_outside() -> void:
	var campfire: Node = _spawn(CAMPFIRE_SCENE)
	if campfire == null:
		return
	gm.health = 50.0
	campfire.apply_aura(5.0)
	assert_almost_eq(gm.health, 50.0, 0.001, "范围外不应回血")
