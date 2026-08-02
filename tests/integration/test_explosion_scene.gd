# 爆炸表现层场景冒烟（FR-G-08 AC2 的动画/音效挂载点，IT-G08 的可见部分）。
# 玩法判定逻辑在 scripts/gameplay/hydrogen_event.gd（见 test_hydrogen_event.gd）；
# 本文件只验证 scenes/gameplay/explosion.tscn 能加载、play() 不报错、表现后能复位。
extends GutTest

const SCENE_PATH: String = "res://scenes/gameplay/explosion.tscn"
const EVENT_PATH: String = "res://scripts/gameplay/hydrogen_event.gd"
const CAMERA_SCRIPT_PATH: String = "res://scenes/player/player_camera.gd"

# 与 explosion.gd SHAKE_STRENGTH 对齐的扰动上限（像素）：震屏幅度不许越过表现层强度。
const MAX_SHAKE_OFFSET_PX: float = 14.0


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


# 震屏统一出口（收口 W1）：爆炸不再直写 camera.offset，而是调相机的
# shake(intensity, duration)——与世界的受伤/爆炸震动同一通道，杜绝同帧竞争写 offset。
# 进行中 offset 被扰动且不越强度上限，结束后由相机自身精确复位到零。
func test_shake_disturbs_then_restores_camera_offset() -> void:
	var inst: Node = _spawn()
	if inst == null:
		return
	assert_true(inst.has_method("set_shake_target"), "应有 set_shake_target(camera)")
	if not inst.has_method("set_shake_target"):
		return
	if not ResourceLoader.exists(CAMERA_SCRIPT_PATH):
		fail_test("尚未实现 %s（震屏统一出口的接收方）" % CAMERA_SCRIPT_PATH)
		return
	var cam: Camera2D = (load(CAMERA_SCRIPT_PATH) as GDScript).new() as Camera2D
	assert_not_null(cam, "PlayerCamera 应可实例化")
	add_child_autofree(cam)
	inst.set_shake_target(cam)
	inst.play()
	await wait_seconds(0.15, "等待表现进入震屏段")
	assert_ne(cam.offset, Vector2.ZERO, "震屏进行中相机应被扰动")
	assert_gt(float(cam.get("_shake_intensity")), 0.0,
		"震屏应经相机 shake() 通道（统一出口），不许爆炸直写 offset")
	assert_true(cam.offset.length() <= MAX_SHAKE_OFFSET_PX + 0.001,
		"扰动幅度不许越过爆炸表现层强度：%s" % str(cam.offset))
	await wait_for_signal(inst.finished, 3.0)
	await wait_process_frames(1) # 相机 shake 收尾与 finished 同帧段，等一帧确保复位
	assert_eq(cam.offset, Vector2.ZERO, "震屏结束相机应精确复位")


# 防御：注入无 shake() 的普通 Camera2D 时不崩溃、表现照常播完，offset 不被触碰。
func test_play_without_shake_capable_camera_still_finishes() -> void:
	var inst: Node = _spawn()
	if inst == null:
		return
	var cam: Camera2D = Camera2D.new()
	add_child_autofree(cam)
	inst.set_shake_target(cam)
	watch_signals(inst)
	inst.play()
	await wait_seconds(0.15, "等待表现进入震屏段")
	assert_eq(cam.offset, Vector2.ZERO, "无 shake 能力时震屏段 offset 也不许被直写")
	await wait_for_signal(inst.finished, 3.0, "无 shake 能力的相机不应阻塞表现")
	assert_signal_emitted(inst, "finished", "表现应照常播完")
	assert_eq(cam.offset, Vector2.ZERO, "无 shake 能力时 offset 不许被直写")


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


# 模块化重构（视觉逻辑分离）：世界空间特效（火球/冲击波）拆成 Visuals 下独立节点，
# 音频进 Audio 容器；全屏闪光留在 CanvasLayer 根层。
func test_modular_node_structure() -> void:
	var inst: Node = _spawn()
	if inst == null:
		return
	var visuals: Node = inst.get_node_or_null(^"%Visuals")
	assert_not_null(visuals, "应有 %Visuals 视觉容器（模块化重构）")
	if visuals == null:
		return
	assert_true(visuals is Node2D, "视觉容器应为 Node2D")
	assert_true(inst.get_node_or_null(^"%Fireball") is Polygon2D,
		"应有 %Fireball 火球部件（Polygon2D）")
	assert_true(inst.get_node_or_null(^"%Shockwave") is Polygon2D,
		"应有 %Shockwave 冲击波部件（Polygon2D）")
	var audio: Node = inst.get_node_or_null(^"%Audio")
	assert_not_null(audio, "应有 %Audio 音频容器")
	if audio != null:
		var boom: Node = inst.get_node_or_null(^"%BoomPlayer")
		if boom != null:
			assert_eq(boom.get_parent(), audio, "%BoomPlayer 应挂在 %Audio 容器下")


# 防御：bind 收到无 explosion_triggered 信号的对象不崩溃，只警告。
func test_bind_rejects_object_without_signal() -> void:
	var inst: Node = _spawn()
	if inst == null:
		return
	inst.bind(RefCounted.new())
	inst.bind(null)
	assert_true(true, "非法 bind 不应崩溃")
