# IT-C01 / FR-C-01：视口 640×360、七个输入动作、主场景可加载且零 ERROR。
extends GutTest

const REQUIRED_ACTIONS: Array[String] = [
	"move_left", "move_right", "jump", "interact", "inventory", "worldmap", "pause",
]


# AC1：视口 640×360，stretch_mode=canvas_items，stretch_aspect=keep。
func test_viewport_is_640x360_with_canvas_items_keep() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 640)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 360)
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items")
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/aspect")), "keep")


# AC2：七个输入动作全部已定义。
func test_all_seven_input_actions_are_defined() -> void:
	for action in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "输入动作缺失：%s" % action)


func test_renderer_is_forward_plus() -> void:
	assert_eq(str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "forward_plus")


# AC3：主场景入口固定，且能加载。
func test_main_scene_is_configured_and_loadable() -> void:
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	assert_ne(main_scene, "", "project.godot 未设置 application/run/main_scene")
	assert_true(ResourceLoader.exists(main_scene), "主场景资源不存在：%s" % main_scene)
	var packed: PackedScene = load(main_scene) as PackedScene
	assert_not_null(packed, "主场景无法加载为 PackedScene：%s" % main_scene)
	if packed == null:
		return
	var instance: Node = packed.instantiate()
	assert_not_null(instance, "主场景无法实例化")
	if instance != null:
		add_child_autofree(instance)
		await wait_frames(2)
		assert_true(is_instance_valid(instance), "主场景实例化后立即失效")
