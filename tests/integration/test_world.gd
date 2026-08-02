# 世界总装（TP-17）：白盒地图 + world.tscn 接线——区域触发、采集物生成与清晨刷新、
# 刷怪（CO 幽灵/酸雾怪）、死亡掉落包、复活回床、昼夜 CanvasModulate、ui_manager 输入屏蔽、
# 合成台/卡片/背包/图鉴接线、睡觉渐黑、河边引导字幕、use_item 快捷使用。
extends GutTest

const WORLD_SCENE: String = "res://scenes/main/world.tscn"

const BAL_DAY_DURATION: String = "daynight.day_duration"
const BAL_NIGHT_DURATION: String = "daynight.night_duration"
const BAL_NIGHT_BRIGHTNESS: String = "daynight.night_brightness"

var gm: Node = null
var tip: Node = null
var recipe_db: Node = null
var world_map: Node = null
var _world: Node = null
var _player: Node = null


func before_each() -> void:
	var root: Window = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	tip = root.get_node_or_null(^"KnowledgeTip")
	recipe_db = root.get_node_or_null(^"RecipeDB")
	world_map = root.get_node_or_null(^"WorldMap")
	assert_not_null(gm, "GameManager autoload 必须存在")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if gm == null or tip == null:
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	tip.reload()
	if recipe_db != null:
		recipe_db.reload()
		recipe_db.reset_unlocked()
		recipe_db.reset_rotation()
	_world = null
	_player = null
	if not ResourceLoader.exists(WORLD_SCENE):
		fail_test("尚未实现 %s（TP-17 世界总装）" % WORLD_SCENE)
		return
	_world = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(_world) # 世界不进 autofree：跨测试复用 autoload 状态需要显式清理
	await wait_process_frames(3)
	_player = _world.get_node_or_null(^"Player")


func after_each() -> void:
	if _world != null:
		remove_child(_world)
		_world.queue_free()
		_world = null
	if gm != null:
		gm.reset_clock()
		gm.reset_stats()
		gm.set_flag("explosion_happened", false)
		gm.set_flag("purity_check_unlocked", false)
		gm.set_zone("grassland")
	if tip != null:
		tip.clear_queue()


func _skip_unless_ready() -> bool:
	return _world == null


func _ui_manager() -> Node:
	return _world.get_node_or_null(^"UILayer/UIManager")


func _day_length() -> float:
	return float(gm.get_balance(BAL_DAY_DURATION, 360.0))


func _night_length() -> float:
	return float(gm.get_balance(BAL_NIGHT_DURATION, 180.0))


# 总装：玩家/ HUD / 字幕层 / 合成台 / 卡片 / 背包 / 图鉴 / 学院 / CanvasModulate 全部就位。
func test_world_assembles_all_parts() -> void:
	if _skip_unless_ready():
		return
	assert_not_null(_player, "世界应有 Player")
	assert_true(_player.is_in_group("player"), "玩家应在 player 组")
	for path: String in [
		"UILayer/HUD", "UILayer/TipLayer", "UILayer/CraftPanel", "UILayer/CardPopup",
		"UILayer/InventoryPanel", "UILayer/CodexPanel", "UILayer/UIManager",
		"ZoneTriggers", "Collectables", "Facilities", "Monsters",
		"AcademyBuilding", "CanvasModulate",
	]:
		assert_not_null(_world.get_node_or_null(NodePath(path)), "缺节点：%s" % path)
	# 玩家背包与道具效果已注入（TP-09/TP-10 的鸭子类型约定）。
	assert_not_null(_player.get("inventory"), "玩家背包应已注入")
	assert_not_null(_player.get("item_effects"), "玩家道具效果应已注入")


# 区域触发（FR-C-03 的场景侧）：走进矿洞触发 set_zone。
func test_zone_triggers_switch_zone() -> void:
	if _skip_unless_ready():
		return
	assert_eq(gm.current_zone(), "grassland", "出生在草原")
	_player.global_position = Vector2(1900, -20)
	await wait_physics_frames(5)
	assert_eq(gm.current_zone(), "mine", "走进矿洞应切换区域")
	_player.global_position = Vector2(-1200, -20)
	await wait_physics_frames(5)
	assert_eq(gm.current_zone(), "saltlake", "走进盐湖应切换区域")


# 采集物生成（FR-G-01 接线）：按地图标记生成，拾取入包 + 首次统计进 HUD。
func test_collectables_spawn_and_feed_hud_counter() -> void:
	if _skip_unless_ready():
		return
	var container: Node = _world.get_node(^"Collectables")
	var initial: int = container.get_child_count()
	assert_true(initial >= 10, "白盒地图应撒至少 10 个采集物：%d" % initial)
	var target: Node = null
	for child: Node in container.get_children():
		if str(child.get("substance_id")) == "o2":
			target = child
			break
	assert_not_null(target, "草原上应有 O₂ 光球")
	if target == null:
		return
	target.interact(_player)
	var hud: Node = _world.get_node(^"UILayer/HUD")
	assert_true(hud.collected_text().contains("1"), "首次收集后 HUD 计数应为 1：%s" % hud.collected_text())


# 清晨刷新（FR-C-05 AC3 接线）：resources_respawned 后采集物重新可拾取。
func test_collectables_respawn_on_morning() -> void:
	if _skip_unless_ready():
		return
	var container: Node = _world.get_node(^"Collectables")
	var initial: int = container.get_child_count()
	var target: Node = container.get_child(0)
	target.interact(_player)
	await wait_process_frames(1) # queue_free 在帧末生效
	assert_eq(container.get_child_count(), initial - 1, "拾取后少一个")
	gm.sleep_until_morning() # 触发 resources_respawned
	await wait_process_frames(2)
	assert_eq(container.get_child_count(), initial, "清晨后采集物应刷新回原数")


# 死亡掉落包接线（FR-C-06 AC2/AC3 世界段）：死亡点生成掉落包、背包清空、复活回床。
func test_death_spawns_drop_bag_and_respawn_at_bed() -> void:
	if _skip_unless_ready():
		return
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("o2", 3)
	_player.global_position = Vector2(1500, -20)
	await wait_process_frames(2) # 让 respawn reference 同步到死亡点
	gm.modify_health(-999.0)
	await wait_process_frames(2)
	assert_eq(inventory.count_of("o2"), 0, "死亡后背包清空")
	var bag: Node = null
	for child: Node in _world.get_children():
		if child.has_method("items") and child.has_signal("drop_collected"):
			bag = child
			break
	assert_not_null(bag, "死亡点应生成掉落包")
	if bag != null:
		assert_almost_eq(bag.global_position.x, 1500.0, 1.0, "掉落包在死亡点 x")
		assert_eq(int(bag.items()[0].get("count", 0)), 3, "掉落包含死亡时全部物品")
	# 复活：确认死亡画面 → 三值回满 + 位置回床。
	var death_screen: Node = _world.get_node_or_null(^"UILayer/DeathScreen")
	assert_not_null(death_screen, "应有死亡画面")
	if death_screen != null:
		assert_true(death_screen.is_open(), "死亡画面应弹出")
		death_screen.confirm()
		await wait_process_frames(2)
		assert_almost_eq(gm.health, gm.health_max, 0.001, "复活生命回满")
		var bed: Node = _world.get_node_or_null(^"Facilities/FacilityBed")
		assert_not_null(bed, "营地应有床")
		if bed != null:
			assert_almost_eq(_player.global_position.x, bed.global_position.x, 4.0, "复活位置为营地床")


# 昼夜 tint（FR-C-04 AC3）：入夜 CanvasModulate 变暗，清晨恢复。
func test_canvas_modulate_tints_at_night() -> void:
	if _skip_unless_ready():
		return
	var tint: CanvasModulate = _world.get_node(^"CanvasModulate")
	var before: Color = tint.color
	gm.tick(_day_length())
	await wait_seconds(0.8)
	var brightness: float = float(gm.get_balance(BAL_NIGHT_BRIGHTNESS, 0.35))
	assert_true(tint.color.r < before.r, "入夜应变暗")
	assert_almost_eq(tint.color.r, brightness, 0.05, "暗度按 balance.night_brightness")
	gm.tick(_night_length())
	await wait_seconds(0.8)
	assert_almost_eq(tint.color.r, 1.0, 0.05, "清晨恢复")


# 酸雾怪接线（FR-G-11 AC1 世界段）：夜晚刷 2~3 只、清晨清除。
func test_acid_mist_spawner_wired() -> void:
	if _skip_unless_ready():
		return
	var spawner: Node = _world.get_node_or_null(^"Monsters/MistSpawner")
	assert_not_null(spawner, "应有酸雾怪刷新器")
	if spawner == null:
		return
	gm.tick(_day_length())
	await wait_process_frames(2)
	assert_between(spawner.alive_count(), 2, 3, "夜晚刷 2~3 只酸雾怪")
	gm.tick(_night_length())
	await wait_process_frames(2)
	assert_eq(spawner.alive_count(), 0, "清晨清除酸雾怪")


# CO 幽灵接线（FR-G-10 AC1 世界段）：矿洞全天有、草原仅夜晚。
func test_co_ghost_presence_rules() -> void:
	if _skip_unless_ready():
		return
	var monsters: Node = _world.get_node(^"Monsters")
	var mine_ghosts: int = 0
	var grass_ghost: Node = null
	for child: Node in monsters.get_children():
		if child.has_method("drift_step"):
			if child.name == "GrassGhost":
				grass_ghost = child
			else:
				mine_ghosts += 1
	assert_true(mine_ghosts >= 1, "矿洞应常驻 CO 幽灵")
	assert_null(grass_ghost, "白天草原无 CO 幽灵")
	gm.tick(_day_length())
	await wait_process_frames(2)
	grass_ghost = monsters.get_node_or_null(^"GrassGhost")
	assert_not_null(grass_ghost, "夜晚草原应刷 CO 幽灵")
	gm.tick(_night_length())
	await wait_process_frames(2)
	assert_null(monsters.get_node_or_null(^"GrassGhost"), "清晨草原幽灵退场")


# 背包面板接线（FR-U-05 AC1）：Tab 经 ui_manager 打开 → 玩家输入被屏蔽。
func test_inventory_blocks_player_input() -> void:
	if _skip_unless_ready():
		return
	var panel: Node = _world.get_node(^"UILayer/InventoryPanel")
	var event: InputEventAction = InputEventAction.new()
	event.action = "inventory"
	event.pressed = true
	panel._unhandled_input(event)
	await wait_process_frames(1)
	assert_true(panel.is_open(), "Tab 打开背包")
	assert_true(_player.get("input_blocked"), "背包打开时玩家输入被屏蔽")
	panel._unhandled_input(event)
	await wait_process_frames(1)
	assert_false(panel.is_open(), "再按 Tab 关闭")
	assert_false(_player.get("input_blocked"), "关闭后恢复")


# 合成台接线（FR-G-05 入口）：空背包交互实验台 → 打开合成界面（ui_manager 裁决）。
func test_bench_opens_craft_panel() -> void:
	if _skip_unless_ready():
		return
	var bench: Node = _world.get_node_or_null(^"Facilities/FacilityBench")
	assert_not_null(bench, "营地应有实验台/合成台")
	if bench == null:
		return
	bench.interact(_player)
	await wait_process_frames(1)
	var craft: Node = _world.get_node(^"UILayer/CraftPanel")
	assert_true(craft.is_open(), "合成台交互应打开合成界面")
	assert_true(_player.get("input_blocked"), "合成界面打开时屏蔽玩家输入")
	craft.close()
	await wait_process_frames(1)
	assert_false(_player.get("input_blocked"), "关闭合成界面后恢复")


# 卡片接线（FR-G-06 世界段）：合成成功 → 卡片弹窗弹出。
func test_craft_success_opens_card_popup() -> void:
	if _skip_unless_ready():
		return
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("stick", 1)
	inventory.add_item("s", 1)
	var craft: Node = _world.get_node(^"UILayer/CraftPanel")
	var popup: Node = _world.get_node(^"UILayer/CardPopup")
	craft.open()
	craft.add_material("stick")
	craft.add_material("s")
	craft.select_tool("portable")
	craft.ignite()
	await wait_process_frames(1)
	assert_true(popup.is_open(), "合成成功应弹出知识卡片")
	assert_true(_player.get("input_blocked"), "卡片弹出时屏蔽玩家输入")
	popup.close()
	assert_false(_player.get("input_blocked"), "跳过卡片后恢复")


# 快捷使用（FR-G-12 接线）：数字键使用快捷栏道具。
func test_hotkey_uses_item() -> void:
	if _skip_unless_ready():
		return
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("oxygen_tank", 1)
	gm.modify_oxygen(-40.0)
	var before: float = gm.oxygen
	var event: InputEventAction = InputEventAction.new()
	event.action = "use_item_1"
	event.pressed = true
	_world._unhandled_input(event)
	var restore: float = float(gm.get_balance("items.oxygen_tank_restore", 50.0))
	var expected: float = minf(before + restore, gm.oxygen_max)
	assert_almost_eq(gm.oxygen, expected, 0.001, "氧气瓶应按 balance 补氧（clamp 到上限）")
	assert_eq(inventory.count_of("oxygen_tank"), 0, "消耗品用后 -1")


# 装备接线（FR-G-12/FR-P-03 世界段）：数字键装备硫火把 → 视野半径扩大。
func test_hotkey_equips_torch() -> void:
	if _skip_unless_ready():
		return
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("sulfur_torch", 1)
	var event: InputEventAction = InputEventAction.new()
	event.action = "use_item_1"
	event.pressed = true
	_world._unhandled_input(event)
	assert_true(_player.is_torch_equipped(), "使用后应装备硫火把")
	var torch_radius: float = float(gm.get_balance("daynight.torch_view_radius", 220.0))
	assert_almost_eq(_player.view_radius(), torch_radius, 0.001, "火把视野半径按 balance")


# 学院接线（TP-17）：学院实例在世界内，聊天框注册为不屏蔽输入的面板。
func test_academy_instanced_with_chat_registered() -> void:
	if _skip_unless_ready():
		return
	var academy: Node = _world.get_node(^"AcademyBuilding")
	var chat: Node = academy.get_node_or_null(^"%ChatPanel")
	assert_not_null(chat, "学院内应有聊天框")
	var manager: Node = _ui_manager()
	assert_not_null(manager, "应有 ui_manager")
	if manager != null and manager.has_method("has_panel"):
		assert_true(manager.has_panel("chat"), "聊天框应注册进 ui_manager")


# 新手引导（FR-U-02 AC3 世界段）：走近河边触发一次 zone_river。
func test_river_hint_fires_once() -> void:
	if _skip_unless_ready():
		return
	assert_false(tip.is_shown("zone_river"), "开场未触发河边字幕")
	_player.global_position = Vector2(750, -20)
	await wait_physics_frames(5)
	assert_true(tip.is_shown("zone_river"), "走近河边应触发 zone_river")


# 活性炭砸幽灵接线（FR-G-10 AC3 世界段）：数字键用活性炭消灭范围内 CO 幽灵。
func test_carbon_thrown_at_ghost_kills_it() -> void:
	if _skip_unless_ready():
		return
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("activated_carbon", 1)
	var ghost: Node2D = _world.get_node_or_null(^"Monsters/CoGhostA")
	assert_not_null(ghost, "矿洞应有 CO 幽灵")
	if ghost == null:
		return
	_player.global_position = ghost.global_position + Vector2(30, 0)
	await wait_process_frames(1)
	var event: InputEventAction = InputEventAction.new()
	event.action = "use_item_1"
	event.pressed = true
	_world._unhandled_input(event)
	await wait_process_frames(2)
	assert_eq(inventory.count_of("activated_carbon"), 0, "活性炭用后消耗")
	assert_true(ghost.is_destroyed() or not is_instance_valid(ghost), "幽灵应被消灭")


# 原住民交易接线（FR-G-15 世界段）：E 进交易态 → 数字键卖出装备换能量。
func test_native_trader_trade_flow() -> void:
	if _skip_unless_ready():
		return
	var trader: Node = _world.get_node_or_null(^"Facilities/NativeTrader")
	assert_not_null(trader, "营地应有原住民")
	if trader == null:
		return
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("oxygen_tank", 1)
	# 世界是活的：能量每帧持续消耗，断言只能锚定交易前后的相对增量。
	var energy_before: float = gm.energy
	gm.modify_energy(-50.0)
	trader.interact(_player)
	assert_true(trader.is_trading(), "E 应进入交易态")
	var event: InputEventAction = InputEventAction.new()
	event.action = "use_item_1"
	event.pressed = true
	_world._unhandled_input(event)
	assert_eq(inventory.count_of("oxygen_tank"), 0, "道具已卖出")
	var expected: float = energy_before - 50.0 + float(gm.get_balance("items.trade_energy_restore", 20.0))
	assert_almost_eq(gm.energy, expected, 0.001, "能量应按 balance 增加")
	assert_false(trader.is_trading(), "成交后退出交易态")


# 矿洞呼吸提示（SPEC-02 §4.1 / B5）：进入 mine 且该区域氧气净速率为负时
# 触发一次 sys_mine_breath；离开后再次进入不重复（KnowledgeTip.show_once 去重）。
func test_mine_breath_tip_fires_once_in_mine() -> void:
	if _skip_unless_ready():
		return
	assert_false(tip.is_shown("sys_mine_breath"), "开场未触发矿洞呼吸提示")
	assert_true(gm.oxygen_net_rate() > 0.0, "草原氧气净速率应为正（前置条件）")
	gm.set_zone("mine")
	assert_true(gm.oxygen_net_rate() < 0.0, "矿洞氧气净速率应为负（前置条件）")
	assert_true(tip.is_shown("sys_mine_breath"), "进入矿洞应触发 sys_mine_breath")


# 光合作用横幅（SPEC-05 §3.1 / B6）：草原白天首次进入触发 zone_photosynthesis；
# 夜晚进入不触发；次日白天进入（此前未触发过）仍应触发。
func test_photosynthesis_tip_day_only() -> void:
	if _skip_unless_ready():
		return
	assert_false(tip.is_shown("zone_photosynthesis"), "开场未触发光合作用横幅")
	# 夜晚进入草原：不触发。
	gm.set_zone("camp")
	gm.tick(_day_length())
	assert_true(gm.is_night(), "应已入夜（前置条件）")
	gm.set_zone("grassland")
	assert_false(tip.is_shown("zone_photosynthesis"), "夜晚进入草原不应触发光合作用横幅")
	# 次日白天进入：触发。
	gm.tick(_night_length())
	assert_false(gm.is_night(), "应已到清晨（前置条件）")
	gm.set_zone("camp")
	gm.set_zone("grassland")
	assert_true(tip.is_shown("zone_photosynthesis"), "白天进入草原应触发光合作用横幅")



func test_sleep_fade_plays() -> void:
	if _skip_unless_ready():
		return
	gm.tick(_day_length()) # 入夜才能睡
	var bed: Node = _world.get_node(^"Facilities/FacilityBed")
	bed.interact(_player)
	await wait_process_frames(2)
	var fade: ColorRect = _world.get_node_or_null(^"FadeLayer/FadeRect")
	assert_not_null(fade, "应有渐黑层")
	if fade != null:
		assert_true(fade.modulate.a > 0.01, "睡觉后渐黑层应正在淡出")
		assert_true(gm.day_count >= 2, "睡觉跳夜到第二天")


# D2（FR-C-08 AC1，2026-08-02）：树根元数据 world_spawn_override="academy_gate" 时，
# world._ready 把玩家出生在学院门口而非默认出生点，且元数据一次性消费（不残留影响下次进入）。
func test_academy_gate_spawn_override() -> void:
	if _skip_unless_ready():
		return
	var default_pos: Vector2 = _player.global_position
	var root: Window = Engine.get_main_loop().root
	root.set_meta("world_spawn_override", "academy_gate")
	remove_child(_world)
	_world.queue_free()
	_world = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(_world)
	await wait_process_frames(3)
	_player = _world.get_node_or_null(^"Player")
	assert_not_null(_player, "重建世界后玩家应存在")
	if _player == null:
		return
	assert_ne(
		_player.global_position, default_pos,
		"学院门进入时出生点不应是默认出生点（D2）"
	)
	var academy: Node2D = _world.get_node_or_null(^"AcademyBuilding") as Node2D
	assert_not_null(academy, "世界应有学院建筑")
	if academy != null:
		assert_true(
			_player.global_position.distance_to(academy.global_position) < 200.0,
			"学院门进入时出生点应在学院门口附近（D2）"
		)
	assert_false(
		root.has_meta("world_spawn_override"),
		"出生点覆盖元数据应被一次性消费（D2）"
	)
