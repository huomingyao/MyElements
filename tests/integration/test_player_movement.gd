# IT-P01 / FR-P-01：玩家控制器——横版移动、跳跃、重力、朝向翻转、低能量减速。
# 断言：参数读自 balance.json（AC3）；能量归零速度 ×0.5（AC2）；落地不抖不穿墙（AC1）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const PLAYER_PATH: String = "res://scenes/player/player.tscn"
const FLOOR_Y: float = 100.0
const SETTLE_FRAMES: int = 30

var _player: CharacterBody2D = null
var _floor: StaticBody2D = null


func before_each() -> void:
	_player = null
	_floor = null
	if not ResourceLoader.exists(PLAYER_PATH):
		fail_test("尚未实现 %s（FR-P-01 / TP-04）" % PLAYER_PATH)
		return
	_floor = _make_floor()
	add_child_autofree(_floor)
	_player = (load(PLAYER_PATH) as PackedScene).instantiate()
	_player.position = Vector2(0.0, FLOOR_Y - 40.0)
	add_child_autofree(_player)


func after_each() -> void:
	for action in ["move_left", "move_right", "jump", "interact"]:
		Input.action_release(action)
	# GameManager 是共享 autoload，测完恢复满状态，别污染别的测试。
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm != null:
		gm.reset_stats()


# 平地一块 StaticBody2D：中心 FLOOR_Y，半高 10，顶面 FLOOR_Y-10。
func _make_floor() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = Vector2(0.0, FLOOR_Y)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2000.0, 20.0)
	shape.shape = rect
	body.add_child(shape)
	return body


# 落到地面站住后再测移动，排除下落过程干扰。
func _settle_on_floor() -> void:
	await wait_physics_frames(SETTLE_FRAMES)


func _balance_player() -> Dictionary:
	return Fixture.read_object("balance.json").get("player", {})


# AC3：移动/跳跃/重力/交互半径全部读自 data/balance.json，不是写死的。
func test_params_read_from_balance() -> void:
	if _player == null:
		return
	var table: Dictionary = _balance_player()
	assert_false(table.is_empty(), "balance.json 应有 player 段")
	for key in ["move_speed", "jump_velocity", "gravity", "interact_radius"]:
		assert_almost_eq(
			float(_player.get(key)), float(table.get(key, -1.0)), 0.001,
			"玩家参数 %s 应读自 balance.json" % key)


# AC1：按右 → velocity.x ≈ +move_speed，位置右移，朝向为右。
func test_move_right() -> void:
	if _player == null:
		return
	await _settle_on_floor()
	var start_x: float = _player.position.x
	Input.action_press("move_right")
	await wait_physics_frames(10)
	assert_almost_eq(_player.velocity.x, _player.move_speed, 1.0, "右移速度应等于 move_speed")
	assert_gt(_player.position.x, start_x, "位置应向右移动")
	assert_eq(_player.facing, 1, "朝右移动时 facing 应为 1")


# AC1：按左 → 速度取反、朝向翻转为左。
func test_move_left_flips_facing() -> void:
	if _player == null:
		return
	await _settle_on_floor()
	Input.action_press("move_left")
	await wait_physics_frames(10)
	assert_almost_eq(_player.velocity.x, -_player.move_speed, 1.0, "左移速度应等于 -move_speed")
	assert_eq(_player.facing, -1, "朝左移动时 facing 应翻转为 -1")


# AC1：松开按键后水平速度归零（不做惯性滑行，落地不晃）。
func test_stop_when_no_input() -> void:
	if _player == null:
		return
	await _settle_on_floor()
	Input.action_press("move_right")
	await wait_physics_frames(5)
	Input.action_release("move_right")
	await wait_physics_frames(3)
	assert_almost_eq(_player.velocity.x, 0.0, 0.001, "无输入时水平速度应为 0")


# AC1：重力把玩家拉到地面，落地后 y 不再下沉（不穿墙/不穿地）。
func test_gravity_and_landing() -> void:
	if _player == null:
		return
	assert_false(_player.is_on_floor(), "出生时悬空，不应着地")
	await _settle_on_floor()
	assert_true(_player.is_on_floor(), "落地后应着地")
	assert_almost_eq(_player.velocity.y, 0.0, 0.5, "落地后垂直速度应归零")
	# 连续多帧 y 基本不变 = 落地不抖。
	var ys: Array[float] = []
	for i in 6:
		await wait_physics_frames(1)
		ys.append(_player.position.y)
	for y in ys:
		assert_almost_eq(y, ys[0], 0.5, "落地后位置不应抖动")


# AC1：空格起跳——离地且先向上（y 减小），随后重力拉回地面。
func test_jump() -> void:
	if _player == null:
		return
	await _settle_on_floor()
	var ground_y: float = _player.position.y
	Input.action_press("jump")
	await wait_physics_frames(1)
	Input.action_release("jump")
	await wait_physics_frames(3)
	assert_lt(_player.position.y, ground_y - 1.0, "起跳后应离开地面向上")
	await wait_physics_frames(SETTLE_FRAMES * 2)
	assert_true(_player.is_on_floor(), "跳跃后应落回地面")


# AC2：能量归零时移动速度为正常值 × balance.low_energy_speed_multiplier（0.5）。
func test_low_energy_halves_speed() -> void:
	if _player == null:
		return
	var gm: Node = get_node_or_null(^"/root/GameManager")
	assert_not_null(gm, "需要 GameManager autoload")
	if gm == null:
		return
	var bal: Dictionary = Fixture.read_object("balance.json")
	var multiplier: float = float(bal.get("stats", {}).get("low_energy_speed_multiplier", 0.5))
	await _settle_on_floor()
	gm.modify_energy(-gm.energy_max * 2.0)
	assert_almost_eq(gm.energy, 0.0, 0.001, "前置：能量应已归零")
	Input.action_press("move_right")
	await wait_physics_frames(10)
	assert_almost_eq(
		_player.velocity.x, _player.move_speed * multiplier, 1.0,
		"能量归零时速度应为 move_speed × %s" % multiplier)
