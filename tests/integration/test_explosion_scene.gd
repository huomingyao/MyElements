# 爆炸表现层场景冒烟（FR-G-08 AC2 的动画/音效挂载点，IT-G08 的可见部分）。
# 玩法判定逻辑在 scripts/gameplay/hydrogen_event.gd（见 test_hydrogen_event.gd）；
# 本文件只验证 scenes/gameplay/explosion.tscn 能加载、play() 不报错、表现后能复位。
extends GutTest

const SCENE_PATH: String = "res://scenes/gameplay/explosion.tscn"
const EVENT_PATH: String = "res://scripts/gameplay/hydrogen_event.gd"


func before_each() -> void:
	if not ResourceLoader.exists(SCENE_PATH):
		fail_test("尚未实现 %s（FR-G-08 爆炸表现层）" % SCENE_PATH)


func _spawn() -> Node:
	var packed: Resource = load(SCENE_PATH)
	assert_not_null(packed, "explosion.tscn 应可加载")
	if packed == null:
		return null
	var inst: Node = (packed as PackedScene).instantiate()
	add_child_autofree(inst)
	return inst


# 场景可实例化且节点结构齐全（唯一名 %Flash / %BoomPlayer），接口方法存在。
func test_scene_loads_with_required_structure() -> void:
	var inst: Node = _spawn()
	if inst == null:
		return
	assert_true(inst.has_method("play"), "应有 play() 触发爆炸表现")
	assert_true(inst.has_method("bind"), "应有 bind(event) 接线 HydrogenEvent")
	assert_true(inst.has_signal("finished"), "应有 finished 信号（表现结束）")
	assert_not_null(inst.get_node_or_null("%Flash"), "缺 %Flash 火光层")
	assert_not_null(inst.get_node_or_null("%BoomPlayer"), "缺 %BoomPlayer 音效节点")


# play()：火光先亮后灭，结束后复位不可见并发 finished；无音频资源时不报错。
func test_play_flashes_then_restores_and_finishes() -> void:
	var inst: Node = _spawn()
	if inst == null:
		return
	var flash: ColorRect = inst.get_node("%Flash") as ColorRect
	assert_almost_eq(flash.modulate.a, 0.0, 0.001, "初始火光应不可见")
	watch_signals(inst)
	inst.play()
	await wait_for_signal(inst.finished, 3.0, "爆炸表现应在 3 秒内结束")
	assert_signal_emitted(inst, "finished", "表现结束应发 finished")
	assert_almost_eq(flash.modulate.a, 0.0, 0.01, "结束后火光应恢复不可见")


# 震屏：注入相机后 play()，进行中 offset 被扰动，结束后精确复位到零。
func test_shake_disturbs_then_restores_camera_offset() -> void:
	var inst: Node = _spawn()
	if inst == null:
		return
	assert_true(inst.has_method("set_shake_target"), "应有 set_shake_target(camera)")
	if not inst.has_method("set_shake_target"):
		return
	var cam: Camera2D = Camera2D.new()
	add_child_autofree(cam)
	inst.set_shake_target(cam)
	inst.play()
	await wait_seconds(0.15, "等待表现进入震屏段")
	assert_ne(cam.offset, Vector2.ZERO, "震屏进行中相机应被扰动")
	await wait_for_signal(inst.finished, 3.0)
	assert_eq(cam.offset, Vector2.ZERO, "震屏结束相机应精确复位")


# bind：HydrogenEvent 的 explosion_triggered 信号驱动 play()（表现层与逻辑层的唯一接线）。
func test_bind_triggers_play_on_explosion_signal() -> void:
	if not ResourceLoader.exists(EVENT_PATH):
		fail_test("尚未实现 %s" % EVENT_PATH)
		return
	var inst: Node = _spawn()
	if inst == null:
		return
	var event: RefCounted = (load(EVENT_PATH) as GDScript).new()
	inst.bind(event)
	watch_signals(inst)
	event.explosion_triggered.emit()
	await wait_for_signal(inst.finished, 3.0, "bind 后爆炸信号应触发完整表现")
	assert_signal_emitted(inst, "finished", "爆炸信号应驱动表现播完")


# 防御：bind 收到无 explosion_triggered 信号的对象不崩溃，只警告。
func test_bind_rejects_object_without_signal() -> void:
	var inst: Node = _spawn()
	if inst == null:
		return
	inst.bind(RefCounted.new())
	inst.bind(null)
	assert_true(true, "非法 bind 不应崩溃")
