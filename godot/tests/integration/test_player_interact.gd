# IT-P02 / FR-P-02：统一交互键 E + 提示气泡 + 最近目标选择。
# 断言：进出范围气泡显隐（AC1）；多目标取最近（AC2）；只认 SPEC-03 §5 三方法约定，
# 测试内自定义的交互物不改玩家代码即可被识别（AC3）。
extends GutTest

const PLAYER_PATH: String = "res://scenes/player/player.tscn"

var _player: CharacterBody2D = null


# 假交互物：只实现 SPEC-03 §5 的三个方法，玩家不认识它的具体类型（这就是 AC3 的证明方式）。
class FakeInteractable:
	extends Area2D

	var prompt_id: String = "prompt_interact"
	var interactable: bool = true
	var interact_calls: Array = []

	func _init() -> void:
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		shape.shape = circle
		add_child(shape)

	func get_interact_prompt() -> String:
		return prompt_id

	func can_interact() -> bool:
		return interactable

	func interact(player: Node) -> void:
		interact_calls.append(player)


func before_each() -> void:
	_player = null
	if not ResourceLoader.exists(PLAYER_PATH):
		fail_test("尚未实现 %s（FR-P-02 / TP-04）" % PLAYER_PATH)
		return
	_player = (load(PLAYER_PATH) as PackedScene).instantiate()
	_player.position = Vector2.ZERO
	add_child_autofree(_player)
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release("interact")


func _prompt_bubble() -> Label:
	var bubble: Node = _player.get_node_or_null(^"%PromptBubble")
	assert_not_null(bubble, "玩家应有唯一名节点 %PromptBubble（SPEC-03 §5.1）")
	return bubble as Label


func _spawn_target(at: Vector2) -> FakeInteractable:
	var target := FakeInteractable.new()
	target.position = at
	add_child_autofree(target)
	return target


# AC1：可交互对象进入范围 → 头顶气泡显示数据表里的提示文案；离开范围 → 消失。
func test_prompt_shows_in_range_and_hides_out() -> void:
	if _player == null:
		return
	var bubble: Label = _prompt_bubble()
	if bubble == null:
		return
	var target: FakeInteractable = _spawn_target(Vector2(16.0, 0.0))
	await wait_physics_frames(3)
	assert_true(bubble.visible, "范围内有可交互对象时气泡应显示")
	assert_eq(bubble.text, "按 E", "气泡文案应来自 ui_strings.prompt_interact")
	target.position = Vector2(500.0, 0.0)
	await wait_physics_frames(3)
	assert_false(bubble.visible, "离开范围后气泡应消失")


# AC1：范围内对象 can_interact() == false 时不显示气泡，按键也不触发交互。
func test_uninteractable_target_shows_no_prompt() -> void:
	if _player == null:
		return
	var bubble: Label = _prompt_bubble()
	if bubble == null:
		return
	var target: FakeInteractable = _spawn_target(Vector2(16.0, 0.0))
	target.interactable = false
	await wait_physics_frames(3)
	assert_false(bubble.visible, "can_interact 为 false 时不该显示气泡")
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(target.interact_calls.size(), 0, "can_interact 为 false 时不许触发 interact()")


# AC2：两个对象同时在范围内，按 E 只触发最近的那个。
func test_nearest_target_wins() -> void:
	if _player == null:
		return
	var near: FakeInteractable = _spawn_target(Vector2(10.0, 0.0))
	var far: FakeInteractable = _spawn_target(Vector2(-20.0, 0.0))
	await wait_physics_frames(3)
	var current: Node = _player.current_interactable()
	assert_eq(current, near, "多目标重叠时应选中最近的一个")
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(near.interact_calls.size(), 1, "按 E 应触发最近对象的 interact()")
	assert_eq(far.interact_calls.size(), 0, "较远的对象不该被触发")
	assert_eq(near.interact_calls[0], _player, "interact() 应收到玩家节点")


# AC2：最近关系随距离动态变化——走近原来较远的对象后切换目标。
func test_target_switches_when_closer_one_changes() -> void:
	if _player == null:
		return
	var left: FakeInteractable = _spawn_target(Vector2(-24.0, 0.0))
	var right: FakeInteractable = _spawn_target(Vector2(24.0, 0.0))
	await wait_physics_frames(3)
	_player.position = Vector2(20.0, 0.0)
	await wait_physics_frames(3)
	assert_eq(_player.current_interactable(), right, "走近右侧后目标应切换")


# AC3：交互物不在范围内（从未进入过 Interactor）时 current_interactable 为 null。
func test_no_target_in_range() -> void:
	if _player == null:
		return
	assert_null(_player.current_interactable(), "范围内没有交互物时应为 null")


# 包A-7：模态面板打开（input_blocked）时气泡必须隐藏，不许在面板后面冒提示；解除后恢复。
func test_prompt_hides_when_input_blocked() -> void:
	if _player == null:
		return
	var bubble: Label = _prompt_bubble()
	if bubble == null:
		return
	var _target: FakeInteractable = _spawn_target(Vector2(16.0, 0.0))
	await wait_physics_frames(3)
	assert_true(bubble.visible, "前置：范围内有可交互对象时气泡应显示")
	_player.set("input_blocked", true)
	await wait_physics_frames(2)
	assert_false(bubble.visible, "input_blocked 时气泡应隐藏")
	_player.set("input_blocked", false)
	await wait_physics_frames(2)
	assert_true(bubble.visible, "解除屏蔽后气泡应恢复显示")
