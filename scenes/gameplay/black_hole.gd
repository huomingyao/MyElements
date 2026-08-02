# 边缘触发器（区域过渡，2026-08-03 起隐形）：玩家触碰→画面渐黑→传送到对侧区域入口→渐亮。
# 无自有视觉（黑核/紫环已按用户要求移除），边界观感由白盒图幕布承担；
# 过渡覆盖层即用即建，Tween 驱动不占 _process。
extends Area2D

# 完成一次传送（ from_zone → to_zone ）。
signal traveled(from_zone: String, to_zone: String)
# 过场开始（渐黑起，FR-C-10 AC3）：世界据此在渐黑~渐亮期间锁输入。
signal travel_started

# 从西侧进入时的落点（对侧区域入口）；两侧都由世界总装按区域边界填。
@export var west_target: Vector2 = Vector2.ZERO
@export var east_target: Vector2 = Vector2.ZERO
@export var west_zone: String = ""
@export var east_zone: String = ""

const FADE_OUT: float = 0.25
const FADE_IN: float = 0.35
const REARM_DELAY: float = 0.8

var _armed: bool = true


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func is_armed() -> bool:
	return _armed


func _on_body_entered(body: Node) -> void:
	if not _armed or not (body is CharacterBody2D):
		return
	var from_west: bool = (body as Node2D).global_position.x < global_position.x
	var target: Vector2 = east_target if from_west else west_target
	var to_zone: String = east_zone if from_west else west_zone
	var from_zone: String = west_zone if from_west else east_zone
	_armed = false
	_travel(body as Node2D, target, from_zone, to_zone)


# 渐黑→传送→渐亮；覆盖层挂在树根最顶层，播完即释放。
func _travel(body: Node2D, target: Vector2, from_zone: String, to_zone: String) -> void:
	travel_started.emit()
	var layer := CanvasLayer.new()
	layer.layer = 100
	var shade := ColorRect.new()
	shade.color = Color.BLACK
	shade.modulate.a = 0.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	get_tree().root.add_child(layer)
	var tween: Tween = create_tween()
	tween.tween_property(shade, "modulate:a", 1.0, FADE_OUT)
	tween.tween_callback(_teleport.bind(body, target))
	tween.tween_property(shade, "modulate:a", 0.0, FADE_IN)
	tween.tween_callback(_finish.bind(layer, from_zone, to_zone))


func _teleport(body: Node2D, target: Vector2) -> void:
	if is_instance_valid(body):
		body.global_position = target
		# FR-C-10 AC3：传送落位即收敛相机平滑，渐亮期间无跨区拖影（玩家相机，B-008 同款）。
		if body.has_method("reset_camera_smoothing"):
			body.reset_camera_smoothing()


func _finish(layer: CanvasLayer, from_zone: String, to_zone: String) -> void:
	layer.queue_free()
	traveled.emit(from_zone, to_zone)
	_rearm()


func _rearm() -> void:
	await get_tree().create_timer(REARM_DELAY).timeout
	_armed = true
