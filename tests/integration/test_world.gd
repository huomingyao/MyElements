# 世界总装（TP-17）：白盒地图 + world.tscn 接线——区域触发、采集物生成与清晨刷新、
# 刷怪（CO 幽灵/酸雾怪）、死亡掉落包、复活回床、昼夜 CanvasModulate、ui_manager 输入屏蔽、
# 合成台/卡片/背包/图鉴接线、睡觉渐黑、河边引导字幕、use_item 快捷使用。
extends GutTest

const WORLD_SCENE: String = "res://scenes/main/world.tscn"

const BAL_DAY_DURATION: String = "daynight.day_duration"
const BAL_NIGHT_DURATION: String = "daynight.night_duration"
const BAL_NIGHT_BRIGHTNESS: String = "daynight.night_brightness"

# 字幕队列冲刷时长（秒）：一次性推进足够清空多条排队横幅（单条最长 warning 5s）。
const TIP_FLUSH_SECONDS: float = 60.0

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
	get_tree().paused = false # 暂停测试的安全复位：树留着 paused 会拖垮后续用例
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


# 总装：玩家/ HUD / 字幕层 / 合成台 / 卡片 / 背包 / 图鉴 / 导师室 / 黑洞 / CanvasModulate 全部就位。
func test_world_assembles_all_parts() -> void:
	if _skip_unless_ready():
		return
	assert_not_null(_player, "世界应有 Player")
	assert_true(_player.is_in_group("player"), "玩家应在 player 组")
	for path: String in [
		"UILayer/HUD", "UILayer/TipLayer", "UILayer/CraftPanel", "UILayer/CardPopup",
		"UILayer/InventoryPanel", "UILayer/CodexPanel", "UILayer/UIManager",
		"UILayer/MentorRoom",
		"ZoneTriggers", "Collectables", "Facilities", "Monsters",
		"BlackHoles", "CanvasModulate",
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


# 合成台接线（FR-G-05 入口 + AC5）：空背包交互实验台 → 合成界面与背包同屏并列打开。
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
	var inv: Node = _world.get_node(^"UILayer/InventoryPanel")
	assert_true(craft.is_open(), "合成台交互应打开合成界面")
	assert_true(inv.is_open(), "AC5：合成界面打开时背包同屏并列打开")
	assert_true(_player.get("input_blocked"), "合成界面打开时屏蔽玩家输入")
	craft.close()
	await wait_process_frames(1)
	assert_true(inv.is_open(), "关闭合成界面后背包保持打开（AC5）")
	assert_true(_player.get("input_blocked"), "背包仍打开时输入仍屏蔽")
	# 背包无 close_requested，经 ui_manager 关闭（等价 Esc 路径）。
	_ui_manager().close_active()
	await wait_process_frames(1)
	assert_false(_player.get("input_blocked"), "全部关闭后恢复")


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


# 提纯卡片接线（FR-G-14 AC2 世界段，包B-A1）：实验台三步完成 → 卡片弹窗弹出（物理变化说明）。
func test_purify_completion_opens_card_popup() -> void:
	if _skip_unless_ready():
		return
	var bench: Node = _world.get_node_or_null(^"Facilities/FacilityBench")
	var popup: Node = _world.get_node_or_null(^"UILayer/CardPopup")
	assert_not_null(bench, "营地应有实验台")
	assert_not_null(popup, "应有卡片弹窗")
	if bench == null or popup == null:
		return
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("crude_salt", 1)
	for i: int in 3:
		bench.interact(_player)
	await wait_process_frames(1)
	assert_eq(inventory.count_of("nacl"), 1, "三步完成后应得到 nacl（前置）")
	assert_true(popup.is_open(), "提纯三步完成应弹出知识卡片（FR-G-14 AC2）")
	popup.close()
	await wait_process_frames(1)


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


# 导师室接线（2026-08-02 独立页方案）：导师室注册为 ui_manager 模态面板（屏蔽玩家输入），
# 面板契约 open/close/is_open 生效；聊天框内嵌其中，不再单列注册。
func test_mentor_room_registered_as_modal_panel() -> void:
	if _skip_unless_ready():
		return
	var room: Node = _world.get_node_or_null(^"UILayer/MentorRoom")
	assert_not_null(room, "世界 UILayer 应有导师室")
	var manager: Node = _ui_manager()
	assert_not_null(manager, "应有 ui_manager")
	if room == null or manager == null:
		return
	if manager.has_method("has_panel"):
		assert_true(manager.has_panel("mentor_room"), "导师室应注册进 ui_manager")
	assert_false(room.is_open(), "初始应关闭")
	manager.open("mentor_room")
	await wait_process_frames(1)
	assert_true(manager.is_open("mentor_room"), "ui_manager.open(mentor_room) 应命中面板契约")
	assert_true(room.is_open(), "导师室契约 is_open() 应为真")
	assert_true(room.visible, "打开后页面应可见")
	assert_true(bool(_player.get("input_blocked")), "导师室打开应屏蔽玩家输入")
	manager.close_active()
	await wait_process_frames(1)
	assert_false(room.is_open(), "close_active() 应经契约关闭导师室")
	assert_false(room.visible, "关闭后页面应隐藏")


# 区域间黑洞（2026-08-02）：玩家触碰草原东侧黑洞→黑屏传送→落在营地并切区。
func test_black_hole_transports_player_to_next_zone() -> void:
	if _skip_unless_ready():
		return
	_player.global_position = Vector2(370, -20)
	await wait_physics_frames(3)
	_player.global_position = Vector2(389, -60)
	await wait_seconds(1.2)
	assert_true(
		_player.global_position.x > 420.0,
		"触碰草原东缘触发器应被传送到营地侧：%s" % str(_player.global_position)
	)
	await wait_physics_frames(3)
	assert_eq(gm.current_zone(), "camp", "传送落点应触发营地切区")


# 新手引导（FR-U-02 AC3 世界段）：走近河边触发一次 zone_river。
func test_river_hint_fires_once() -> void:
	if _skip_unless_ready():
		return
	assert_false(tip.is_shown("zone_river"), "开场未触发河边字幕")
	_player.global_position = Vector2(570, -20)
	await wait_physics_frames(5)
	# 新语义（包C-3）：入队≠已展示；出生区域横幅可能占着播放位，结算队列后再断言。
	tip.advance(TIP_FLUSH_SECONDS)
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


# 砸空反馈（B 级体验缺口）：范围内无目标时数字键不消耗道具，且播 sys_no_target 字幕；
# 修复前 use_item 返回结果被丢弃，按键零反馈（不消耗/不提示，玩家以为坏了）。
func test_hotkey_kill_item_without_target_shows_feedback() -> void:
	if _skip_unless_ready():
		return
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("activated_carbon", 1)
	# 玩家留在草原出生区域：矿洞幽灵远在 96px 射程外，草原夜晚幽灵白天不刷。
	var event: InputEventAction = InputEventAction.new()
	event.action = "use_item_1"
	event.pressed = true
	_world._unhandled_input(event)
	await wait_process_frames(2)
	assert_eq(inventory.count_of("activated_carbon"), 1, "无目标时不应消耗道具")
	tip.advance(TIP_FLUSH_SECONDS)
	assert_true(tip.is_shown("sys_no_target"), "无目标使用砸怪道具应播 sys_no_target 反馈")


# 中和喷雾砸酸雾怪接线（FR-G-11 AC3 世界段）：数字键用喷雾消灭范围内酸雾怪。
# 酸雾怪刷在 MistSpawner 下（_monsters 的孙节点），目标搜索必须递归到它们。
func test_spray_thrown_at_acid_mist_kills_it() -> void:
	if _skip_unless_ready():
		return
	var spawner: Node = _world.get_node_or_null(^"Monsters/MistSpawner")
	assert_not_null(spawner, "应有酸雾怪刷新器")
	if spawner == null:
		return
	var mists: Array = spawner.spawn_night_mists()
	assert_true(mists.size() > 0, "应刷出酸雾怪")
	if mists.is_empty():
		return
	var mist: Node2D = mists[0] as Node2D
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("neutral_spray", 1)
	_player.global_position = mist.global_position + Vector2(30, 0)
	await wait_process_frames(1)
	var event: InputEventAction = InputEventAction.new()
	event.action = "use_item_1"
	event.pressed = true
	_world._unhandled_input(event)
	await wait_process_frames(2)
	assert_eq(inventory.count_of("neutral_spray"), 0, "中和喷雾用后消耗")
	assert_true(mist.is_destroyed() or not is_instance_valid(mist), "酸雾怪应被消灭")


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
	# 新语义（包C-3）：入队≠已展示；区域横幅可能占着播放位，结算队列后再断言。
	tip.advance(TIP_FLUSH_SECONDS)
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
	# 新语义（包C-3）：入队≠已展示，_shown 在 _start 时才标记；
	# 夜晚排队的区域横幅尚未播完，驱动 advance 结算队列后再断言。
	tip.advance(TIP_FLUSH_SECONDS)
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


# ==== 包A「世界与玩家手感」新增用例 ====

# 包A-1：暂停菜单真暂停——打开时 get_tree().paused=true、三值 tick 停住，关闭恢复；
# 菜单本体 process_mode=ALWAYS，否则暂停后按钮收不到输入。
func test_pause_menu_truly_pauses_tree() -> void:
	if _skip_unless_ready():
		return
	var pause: Node = _world.get_node_or_null(^"UILayer/PauseMenu")
	assert_not_null(pause, "应有暂停菜单")
	if pause == null:
		return
	assert_eq(int(pause.process_mode), int(Node.PROCESS_MODE_ALWAYS),
		"暂停菜单须 process_mode=ALWAYS，否则暂停后按钮失效")
	pause.open()
	await wait_process_frames(1)
	assert_true(get_tree().paused, "打开暂停菜单应暂停场景树")
	var energy_at_pause: float = gm.energy
	await wait_physics_frames(10)
	assert_eq(gm.energy, energy_at_pause, "暂停时三值 tick 应停住")
	pause.close()
	await wait_process_frames(1)
	assert_false(get_tree().paused, "关闭暂停菜单应恢复")


# 包A-2：快捷栏尊重 input_blocked——模态面板打开时数字键不消耗道具、不生效。
func test_hotkeys_blocked_when_panel_open() -> void:
	if _skip_unless_ready():
		return
	var inventory: RefCounted = _player.get("inventory")
	inventory.add_item("oxygen_tank", 1)
	gm.modify_oxygen(-40.0)
	_ui_manager().open("inventory")
	await wait_process_frames(1)
	assert_true(_player.get("input_blocked"), "前置：背包打开应屏蔽玩家输入")
	var oxygen_before: float = gm.oxygen
	var event: InputEventAction = InputEventAction.new()
	event.action = "use_item_1"
	event.pressed = true
	_world._unhandled_input(event)
	assert_eq(inventory.count_of("oxygen_tank"), 1, "面板打开时数字键不应消耗道具")
	assert_almost_eq(gm.oxygen, oxygen_before, 0.001, "面板打开时数字键不应生效")
	_ui_manager().close_active()


# 包A-2 例外：图鉴 C 键在 input_blocked 时仍放行——图鉴自身是模态面板，
# 若一并屏蔽，打开后将无法用 C 关闭。
func test_codex_key_still_toggles_when_blocked() -> void:
	if _skip_unless_ready():
		return
	var event: InputEventAction = InputEventAction.new()
	event.action = "codex"
	event.pressed = true
	_world._unhandled_input(event)
	await wait_process_frames(1)
	assert_true(_ui_manager().is_open("codex"), "C 键应打开图鉴")
	assert_true(_player.get("input_blocked"), "前置：图鉴打开时输入被屏蔽")
	_world._unhandled_input(event)
	await wait_process_frames(1)
	assert_false(_ui_manager().is_open("codex"), "图鉴打开时 C 键应仍能关闭图鉴（例外放行）")


# 包A-3：采集物生成后应围绕标记高度漂浮，不被 Tween 拉回 y=0
# （生成顺序 bug：先入树触发 _ready 捕获 _base_y=0，后设位置被 Tween 拉回）。
func test_collectables_stay_at_marker_height() -> void:
	if _skip_unless_ready():
		return
	var markers: Node = _world.get_node_or_null(^"Map/CollectableSpawns")
	assert_not_null(markers, "白盒地图应有 CollectableSpawns")
	if markers == null or markers.get_child_count() == 0:
		return
	var base_y: float = (markers.get_child(0) as Marker2D).global_position.y
	await wait_seconds(0.6) # 让漂浮 Tween 跑过一段，bug 会在此间显形
	var container: Node = _world.get_node(^"Collectables")
	assert_true(container.get_child_count() > 0, "应有采集物")
	for child: Node in container.get_children():
		assert_almost_eq((child as Node2D).global_position.y, base_y, 5.5,
			"采集物 %s 应围绕标记高度漂浮，不被拉回 y=0" % str(child.get("substance_id")))


# 包A-4：复活横跨地图传送后相机应立即对齐床边区域（reset_smoothing），不开平滑慢追。
# FR-C-10（2026-08-03）：相机按营地区矩形钳制，床在营地东侧（x=1240）时屏幕中心
# 只能到钳位点（营地中心域 [920,1030]），断言对齐到钳位点而非床坐标本身。
func test_camera_snaps_to_bed_after_respawn() -> void:
	if _skip_unless_ready():
		return
	var cam: Camera2D = _player.get_node_or_null(^"%Camera") as Camera2D
	var bed: Node = _world.get_node_or_null(^"Facilities/FacilityBed")
	var death_screen: Node = _world.get_node_or_null(^"UILayer/DeathScreen")
	assert_not_null(cam, "玩家应有 %Camera")
	assert_not_null(bed, "营地应有床")
	assert_not_null(death_screen, "应有死亡画面")
	if cam == null or bed == null or death_screen == null:
		return
	_player.global_position = Vector2(2200.0, -20.0) # 矿洞深处，远离营地床
	await wait_process_frames(2)
	gm.modify_health(-999.0)
	await wait_process_frames(2)
	death_screen.confirm()
	# 落点 ZoneTrigger 物理检测需数帧才切区（切区时才换钳制并 snap），等足余量。
	await wait_process_frames(8)
	var half_view: float = 320.0 # 640 视口半宽
	var expected_x: float = clampf(
		(bed as Node2D).global_position.x,
		ZONE_BOUNDS_CAMP.position.x + half_view,
		ZONE_BOUNDS_CAMP.end.x - half_view
	)
	assert_almost_eq(cam.get_screen_center_position().x, expected_x, 60.0,
		"复活传送后相机应立即对齐营地钳位点，而非横跨地图慢追")


# 2026-08-03 等宽重排：四区紧凑排列，原学院缺口带消除；区域触发器完整覆盖各自区
# （传送行为见 test_black_hole_transports_player_to_next_zone）。
func test_zone_triggers_cover_former_gaps() -> void:
	if _skip_unless_ready():
		return
	_player.global_position = Vector2(-160.0, -20.0) # 草原中部
	await wait_physics_frames(3)
	assert_eq(gm.current_zone(), "grassland", "前置：x=-160 应属草原")
	_player.global_position = Vector2(585.0, -20.0) # 营地中西部
	await wait_physics_frames(5)
	assert_eq(gm.current_zone(), "camp", "x=585 应归属营地")


# 包A-8：受伤触发相机小幅震动，震动结束 offset 精确复位。
func test_hurt_triggers_camera_shake() -> void:
	if _skip_unless_ready():
		return
	var cam: Camera2D = _player.get_node_or_null(^"%Camera") as Camera2D
	assert_not_null(cam, "玩家应有 %Camera")
	if cam == null:
		return
	assert_true(cam.has_method("shake"), "相机应提供 shake(intensity, duration)")
	gm.modify_health(-5.0)
	await wait_process_frames(2)
	assert_gt(cam.offset.length(), 0.1, "受伤应触发相机震动")
	await wait_seconds(0.5)
	assert_almost_eq(cam.offset.length(), 0.0, 0.001, "震动结束后 offset 应精确复位")


# 包A-8：爆炸事件接线相机震动（氢气事件 explosion_triggered → 世界 → 相机 shake）。
# 白盒断言连接关系：行为复用 test_hurt_triggers_camera_shake 已验证的 shake 本体。
func test_explosion_event_wired_to_camera_shake() -> void:
	if _skip_unless_ready():
		return
	var hydrogen: Variant = _world.get("_hydrogen")
	assert_not_null(hydrogen, "世界应有氢气事件实例")
	if hydrogen == null:
		return
	var found: bool = false
	for connection: Dictionary in (hydrogen as Object).get_signal_connection_list(&"explosion_triggered"):
		var callable: Callable = connection.get("callable", Callable())
		if callable.get_object() == _world:
			found = true
			break
	assert_true(found, "世界应把 explosion_triggered 接到相机震动")


# 收口W1-4：DeathScreen 纳入 Esc 裁决——死亡画面打开时按 Esc，
# ui_manager 在 _input 层吞掉：不叠开暂停菜单、不暂停场景树、不关死亡画面。
func test_esc_swallowed_while_death_screen_open() -> void:
	if _skip_unless_ready():
		return
	var death_screen: Node = _world.get_node_or_null(^"UILayer/DeathScreen")
	var pause: Node = _world.get_node_or_null(^"UILayer/PauseMenu")
	assert_not_null(death_screen, "应有死亡画面")
	assert_not_null(pause, "应有暂停菜单")
	if death_screen == null or pause == null:
		return
	gm.modify_health(-999.0)
	await wait_process_frames(2)
	assert_true(death_screen.is_open(), "前置：死亡画面已打开")
	var event: InputEventAction = InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	Input.parse_input_event(event)
	await wait_process_frames(2)
	assert_true(death_screen.is_open(), "Esc 不许关闭死亡画面")
	assert_false(pause.visible, "死亡画面打开时 Esc 不许叠开暂停菜单")
	assert_false(get_tree().paused, "死亡画面打开时 Esc 不许暂停场景树")
	# 清理：确认复活回床，避免死亡状态拖垮后续用例。
	death_screen.confirm()
	await wait_process_frames(2)
	assert_false(death_screen.is_open(), "确认后死亡画面应关闭")


# ==== FR-C-10 区域相机钳制与边界幕布（2026-08-03） ====

# 白盒区域相机矩形（与 SPEC-02 §3 区域可视性规则一致；四区等宽 1000、x 钳区域、y 全高）。
const ZONE_BOUNDS_GRASSLAND: Rect2 = Rect2(-640, -300, 1000, 400)
const ZONE_BOUNDS_SALTLAKE: Rect2 = Rect2(-1700, -300, 1000, 400)
const ZONE_BOUNDS_CAMP: Rect2 = Rect2(420, -300, 1000, 400)
const ZONE_BOUNDS_MINE: Rect2 = Rect2(1480, -300, 1000, 400)

# 四区画布节点名（等宽断言用）。
const ZONE_BG_NAMES: Array[String] = ["SaltlakeBg", "GrasslandBg", "CampBg", "MineBg"]
const ZONE_BG_WIDTH: float = 1000.0


func _assert_camera_bounds(rect: Rect2, label: String) -> void:
	var cam: Camera2D = _player.get_node_or_null(^"%Camera") as Camera2D
	assert_not_null(cam, "玩家应有 %Camera")
	if cam == null:
		return
	assert_eq(cam.limit_left, int(rect.position.x), "%s：limit_left" % label)
	assert_eq(cam.limit_top, int(rect.position.y), "%s：limit_top" % label)
	assert_eq(cam.limit_right, int(rect.end.x), "%s：limit_right" % label)
	assert_eq(cam.limit_bottom, int(rect.end.y), "%s：limit_bottom" % label)


# AC1：出生初始相机边界 == 草原矩形（不再用全图 MAP_BOUNDS）。
func test_camera_initial_bounds_grassland() -> void:
	if _skip_unless_ready():
		return
	_assert_camera_bounds(ZONE_BOUNDS_GRASSLAND, "出生初始")


# AC1：zone_changed 即切换相机边界到对应区域矩形。
func test_zone_change_switches_camera_bounds() -> void:
	if _skip_unless_ready():
		return
	gm.set_zone("mine")
	await wait_process_frames(1)
	_assert_camera_bounds(ZONE_BOUNDS_MINE, "切到矿洞")
	gm.set_zone("saltlake")
	await wait_process_frames(1)
	_assert_camera_bounds(ZONE_BOUNDS_SALTLAKE, "切到盐湖")


# AC2（v2 等宽画布）：四区背景等宽 1000px（≥640 视口，钳制下屏幕恒被铺满不露黑边），
# 且不再有幕布节点（窄区消除后幕布方案废弃）。
func test_zone_backgrounds_uniform_width() -> void:
	if _skip_unless_ready():
		return
	var backgrounds: Node = _world.get_node_or_null(^"Map/ZoneBackgrounds")
	assert_not_null(backgrounds, "白盒地图应有 ZoneBackgrounds")
	if backgrounds == null:
		return
	for bg_name: String in ZONE_BG_NAMES:
		var bg: Polygon2D = backgrounds.get_node_or_null(NodePath(bg_name)) as Polygon2D
		assert_not_null(bg, "缺区域背景：%s" % bg_name)
		if bg == null:
			continue
		var xs: Array = []
		for point: Vector2 in bg.polygon:
			xs.append(point.x)
		assert_almost_eq(xs.max() - xs.min(), ZONE_BG_WIDTH, 0.01,
			"%s 画布宽应为 %s" % [bg_name, str(ZONE_BG_WIDTH)])
	for child: Node in backgrounds.get_children():
		assert_false(str(child.name).begins_with("Curtain"), "不应再有幕布节点：%s" % child.name)


# AC3：黑洞过场期间（渐黑~渐亮）玩家输入锁定，结束后恢复。
func test_travel_locks_input_during_transition() -> void:
	if _skip_unless_ready():
		return
	assert_false(_player.get("input_blocked"), "前置：开场输入未屏蔽")
	_player.global_position = Vector2(370, -20)
	await wait_physics_frames(3)
	_player.global_position = Vector2(389, -60)
	await wait_seconds(0.15) # 过场已开始（渐黑 0.25s 内），traveled 尚未发出
	assert_true(_player.get("input_blocked"), "过场期间玩家输入应锁定")
	await wait_seconds(1.2) # 过场结束（0.6s）+ 余量
	assert_false(_player.get("input_blocked"), "过场结束后输入应恢复")
