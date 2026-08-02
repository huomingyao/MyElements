# IT-M01 / FR-M-01：导师学院场景。
# 断言：四个房间各有一位导师且房间与 mentors.json 的 room 字段一致（AC1）；
# 学院区域氧气净速率为 0、场景内无怪物节点（AC2）；走近出现「按 E 提问」气泡（AC3）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const ACADEMY_PATH: String = "res://scenes/mentor/academy.tscn"
const PLAYER_PATH: String = "res://scenes/player/player.tscn"
const NPC_SCRIPT_PATH: String = "res://scenes/mentor/mentor_npc.gd"

const EXPECTED_MENTOR_COUNT: int = 4

var _academy: Node = null
var _rows: Array = []


func before_each() -> void:
	_academy = null
	_rows = Fixture.rows_of("mentors.json")
	if not ResourceLoader.exists(ACADEMY_PATH):
		fail_test("尚未实现 %s（FR-M-01 / TP-13）" % ACADEMY_PATH)
		return
	_academy = (load(ACADEMY_PATH) as PackedScene).instantiate()
	add_child_autofree(_academy)
	await wait_physics_frames(2)


func after_each() -> void:
	# 区域状态是 autoload 全局态，测完还原，避免污染其他测试。
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm != null:
		gm.set_zone("grassland")


# 收集学院里全部导师小人：Area2D 且带 mentor_id 属性与交互三方法。
func _mentor_npcs() -> Array:
	var out: Array = []
	if _academy != null:
		_collect_npcs(_academy, out)
	return out


func _collect_npcs(node: Node, out: Array) -> void:
	if node.get("mentor_id") != null and node.has_method("get_interact_prompt"):
		out.append(node)
	for child in node.get_children():
		_collect_npcs(child, out)


# AC1：四个房间各有一位导师，且所处房间的元数据与 mentors.json 的 room 字段一致。
func test_each_mentor_stands_in_room_matching_data() -> void:
	if _academy == null:
		return
	assert_eq(_rows.size(), EXPECTED_MENTOR_COUNT, "mentors.json 应有 4 位导师（FR-D-04）")
	var by_id: Dictionary = {}
	for npc_value in _mentor_npcs():
		var npc: Node = npc_value
		by_id[str(npc.mentor_id)] = npc
	for row_value in _rows:
		var row: Dictionary = row_value
		var id: String = str(row.get("id", ""))
		assert_true(by_id.has(id), "学院中应有导师小人：%s" % id)
		if not by_id.has(id):
			continue
		var npc: Node = by_id[id]
		var room_node: Node = npc.get_parent()
		assert_not_null(room_node, "导师小人应挂在房间节点下")
		if room_node == null:
			continue
		assert_true(
			room_node.has_meta("room"),
			"房间节点 %s 应有 room 元数据" % room_node.name
		)
		if room_node.has_meta("room"):
			assert_eq(
				str(room_node.get_meta("room")), str(row.get("room", "")),
				"导师 %s 应站在「%s」" % [id, str(row.get("room", ""))]
			)


# AC1：导师小人的数量与数据表一致，不多不少。
func test_exactly_four_mentor_npcs() -> void:
	if _academy == null:
		return
	assert_eq(
		_mentor_npcs().size(), EXPECTED_MENTOR_COUNT,
		"学院应恰好有 4 位导师小人（数据驱动）"
	)


# AC2：进入学院触发区后区域切到 academy，氧气净速率为 0（不消耗也不回复）。
func test_academy_zone_has_zero_oxygen_net_rate() -> void:
	if _academy == null:
		return
	var gm: Node = get_node_or_null(^"/root/GameManager")
	assert_not_null(gm, "GameManager autoload 应存在")
	if gm == null:
		return
	var trigger: Node = _academy.get_node_or_null(^"%ZoneTrigger")
	assert_not_null(trigger, "学院应有 %%ZoneTrigger 区域触发器")
	if trigger == null:
		return
	var body: CharacterBody2D = CharacterBody2D.new()
	add_child_autofree(body)
	trigger.body_entered.emit(body)
	assert_eq(gm.current_zone(), "academy", "进入学院后区域应为 academy")
	assert_almost_eq(
		float(gm.oxygen_net_rate()), 0.0, 0.001,
		"学院内氧气净速率应为 0（FR-M-01 AC2）"
	)


# AC2：怪物不进入学院——场景树内不许出现怪物脚本的节点。
func test_no_monster_nodes_inside_academy() -> void:
	if _academy == null:
		return
	var hits: Array = []
	_scan_monsters(_academy, hits)
	assert_eq(hits, [], "学院内不许有怪物节点：%s" % str(hits))


func _scan_monsters(node: Node, hits: Array) -> void:
	var script: Variant = node.get_script()
	if script is Script and str((script as Script).resource_path).contains("monster"):
		hits.append(str(node.name))
	for child in node.get_children():
		_scan_monsters(child, hits)


# AC3：导师实现 SPEC-03 §5 三方法，提示 id 指向 ui_strings.prompt_ask（「按 E 提问」）。
func test_mentor_implements_interact_contract_with_ask_prompt() -> void:
	if _academy == null:
		return
	var ui: Dictionary = Fixture.read_object("ui_strings.json")
	assert_true(ui.has("prompt_ask"), "ui_strings.json 应有 prompt_ask")
	for npc_value in _mentor_npcs():
		var npc: Node = npc_value
		assert_eq(
			npc.get_interact_prompt(), "prompt_ask",
			"导师提示气泡应使用 ui_strings.prompt_ask（NFR-04）"
		)
		assert_true(npc.can_interact(), "导师应可交互")
		assert_true(npc.has_method("interact"), "导师应实现 interact()（SPEC-03 §5）")


# AC3：玩家走近导师 → 头顶出现「按 E 提问」；走开 → 消失（走 SPEC-03 §5 约定，不改玩家代码）。
func test_prompt_bubble_shows_near_mentor_and_hides_away() -> void:
	if _academy == null:
		return
	if not ResourceLoader.exists(PLAYER_PATH):
		fail_test("缺少 %s（TP-04 应先完成）" % PLAYER_PATH)
		return
	var npcs: Array = _mentor_npcs()
	if npcs.is_empty():
		fail_test("学院中没有导师小人")
		return
	var npc: Node = npcs[0]
	var player: CharacterBody2D = (load(PLAYER_PATH) as PackedScene).instantiate()
	add_child_autofree(player)
	player.global_position = npc.global_position
	await wait_physics_frames(3)
	var bubble: Label = player.get_node_or_null(^"%PromptBubble")
	assert_not_null(bubble, "玩家应有 %%PromptBubble（SPEC-03 §5.1）")
	if bubble == null:
		return
	assert_true(bubble.visible, "走近导师应显示提问气泡")
	var expected: String = str(Fixture.read_object("ui_strings.json").get("prompt_ask", ""))
	assert_eq(bubble.text, expected, "气泡文案应来自 ui_strings.prompt_ask")
	player.global_position = npc.global_position + Vector2(400.0, 0.0)
	await wait_physics_frames(3)
	assert_false(bubble.visible, "走开后气泡应消失")
