# IT-C06 / FR-C-06（TP-11）：死亡、复活与掉落。
# AC1 生命归零弹死亡画面 + 字幕 sys_death；AC2 复活三值回满、位置回床、背包为空；
# AC3 掉落包含死亡瞬间背包全部物品、拾取原数量回包；AC4 下一次死亡前掉落包不消失。
# 世界编排（world.gd）不在本任务白名单内：测试里的「死亡时生成掉落包并清空背包」
# 一行接线就是世界场景将来要写的同一行，掉落包本体与复活契约在这里验证。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")
const InventoryScript: GDScript = preload("res://scripts/gameplay/inventory.gd")

const DEATH_SCREEN_PATH: String = "res://scenes/ui/death_screen.tscn"
const DEATH_SCREEN_SCRIPT_PATH: String = "res://scenes/ui/death_screen.gd"
const DROP_BAG_SCRIPT_PATH: String = "res://scenes/gameplay/drop_bag.gd"
const DROP_BAG_SCENE_PATH: String = "res://scenes/gameplay/drop_bag.tscn"

const TIP_DEATH: String = "sys_death"
const UI_TITLE_KEY: String = "death_title"
const PROMPT_KEY: String = "prompt_interact"

# 营地床铺坐标占位：床是 TP-10 设施，实机落点接线归世界场景；
# 这里验证的是「监听 player_respawned 落点」这条契约本身。
const BED_POSITION: Vector2 = Vector2(320.0, 180.0)
const DEATH_POSITION: Vector2 = Vector2(64.0, 96.0)

var gm: Node = null
var tip: Node = null


func before_each() -> void:
	gm = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	assert_not_null(gm, "GameManager autoload 必须存在")
	tip = Engine.get_main_loop().root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if gm == null or tip == null:
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	gm.set_zone("grassland")
	tip.reload()


# ==== 构造辅助（缺实现时记断言失败而不是脚本崩，SPEC-06 §2） ====

func _make_screen() -> Node:
	if not ResourceLoader.exists(DEATH_SCREEN_PATH):
		fail_test("尚未实现 %s（FR-C-06 AC1）" % DEATH_SCREEN_PATH)
		return null
	var screen: Node = (load(DEATH_SCREEN_PATH) as PackedScene).instantiate()
	add_child_autofree(screen)
	return screen


func _drop_bag_script() -> GDScript:
	if not ResourceLoader.exists(DROP_BAG_SCRIPT_PATH):
		fail_test("尚未实现 %s（FR-C-06 AC3）" % DROP_BAG_SCRIPT_PATH)
		return null
	return load(DROP_BAG_SCRIPT_PATH) as GDScript


# 世界编排占位：死亡时在死亡点生成掉落包（含背包全部物品）并清空背包。
# 返回生成的掉落包；掉落包脚本缺失时为 null 并已记断言失败。
func _world_on_player_died(world: Node, inventory: RefCounted) -> Node:
	var bag_script: GDScript = _drop_bag_script()
	if bag_script == null:
		return null
	var bag: Node = bag_script.spawn_at(world, DEATH_POSITION, inventory.slots())
	inventory.clear()
	return bag


func _die_at(position: Vector2) -> void:
	gm.set_respawn_reference_position(position)
	gm.modify_health(-gm.health_max)


func _ui_string(key: String) -> String:
	return str(Fixture.read_object("ui_strings.json").get(key, ""))


# 交互约定里的 player 参数：掉落包不读它，给个自动回收的空节点即可。
func _fake_player() -> Node:
	var player: Node = Node.new()
	add_child_autofree(player)
	return player


# ==== AC1：生命归零 → 死亡画面 + sys_death ====

func test_death_opens_screen_and_shows_sys_death_tip() -> void:
	var screen: Node = _make_screen()
	if screen == null:
		return
	if not screen.has_method("is_open"):
		fail_test("DeathScreen 应有 is_open()")
		return
	assert_false(screen.is_open(), "死亡前死亡画面必须隐藏")
	_die_at(DEATH_POSITION)
	assert_true(screen.is_open(), "生命归零应弹出死亡画面（AC1）")
	assert_true(tip.is_shown(TIP_DEATH), "死亡应触发字幕 %s（AC1）" % TIP_DEATH)
	assert_eq(str(tip.current_tip_id()), TIP_DEATH,
		"sys_death 为 warning 样式应抢占当前字幕（AC1）")


func test_death_screen_title_comes_from_ui_strings() -> void:
	var screen: Node = _make_screen()
	if screen == null:
		return
	var title: Node = screen.get_node_or_null(^"%TitleLabel")
	assert_not_null(title, "死亡画面应有唯一名节点 %TitleLabel")
	if title == null:
		return
	var expected: String = _ui_string(UI_TITLE_KEY)
	assert_false(expected.is_empty(), "ui_strings.json 应有 %s" % UI_TITLE_KEY)
	assert_eq(str(title.text), expected, "标题文案应取自 ui_strings.%s（NFR-04）" % UI_TITLE_KEY)


# ==== 优化包C-5：死亡画面信息丰富化（复活提示 / 掉落可捡回说明 / 坚持天数统计） ====

func test_death_screen_shows_respawn_hint_and_penalty_info() -> void:
	var screen: Node = _make_screen()
	if screen == null:
		return
	var hint: Node = screen.get_node_or_null(^"%HintLabel")
	assert_not_null(hint, "死亡画面应有唯一名节点 %HintLabel（复活操作提示）")
	var info: Node = screen.get_node_or_null(^"%InfoLabel")
	assert_not_null(info, "死亡画面应有唯一名节点 %InfoLabel（死亡后果说明）")
	if hint == null or info == null:
		return
	var expected_hint: String = _ui_string("death_hint")
	var expected_info: String = _ui_string("death_info")
	assert_false(expected_hint.is_empty(), "ui_strings.json 应有 death_hint（复活操作提示）")
	assert_false(expected_info.is_empty(), "ui_strings.json 应有 death_info（死亡后果说明）")
	assert_eq(str(hint.text), expected_hint, "复活提示应取自 ui_strings.death_hint（NFR-04）")
	assert_eq(str(info.text), expected_info, "后果说明应取自 ui_strings.death_info（NFR-04）")


func test_death_screen_shows_survived_day_count() -> void:
	var screen: Node = _make_screen()
	if screen == null:
		return
	var day_label: Node = screen.get_node_or_null(^"%DayLabel")
	assert_not_null(day_label, "死亡画面应有唯一名节点 %DayLabel（统计信息）")
	if day_label == null:
		return
	var expected_tpl: String = _ui_string("death_day")
	assert_false(expected_tpl.is_empty(), "ui_strings.json 应有 death_day（坚持天数）")
	gm.day_count = 3
	_die_at(DEATH_POSITION)
	assert_eq(
		str(day_label.text), expected_tpl.format({"n": 3}),
		"死亡画面应展示本局坚持天数统计（GameManager.day_count）"
	)


# ==== AC2：复活 → 三值回满、位置回床、背包为空、画面关闭 ====

func test_confirm_respawns_full_stats_and_closes_screen() -> void:
	var screen: Node = _make_screen()
	if screen == null:
		return
	for method_name in ["confirm", "is_open"]:
		if not screen.has_method(method_name):
			fail_test("DeathScreen 应有 %s()" % method_name)
			return
	_die_at(DEATH_POSITION)
	assert_true(screen.is_open(), "前置条件：死亡画面已打开")
	watch_signals(gm)
	screen.confirm()
	assert_signal_emitted(gm, "player_respawned", "确认后应触发复活信号")
	assert_almost_eq(gm.health, gm.health_max, 0.001, "复活后生命回满（AC2）")
	assert_almost_eq(gm.oxygen, gm.oxygen_max, 0.001, "复活后氧气回满（AC2）")
	assert_almost_eq(gm.energy, gm.energy_max, 0.001, "复活后能量回满（AC2）")
	assert_false(screen.is_open(), "复活后死亡画面应关闭")


func test_confirm_without_death_does_nothing() -> void:
	var screen: Node = _make_screen()
	if screen == null or not screen.has_method("confirm"):
		return
	watch_signals(gm)
	screen.confirm()
	assert_signal_not_emitted(gm, "player_respawned", "未死亡时确认不许触发复活")


# Esc 不确认复活（收口 W1）：暂停语义键交给 ui_manager 裁决，
# 死亡画面自身的「任意键确认」不许把 Esc 当成确认键。
func test_esc_does_not_confirm_death_screen() -> void:
	var screen: Node = _make_screen()
	if screen == null:
		return
	_die_at(DEATH_POSITION)
	assert_true(screen.is_open(), "前置条件：死亡画面已打开")
	watch_signals(gm)
	# 真实 Esc 是 InputEventKey（pause 动作绑定 Escape，见 project.godot）。
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_ESCAPE
	key_event.pressed = true
	screen._unhandled_input(key_event)
	assert_true(screen.is_open(), "Esc 不许关闭死亡画面")
	assert_signal_not_emitted(gm, "player_respawned", "Esc 不许触发复活")
	assert_almost_eq(gm.health, 0.0, 0.001, "Esc 后生命不应被复活回满")
	# 普通按键仍应确认复活（既有契约不回归）。
	var any_key: InputEventKey = InputEventKey.new()
	any_key.physical_keycode = KEY_SPACE
	any_key.pressed = true
	screen._unhandled_input(any_key)
	assert_signal_emitted(gm, "player_respawned", "普通按键仍应确认复活")


func test_respawn_moves_player_to_bed_position() -> void:
	var screen: Node = _make_screen()
	if screen == null:
		return
	# 落点契约：场景监听 player_respawned 把玩家放回营地床（game_manager.gd 注释）。
	# 用真实玩家场景验证信号能把节点移到床坐标；物理关掉避免重力干扰断言。
	var player: Node = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = DEATH_POSITION
	# ONE_SHOT：复活信号发一次即自动断开，避免测试结束后 autoload 上残留
	# 指向已回收节点的 lambda，污染后续测试文件。
	gm.player_respawned.connect(
		func() -> void:
			if is_instance_valid(player):
				player.global_position = BED_POSITION,
		CONNECT_ONE_SHOT)
	_die_at(DEATH_POSITION)
	screen.confirm()
	assert_eq(player.global_position, BED_POSITION, "复活后玩家应在营地床坐标（AC2）")


func test_inventory_empty_after_death_and_respawn() -> void:
	var screen: Node = _make_screen()
	if screen == null:
		return
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var inventory: RefCounted = InventoryScript.new()
	inventory.add_item("o2", 3)
	inventory.add_item("c", 2)
	_die_at(DEATH_POSITION)
	var bag: Node = _world_on_player_died(world, inventory)
	if bag == null:
		return
	screen.confirm()
	assert_eq(inventory.used_slots(), 0, "复活后背包应为空（AC2）")


# ==== AC3：掉落包含死亡瞬间背包全部物品；拾取原数量回包 ====

func test_drop_bag_spawned_at_death_position_with_all_items() -> void:
	var bag_script: GDScript = _drop_bag_script()
	if bag_script == null:
		return
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var inventory: RefCounted = InventoryScript.new()
	inventory.add_item("o2", 3)
	inventory.add_item("c", 2)
	var snapshot: Array = inventory.slots()
	watch_signals(gm)
	_die_at(DEATH_POSITION)
	# 注意：此断言的第 4 参是发射序号而非消息文本（GUT API），消息只能写到注释里。
	assert_signal_emitted_with_parameters(gm, "player_died", [DEATH_POSITION])
	var bag: Node = _world_on_player_died(world, inventory)
	if bag == null:
		return
	assert_eq(bag.global_position, DEATH_POSITION, "掉落包应生成在死亡点（AC3）")
	if not bag.has_method("items"):
		fail_test("DropBag 应有 items() 供断言内容")
		return
	assert_eq(bag.items(), snapshot, "掉落包应包含死亡瞬间背包全部物品（AC3）")


func test_pickup_returns_exact_items_to_inventory() -> void:
	var bag_script: GDScript = _drop_bag_script()
	if bag_script == null:
		return
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var inventory: RefCounted = InventoryScript.new()
	inventory.add_item("o2", 3)
	inventory.add_item("c", 2)
	var snapshot: Array = inventory.slots()
	_die_at(DEATH_POSITION)
	var bag: Node = _world_on_player_died(world, inventory)
	if bag == null:
		return
	for method_name in ["set_inventory", "interact", "can_interact", "get_interact_prompt"]:
		if not bag.has_method(method_name):
			fail_test("DropBag 应有 %s()（SPEC-03 §5 交互约定）" % method_name)
			return
	assert_eq(str(bag.get_interact_prompt()), PROMPT_KEY,
		"交互提示应返回 ui_strings 的 key（NFR-04）")
	assert_true(bag.can_interact(), "未拾取前应可交互")
	# 跑回复活后的空背包拾取：物品原数量回到背包（AC3）。
	bag.set_inventory(inventory)
	bag.interact(_fake_player())
	assert_eq(inventory.slots(), snapshot, "拾取后物品应原数量回到背包（AC3）")
	assert_false(bag.can_interact(), "拾取后不应再可交互")
	assert_true(bag.is_queued_for_deletion(), "拾取后掉落包应销毁")


func test_pickup_without_inventory_injected_keeps_bag() -> void:
	var bag_script: GDScript = _drop_bag_script()
	if bag_script == null:
		return
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var bag: Node = bag_script.spawn_at(world, DEATH_POSITION, [{"id": "o2", "count": 1}])
	if bag == null:
		return
	bag.interact(_fake_player())
	assert_false(bag.is_queued_for_deletion(), "未注入背包时不许吞掉掉落包（防御性）")
	assert_true(bag.can_interact(), "拾取失败后应仍可交互")


# 包B修复3：背包满时拾取掉落包，未装下的物品留在包里——不销毁、不置已拾取，
# 腾位后可再次拾取（参考 collectable.gd 背包满留原地的语义）。
func test_pickup_with_full_inventory_keeps_leftover_in_bag() -> void:
	var bag_script: GDScript = _drop_bag_script()
	if bag_script == null:
		return
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var inventory: RefCounted = InventoryScript.new()
	# 塞满 8 格 × 堆叠上限，c 已占一格且堆满（add_item 的 leftover 路径全覆盖）。
	for id: String in ["o2", "h2", "c", "s", "fe", "cu", "nacl", "h2o"]:
		inventory.add_item(id, inventory.stack_limit())
	var bag: Node = bag_script.spawn_at(world, DEATH_POSITION, [
		{"id": "c", "count": 5},
		{"id": "nacl", "count": 2},
	])
	if bag == null:
		return
	bag.set_inventory(inventory)
	bag.interact(_fake_player())
	assert_false(bag.is_queued_for_deletion(), "背包满时不许销毁掉落包")
	assert_true(bag.can_interact(), "未全放回时掉落包应仍可交互")
	assert_eq(inventory.count_of("c"), inventory.stack_limit(), "背包不应溢出堆叠上限")
	assert_eq(bag.items(), [{"id": "c", "count": 5}, {"id": "nacl", "count": 2}],
		"未装下的物品应原样留在掉落包内")
	# 腾出空间后再次拾取：全部回包，包才销毁。
	inventory.clear()
	bag.interact(_fake_player())
	assert_eq(inventory.count_of("c"), 5, "腾位后 c 应全部回包")
	assert_eq(inventory.count_of("nacl"), 2, "腾位后 nacl 应全部回包")
	assert_true(bag.is_queued_for_deletion(), "全部放回后掉落包才销毁")
	assert_false(bag.can_interact(), "全部放回后才置已拾取")


# 包B修复3：部分放回——装得下的先入包，剩余量写回掉落包（数量要更新，不是原样复制）。
func test_pickup_partial_leftover_writes_back_remaining() -> void:
	var bag_script: GDScript = _drop_bag_script()
	if bag_script == null:
		return
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var inventory: RefCounted = InventoryScript.new()
	# 7 格堆满，留 1 个空格：o2 占掉空格，c 堆满装不下剩 1 个。
	for id: String in ["h2", "c", "s", "fe", "cu", "nacl", "h2o"]:
		inventory.add_item(id, inventory.stack_limit())
	var bag: Node = bag_script.spawn_at(world, DEATH_POSITION, [
		{"id": "o2", "count": 5},
		{"id": "c", "count": 1},
	])
	if bag == null:
		return
	bag.set_inventory(inventory)
	bag.interact(_fake_player())
	assert_eq(inventory.count_of("o2"), 5, "装得下的部分应正常入包")
	assert_false(bag.is_queued_for_deletion(), "有剩余时不许销毁掉落包")
	assert_eq(bag.items(), [{"id": "c", "count": 1}], "剩余量应写回掉落包（仅剩 c×1）")


# ==== AC4：下一次死亡前掉落包不消失 ====

func test_drop_bag_persists_until_next_death_replaces_it() -> void:
	var bag_script: GDScript = _drop_bag_script()
	if bag_script == null:
		return
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var first: Node = bag_script.spawn_at(world, DEATH_POSITION, [{"id": "o2", "count": 1}])
	assert_not_null(first, "应能生成第一个掉落包")
	await wait_process_frames(5)
	assert_false(first.is_queued_for_deletion(), "掉落包不得自行消失（AC4）")
	assert_true(is_instance_valid(first), "掉落包不得自行消失（AC4）")
	# 下一次死亡生成新掉落包：旧的才被替换掉。
	var second: Node = bag_script.spawn_at(world, Vector2(200.0, 200.0), [{"id": "c", "count": 5}])
	assert_not_null(second, "应能生成第二个掉落包")
	await wait_process_frames(2)
	# 先判 is_instance_valid：旧包可能已被真正释放，直接调方法会崩。
	assert_true(not is_instance_valid(first) or first.is_queued_for_deletion(),
		"新掉落包生成时旧的才被移除（AC4）")
	assert_true(is_instance_valid(second) and not second.is_queued_for_deletion(),
		"新掉落包必须存活（AC4）")


# ==== NFR-04：逻辑代码零中文 ====

func test_scripts_have_no_hardcoded_chinese() -> void:
	for path in [DROP_BAG_SCRIPT_PATH, DEATH_SCREEN_SCRIPT_PATH]:
		if not ResourceLoader.exists(path):
			fail_test("尚未实现 %s" % path)
			continue
		var text: String = FileAccess.get_file_as_string(path)
		for line in text.split("\n"):
			var stripped: String = str(line).strip_edges()
			if stripped.begins_with("#"):
				continue
			# 日志文案（push_*/print）不向玩家展示，沿用既有 autoload 惯例允许中文。
			if stripped.contains("push_warning(") or stripped.contains("push_error(") \
					or stripped.contains("print("):
				continue
			assert_false(_has_cjk(stripped),
				"%s 逻辑代码不许硬编码中文（NFR-04）：%s" % [path, stripped])


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
