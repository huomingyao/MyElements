# 黑洞（区域过渡）：玩家从一侧进入→黑屏→传送到对侧落点并发 traveled 信号；
# 冷却期内不重复触发；2026-08-03 起为纯隐形边缘触发器（黑核/紫环视觉已按用户要求移除）。
extends GutTest

const HOLE_SCENE: String = "res://scenes/gameplay/black_hole.tscn"
const HOLE_POS: Vector2 = Vector2(-700, 0)
const WEST_TARGET: Vector2 = Vector2(-770, 0)
const EAST_TARGET: Vector2 = Vector2(-630, 0)

var _hole: Area2D = null
var _body: CharacterBody2D = null
var _travels: Array = []


func before_each() -> void:
	_travels = []
	if not ResourceLoader.exists(HOLE_SCENE):
		fail_test("尚未实现 %s" % HOLE_SCENE)
		return
	_hole = (load(HOLE_SCENE) as PackedScene).instantiate()
	_hole.west_target = WEST_TARGET
	_hole.east_target = EAST_TARGET
	_hole.west_zone = "saltlake"
	_hole.east_zone = "grassland"
	add_child_autofree(_hole)
	_hole.global_position = HOLE_POS
	_body = CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	_body.add_child(shape)
	add_child_autofree(_body)
	_body.global_position = Vector2(-660, -80)
	await wait_physics_frames(2)


func _on_traveled(from_zone: String, to_zone: String) -> void:
	_travels.append([from_zone, to_zone])


# 东侧（grassland）进入 → 传到西侧（saltlake）落点，发 traveled。
func test_entering_from_east_teleports_to_west_target() -> void:
	if _hole == null:
		return
	_hole.traveled.connect(_on_traveled)
	_body.global_position = Vector2(-700, -80)
	await wait_seconds(0.9)
	assert_eq(_body.global_position, WEST_TARGET, "东侧进入应传送到西侧落点")
	assert_eq(_travels, [["grassland", "saltlake"]] as Array, "应发一次 traveled(grassland→saltlake)")


# 西侧进入 → 传到东侧落点。
func test_entering_from_west_teleports_to_east_target() -> void:
	if _hole == null:
		return
	_body.global_position = Vector2(-740, -80)
	await wait_physics_frames(2)
	_body.global_position = Vector2(-701, -80)
	await wait_seconds(0.9)
	assert_eq(_body.global_position, EAST_TARGET, "西侧进入应传送到东侧落点")


# 冷却期内（传送刚结束）再次触碰不重复传送。
func test_cooldown_prevents_immediate_retrigger() -> void:
	if _hole == null:
		return
	_hole.traveled.connect(_on_traveled)
	_body.global_position = Vector2(-700, -80)
	await wait_seconds(0.9)
	assert_eq(_travels.size(), 1, "首次触碰应传送一次")
	_body.global_position = Vector2(-700, -80)
	await wait_seconds(0.3)
	assert_eq(_travels.size(), 1, "冷却期内不应重复传送")
	assert_eq(_body.global_position, Vector2(-700, -80), "冷却期内身体不被移动")


# 隐形触发器（2026-08-03 用户拍板）：黑核/紫环视觉移除，只剩碰撞体，过场全靠黑屏。
func test_has_no_visuals() -> void:
	if _hole == null:
		return
	assert_null(_hole.get_node_or_null("Core"), "不应再有黑核 Core")
	assert_null(_hole.get_node_or_null("Ring"), "不应再有紫环 Ring")
	assert_eq(_hole.get_child_count(), 1, "应只剩 Shape 碰撞体一个子节点")


# ==== FR-C-10 AC3（2026-08-03）：过场开始信号 + 传送瞬间相机 snap ====

# travel_started 必须先于 traveled 发出（世界据此在过场期间锁输入）。
func test_travel_started_precedes_traveled() -> void:
	if _hole == null:
		return
	var order: Array[String] = []
	_hole.travel_started.connect(func() -> void: order.append("started"))
	_hole.traveled.connect(func(_from: String, _to: String) -> void: order.append("traveled"))
	_body.global_position = Vector2(-700, -80)
	await wait_seconds(0.9)
	assert_eq(order, ["started", "traveled"] as Array[String],
		"travel_started 应先于 traveled 各发一次")


# 传送落位瞬间：若身体有 reset_camera_smoothing（玩家相机平滑收敛）即调用，
# 否则渐亮期间相机会从旧位置慢追横跨虚空（FR-C-10 AC3 无跨区拖影）。
func test_teleport_snaps_camera_smoothing() -> void:
	if _hole == null:
		return
	var script := GDScript.new()
	script.source_code = "extends CharacterBody2D\nvar snapped: bool = false\nfunc reset_camera_smoothing() -> void:\n\tsnapped = true\n"
	script.reload()
	var body: CharacterBody2D = script.new() as CharacterBody2D
	assert_not_null(body, "桩身体应实例化")
	if body == null:
		return
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = Vector2(-740, -80)
	await wait_physics_frames(2)
	body.global_position = Vector2(-701, -80)
	await wait_seconds(0.9)
	assert_eq(body.global_position, EAST_TARGET, "桩身体应被传送到东侧落点（前置）")
	assert_true(bool(body.get("snapped")), "传送瞬间应调用 reset_camera_smoothing")
