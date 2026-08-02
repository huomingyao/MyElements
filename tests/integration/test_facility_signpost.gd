# FR-U-03 AC1 / A4：营地路牌（facility_signpost）实现 SPEC-03 §5 交互三方法，
# interact() 调 WorldMap.open() 打开世界地图页；实例摆在 world.tscn 营地区域。
extends GutTest

const SIGNPOST_SCENE: String = "res://scenes/main/facility_signpost.tscn"
const WORLD_SCENE: String = "res://scenes/main/world.tscn"

var world_map: Node = null


func before_each() -> void:
	world_map = Engine.get_main_loop().root.get_node_or_null(^"WorldMap")
	assert_not_null(world_map, "WorldMap autoload 必须存在")
	if world_map != null and bool(world_map.is_open()):
		world_map.close()


func after_each() -> void:
	if world_map != null and bool(world_map.is_open()):
		world_map.close()


# SPEC-03 §5 三方法契约：提示 id / 可交互 / interact 打开地图页。
func test_signpost_opens_world_map_on_interact() -> void:
	if not ResourceLoader.exists(SIGNPOST_SCENE):
		fail_test("尚未实现 %s（A4 营地路牌）" % SIGNPOST_SCENE)
		return
	var signpost: Node = (load(SIGNPOST_SCENE) as PackedScene).instantiate()
	add_child_autofree(signpost)
	await wait_process_frames(1)
	for method_name: String in ["get_interact_prompt", "can_interact", "interact"]:
		assert_true(signpost.has_method(method_name), "路牌应有 %s()（SPEC-03 §5）" % method_name)
	assert_true(bool(signpost.can_interact()), "路牌应总是可交互")
	assert_false(str(signpost.get_interact_prompt()).is_empty(), "路牌应返回交互提示 id")
	assert_false(world_map.is_open(), "交互前地图页应关闭")
	signpost.interact(null)
	assert_true(world_map.is_open(), "interact() 应打开世界地图页（WorldMap.open）")


# 世界总装：路牌实例摆在 world.tscn 的 Facilities 下（营地区域），交互同样开图。
func test_signpost_instanced_in_world_camp() -> void:
	if not ResourceLoader.exists(WORLD_SCENE):
		fail_test("尚未实现 %s" % WORLD_SCENE)
		return
	var world: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(world) # 世界不进 autofree：跨测试复用 autoload 状态需要显式清理
	await wait_process_frames(3)
	var signpost: Node = world.get_node_or_null(^"Facilities/FacilitySignpost")
	assert_not_null(signpost, "world.tscn 营地应有 FacilitySignpost 实例")
	if signpost != null:
		var camp_center_x: float = 1000.0
		assert_almost_eq((signpost as Node2D).global_position.x, camp_center_x, 450.0,
			"路牌应位于营地区域（营地中心附近）")
		signpost.interact(world.get_node_or_null(^"Player"))
		assert_true(world_map.is_open(), "世界内路牌交互应打开世界地图页")
	remove_child(world)
	world.queue_free()
