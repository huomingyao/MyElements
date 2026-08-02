# IT-G01 / FR-G-01：采集物——只配 substance_id，名称/图标/字幕全走数据表；
# 拾取入包 + 消失 + 首次 bubble 字幕；未知 id 不崩溃；图标缺失走占位不空白。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const COLLECTABLE_SCENE: String = "res://scenes/gameplay/collectable.tscn"
const COLLECTABLE_SCRIPT: String = "res://scenes/gameplay/collectable.gd"
const INVENTORY_SCRIPT: String = "res://scripts/gameplay/inventory.gd"

var gm: Node = null
var tip: Node = null
var recipe_db: Node = null


# 假玩家：只携带一个 inventory（同 test_facility_camp.gd 的约定）。
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
	tip.reload()
	recipe_db.reload()


func _make_player() -> FakePlayer:
	var player := FakePlayer.new()
	player.inventory = (load(INVENTORY_SCRIPT) as GDScript).new()
	add_child_autofree(player)
	return player


func _spawn(substance_id: String) -> Node:
	if not ResourceLoader.exists(COLLECTABLE_SCENE):
		fail_test("尚未实现 %s（FR-G-01 / TP-06 补）" % COLLECTABLE_SCENE)
		return null
	var node: Node = (load(COLLECTABLE_SCENE) as PackedScene).instantiate()
	add_child_autofree(node)
	if not node.has_method("setup"):
		fail_test("采集物应有 setup(substance_id)（FR-G-01 AC1）")
		return null
	node.setup(substance_id)
	await wait_process_frames(1)
	return node


# AC1：采集物节点只配置 substance_id，名称/化学式/字幕 id 全部来自数据表。
func test_record_comes_from_data_table() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	if not node.has_method("record"):
		fail_test("采集物应有 record()（FR-G-01 AC1：字段从数据表读取的可观测口）")
		return
	var record: Dictionary = node.record()
	var substance: Dictionary = recipe_db.get_substance("o2")
	assert_false(substance.is_empty(), "substances.json 应有 o2")
	assert_eq(str(record.get("name", "")), str(substance.get("name", "")), "名称必须来自数据表")
	assert_eq(str(record.get("formula", "")), str(substance.get("formula", "")), "化学式必须来自数据表")
	assert_eq(str(record.get("tip_id", "")), str(substance.get("tip_id", "")), "字幕 id 必须来自数据表")


# AC1 延伸：道具表条目（如木棒 stick）也可作采集物，名称同样来自数据表。
func test_item_table_id_also_resolves() -> void:
	var node: Node = await _spawn("stick")
	if node == null:
		return
	var record: Dictionary = node.record()
	assert_eq(str(record.get("name", "")), "木棒", "道具条目的名称必须来自 items.json")


# SPEC-03 §5：实现三方法约定，玩家控制器无需认识本类型。
func test_implements_interact_contract() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	assert_true(node.has_method("get_interact_prompt"), "缺 get_interact_prompt")
	assert_true(node.has_method("can_interact"), "缺 can_interact")
	assert_true(node.has_method("interact"), "缺 interact")
	assert_false(str(node.get_interact_prompt()).is_empty(), "提示 id 不应为空")
	assert_true(bool(node.can_interact()), "未拾取时应可交互")


# A1（D4 / SPEC-02 §5）：白盒地图营地试剂架区域应有 carbon_mask 采集物标记，
# 与试剂三物（hcl/naoh/caoh2）标记同处 CollectableSpawns 下。
func test_whitebox_map_has_carbon_mask_spawn_marker() -> void:
	const MAP_PATH: String = "res://maps/whitebox_map.tscn"
	if not ResourceLoader.exists(MAP_PATH):
		fail_test("缺少白盒地图 %s" % MAP_PATH)
		return
	var map: Node = (load(MAP_PATH) as PackedScene).instantiate()
	add_child_autofree(map)
	var spawns: Node = map.get_node_or_null(^"CollectableSpawns")
	assert_not_null(spawns, "白盒地图应有 CollectableSpawns 标记容器")
	if spawns == null:
		return
	var found: bool = false
	for marker: Node in spawns.get_children():
		if str(marker.get_meta("substance_id", "")) == "carbon_mask":
			found = true
			break
	assert_true(found, "营地试剂架应有 carbon_mask 采集物标记（D4 / SPEC-02 §5）")


# B2 / FR-G-01 AC2：拾取音效挂载点存在；无 stream 时静默跳过不报错（同 explosion 的做法）。
func test_pickup_sound_player_mounted_and_silent_without_stream() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	var audio: Node = node.get_node_or_null(^"%PickupPlayer")
	assert_not_null(audio, "采集物应有 %PickupPlayer 拾取音效挂载点（FR-G-01 AC2）")
	if audio == null:
		return
	assert_true(audio is AudioStreamPlayer, "挂载点应为 AudioStreamPlayer")
	var player_node: AudioStreamPlayer = audio as AudioStreamPlayer
	assert_null(player_node.stream, "P5 音频未交付前 stream 应为空")
	var player: FakePlayer = _make_player()
	node.interact(player) # 无 stream：静默跳过，不报错
	assert_false(player_node.playing, "无 stream 时不应播放")


# B2：有 stream 时拾取播放（用程序生成的静音 WAV 注入，不依赖 P5 音频资产）。
func test_pickup_plays_sound_when_stream_assigned() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	var player_node: AudioStreamPlayer = node.get_node_or_null(^"%PickupPlayer") as AudioStreamPlayer
	if player_node == null:
		fail_test("采集物应有 %PickupPlayer 拾取音效挂载点（FR-G-01 AC2）")
		return
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	wav.data = PackedByteArray([128, 128, 128, 128])
	player_node.stream = wav
	var player: FakePlayer = _make_player()
	node.interact(player)
	assert_true(player_node.playing, "有 stream 时拾取应播放音效")


# 包A-9：有音效在播时拾取不得立即 queue_free（会掐断音频），应等播放结束再销毁。
func test_pickup_with_stream_delays_free_until_sound_finished() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	var player_node: AudioStreamPlayer = node.get_node_or_null(^"%PickupPlayer") as AudioStreamPlayer
	if player_node == null:
		fail_test("采集物应有 %PickupPlayer 拾取音效挂载点")
		return
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	wav.data = PackedByteArray([128, 128, 128, 128])
	player_node.stream = wav
	var player: FakePlayer = _make_player()
	node.interact(player)
	assert_true(player_node.playing, "有 stream 时拾取应播放音效")
	assert_false(node.is_queued_for_deletion(), "播放中不应立即销毁（立即 free 会掐断音频）")
	assert_false(node.visible, "等待销毁期间应隐藏本体")
	assert_true(player_node.finished.is_connected(Callable(node, "queue_free")),
		"应接好播放结束后再销毁")


# AC2：拾取后物品进背包、采集物消失；并发出 collected 信号（世界接线首次统计用）。
func test_pickup_adds_to_inventory_and_frees() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	var player: FakePlayer = _make_player()
	var picked: Array = []
	if node.has_signal("collected"):
		node.collected.connect(func(id_value: String) -> void: picked.append(id_value))
	node.interact(player)
	assert_eq(player.inventory.count_of("o2"), 1, "拾取后背包应有 1 份 o2")
	assert_true(node.is_queued_for_deletion(), "拾取后采集物应消失")
	assert_eq(picked, ["o2"], "拾取应发出 collected(substance_id) 信号")


# AC3：首次获得弹出 bubble 字幕（内容 = 数据表 tip_id，once 去重由字幕引擎保证）。
func test_first_pickup_shows_bubble_tip() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	var player: FakePlayer = _make_player()
	node.interact(player)
	assert_true(tip.is_shown("tip_o2"), "首次拾取 o2 应触发 tip_o2 字幕")
	assert_true(tip.queue_size() > 0 or tip.current_text() != "", "字幕应进入播放")


# AC2 边界：背包满时不拾取、不消失、不静默丢弃（配合 FR-G-02 AC2）。
func test_pickup_blocked_when_inventory_full() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	var player: FakePlayer = _make_player()
	# 8 格 × 99 全部塞满其它物质。
	for i: int in range(player.inventory.slot_count()):
		player.inventory.add_item("c", player.inventory.stack_limit())
	var before: int = player.inventory.count_of("o2")
	node.interact(player)
	assert_eq(player.inventory.count_of("o2"), before, "背包满时不应装入")
	assert_false(node.is_queued_for_deletion(), "背包满时采集物应留在原地")
	assert_true(bool(node.can_interact()), "背包满时仍可交互（之后再捡）")


# AC2 反馈补强（2026-08-03，SPEC-05 §3.2 sys_inventory_full）：背包满拾取失败
# 要给玩家看得见的提示，不许静默无反应；满格但同物质可堆叠时不得误报。
func test_full_inventory_pickup_shows_warning_tip() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	var player: FakePlayer = _make_player()
	for i: int in range(player.inventory.slot_count()):
		player.inventory.add_item("c", player.inventory.stack_limit())
	node.interact(player)
	assert_true(tip.is_shown("sys_inventory_full"), "背包满拾取失败应触发 sys_inventory_full 字幕")


# 堆叠感知：8 格占满但 o2 已在包内且堆叠有空间时，拾取照常成功、不误报满。
func test_full_slots_but_stackable_pickup_succeeds() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	var player: FakePlayer = _make_player()
	var ids: Array[String] = ["o2", "h2", "c", "s", "co", "h2o", "caco3", "fe"]
	for id: String in ids:
		player.inventory.add_item(id, 1)
	node.interact(player)
	assert_eq(player.inventory.count_of("o2"), 2, "同物质堆叠有空间时应拾取成功")
	assert_true(node.is_queued_for_deletion(), "拾取成功后采集物应消失")
	assert_false(tip.is_shown("sys_inventory_full"), "可堆叠时不应误报背包满")


# AC4：数据表中不存在的 id 不崩溃，输出警告且不可交互。
func test_unknown_id_does_not_crash() -> void:
	var node: Node = await _spawn("no_such_substance")
	if node == null:
		return
	assert_false(bool(node.can_interact()), "未知 id 不应可交互")
	var player: FakePlayer = _make_player()
	node.interact(player)
	assert_eq(player.inventory.count_of("no_such_substance"), 0, "未知 id 不应入包")
	assert_false(node.is_queued_for_deletion(), "未知 id 不应被拾取销毁")


# AC2/AC3 补充：拾取后不可再次交互（防双捡）。
func test_picked_collectable_cannot_interact_again() -> void:
	var node: Node = await _spawn("c")
	if node == null:
		return
	var player: FakePlayer = _make_player()
	node.interact(player)
	assert_false(bool(node.can_interact()), "已拾取后 can_interact 应为 false")


# 模块化重构（视觉逻辑分离）：视觉/音频拆成独立命名容器，
# 各可见部件是 Visuals 下的独立节点，可针对单个部件修改。
func test_modular_node_structure() -> void:
	var node: Node = await _spawn("o2")
	if node == null:
		return
	var visuals: Node = node.get_node_or_null(^"%Visuals")
	assert_not_null(visuals, "采集物应有 %Visuals 视觉容器（模块化重构）")
	if visuals == null:
		return
	assert_true(visuals is Node2D, "视觉容器应为 Node2D")
	var glow: Node = node.get_node_or_null(^"%Glow")
	assert_not_null(glow, "应有 %Glow 发光部件")
	if glow != null:
		assert_true(glow is Polygon2D, "发光部件应为 Polygon2D")
		assert_eq(glow.get_parent(), visuals, "%Glow 应挂在 %Visuals 容器下")
	var icon: Node = node.get_node_or_null(^"%IconSprite")
	assert_not_null(icon, "应有 %IconSprite 图标部件")
	if icon != null:
		assert_eq(icon.get_parent(), visuals, "%IconSprite 应挂在 %Visuals 容器下")
	var audio: Node = node.get_node_or_null(^"%Audio")
	assert_not_null(audio, "应有 %Audio 音频容器")
	if audio == null:
		return
	var pickup: Node = node.get_node_or_null(^"%PickupPlayer")
	assert_not_null(pickup, "应有 %PickupPlayer 音效节点")
	if pickup != null:
		assert_eq(pickup.get_parent(), audio, "%PickupPlayer 应挂在 %Audio 容器下")


# NFR-04：逻辑代码里不许出现中文字面量（注释除外）。
func test_script_has_no_hardcoded_chinese() -> void:
	if not FileAccess.file_exists(COLLECTABLE_SCRIPT):
		fail_test("尚未实现 %s（FR-G-01）" % COLLECTABLE_SCRIPT)
		return
	var text: String = FileAccess.get_file_as_string(COLLECTABLE_SCRIPT)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		# NFR-04 判定口径（SPEC-01 §10）：push_*/print 诊断日志不受管制。
		if stripped.contains("push_warning") or stripped.contains("push_error") or stripped.contains("print("):
			continue
		assert_false(_has_cjk(stripped), "逻辑代码里不许硬编码中文（NFR-04）：%s" % stripped)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
