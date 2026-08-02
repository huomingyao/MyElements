# IT-P03 / FR-P-03：相机跟随与边界 + 火把照明半径。
# 断言：set_map_bounds 写入相机 limit，相机不越界（AC1）；
# 硫火把把可视半径从 dark_view_radius 切到 torch_view_radius（AC2，数值可断言）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const PLAYER_PATH: String = "res://scenes/player/player.tscn"
const MAP_BOUNDS: Rect2 = Rect2(-200.0, -100.0, 400.0, 300.0)

var _player: CharacterBody2D = null


func before_each() -> void:
	_player = null
	if not ResourceLoader.exists(PLAYER_PATH):
		fail_test("尚未实现 %s（FR-P-03 / TP-04）" % PLAYER_PATH)
		return
	_player = (load(PLAYER_PATH) as PackedScene).instantiate()
	_player.position = Vector2.ZERO
	add_child_autofree(_player)
	await wait_physics_frames(2)


func after_each() -> void:
	# GameManager 是共享 autoload，昼夜/区域状态测完复位。
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm != null:
		gm.reset_clock()
		gm.reset_stats()
		gm.set_zone("grassland")


func _camera() -> Camera2D:
	var cam: Node = _player.get_node_or_null(^"%Camera")
	assert_not_null(cam, "玩家应有唯一名节点 %Camera（SPEC-03 §5.1）")
	return cam as Camera2D


func _light() -> PointLight2D:
	var light: Node = _player.get_node_or_null(^"%ViewLight")
	assert_not_null(light, "玩家应有唯一名节点 %ViewLight（SPEC-03 §5.1）")
	return light as PointLight2D


func _balance_daynight() -> Dictionary:
	return Fixture.read_object("balance.json").get("daynight", {})


# AC1：相机跟随玩家（落地静止后收敛到玩家位置）。
func test_camera_follows_player() -> void:
	if _player == null:
		return
	var cam: Camera2D = _camera()
	if cam == null:
		return
	# 给一块地面让玩家站住，排除自由落体时平滑滞后的合理现象。
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(0.0, 120.0)
	var floor_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2000.0, 20.0)
	floor_shape.shape = rect
	floor_body.add_child(floor_shape)
	add_child_autofree(floor_body)
	_player.position = Vector2(50.0, 80.0)
	await wait_physics_frames(120)
	assert_almost_eq(
		cam.get_screen_center_position().x, _player.global_position.x, 2.0,
		"相机应跟随玩家水平位置")
	assert_almost_eq(
		cam.get_screen_center_position().y, _player.global_position.y, 2.0,
		"相机应跟随玩家垂直位置")


# AC1：set_map_bounds 把地图边界写进 Camera2D 的四条 limit。
func test_map_bounds_applied_to_camera_limits() -> void:
	if _player == null:
		return
	var cam: Camera2D = _camera()
	if cam == null:
		return
	_player.set_map_bounds(MAP_BOUNDS)
	assert_eq(cam.limit_left, int(MAP_BOUNDS.position.x), "limit_left 应等于地图左边界")
	assert_eq(cam.limit_top, int(MAP_BOUNDS.position.y), "limit_top 应等于地图上边界")
	assert_eq(cam.limit_right, int(MAP_BOUNDS.end.x), "limit_right 应等于地图右边界")
	assert_eq(cam.limit_bottom, int(MAP_BOUNDS.end.y), "limit_bottom 应等于地图下边界")


# AC1：玩家跑出地图右下，相机被 limit 卡住不越界。
func test_camera_never_leaves_bounds() -> void:
	if _player == null:
		return
	var cam: Camera2D = _camera()
	if cam == null:
		return
	_player.set_map_bounds(MAP_BOUNDS)
	_player.position = Vector2(MAP_BOUNDS.end.x + 500.0, MAP_BOUNDS.end.y + 500.0)
	await wait_physics_frames(60)
	var center: Vector2 = cam.get_screen_center_position()
	assert_true(center.x <= MAP_BOUNDS.end.x, "相机不得越出地图右边界")
	assert_true(center.y <= MAP_BOUNDS.end.y, "相机不得越出地图下边界")


# AC2：未持火把时可视半径 = balance.dark_view_radius。
func test_dark_view_radius_without_torch() -> void:
	if _player == null:
		return
	_player.set_torch_equipped(false)
	var expected: float = float(_balance_daynight().get("dark_view_radius", -1.0))
	assert_gt(expected, 0.0, "balance.json 应有 daynight.dark_view_radius")
	assert_almost_eq(_player.view_radius(), expected, 0.001, "无火把半径应等于 dark_view_radius")


# AC2：装备硫火把后可视半径 = balance.torch_view_radius，且明显大于无火把。
func test_torch_expands_view_radius() -> void:
	if _player == null:
		return
	var dark: float = float(_balance_daynight().get("dark_view_radius", -1.0))
	var torch: float = float(_balance_daynight().get("torch_view_radius", -1.0))
	assert_gt(torch, dark, "torch_view_radius 应大于 dark_view_radius")
	_player.set_torch_equipped(true)
	assert_almost_eq(_player.view_radius(), torch, 0.001, "持火把半径应等于 torch_view_radius")
	assert_true(_player.is_torch_equipped(), "is_torch_equipped 应反映装备状态")


# AC2 配套：照明只在黑暗环境（夜晚或矿洞）开启，白天草原不点灯。
func test_light_only_in_darkness() -> void:
	if _player == null:
		return
	var gm: Node = get_node_or_null(^"/root/GameManager")
	assert_not_null(gm, "需要 GameManager autoload")
	var light: PointLight2D = _light()
	if gm == null or light == null:
		return
	var day_length: float = float(_balance_daynight().get("day_duration", 360.0))
	# 白天草原：灯灭。
	await wait_physics_frames(3)
	assert_false(light.enabled, "白天草原不应开灯")
	# 推进到夜晚：灯亮。
	gm.tick(day_length + 1.0)
	await wait_physics_frames(3)
	assert_true(light.enabled, "夜晚应开灯")
	# 回到白天但进矿洞：矿洞黑暗，灯也亮。
	gm.reset_clock()
	gm.set_zone("mine")
	await wait_physics_frames(3)
	assert_true(light.enabled, "矿洞内即使白天也应开灯")


# ==== 包A-4/包A-8：相机传送收敛与震动 ====

# 包A-4：提供传送后的平滑收敛封装（内部走 reset_smoothing）。
func test_camera_has_snap_to_target() -> void:
	if _player == null:
		return
	var cam: Camera2D = _camera()
	if cam == null:
		return
	assert_true(cam.has_method("snap_to_target"), "相机应提供 snap_to_target()（传送后收敛平滑）")
	cam.snap_to_target() # 调用不报错即可


# 包A-8：shake(intensity, duration) 震动中 offset 非零且不超强度，结束精确复位；
# 连续两次震动（新震动打断旧震动）后仍能复位。
func test_shake_offsets_and_recovers() -> void:
	if _player == null:
		return
	var cam: Camera2D = _camera()
	if cam == null:
		return
	assert_true(cam.has_method("shake"), "相机应提供 shake(intensity, duration)")
	if not cam.has_method("shake"):
		return
	cam.shake(3.0, 0.2)
	await wait_process_frames(2)
	var offset_len: float = cam.offset.length()
	assert_gt(offset_len, 0.1, "震动中 offset 应非零")
	assert_true(offset_len <= 3.01, "震动幅度不应超过 intensity：%s" % offset_len)
	await wait_seconds(0.4)
	assert_eq(cam.offset, Vector2.ZERO, "震动结束后 offset 应精确复位")
	cam.shake(2.0, 0.1)
	await wait_process_frames(1)
	cam.shake(2.0, 0.1) # 新震动打断旧震动
	await wait_seconds(0.3)
	assert_eq(cam.offset, Vector2.ZERO, "连续震动后 offset 仍应复位")
