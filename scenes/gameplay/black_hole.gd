# 黑洞（区域过渡）：玩家触碰→画面渐黑→传送到对侧区域入口→渐亮。
# 视觉（黑核 + 紫环脉动）_ready 程序化生成；过渡覆盖层即用即建，Tween 驱动不占 _process。
extends Area2D

# 完成一次传送（ from_zone → to_zone ）。
signal traveled(from_zone: String, to_zone: String)

# 从西侧进入时的落点（对侧区域入口）；两侧都由世界总装按区域边界填。
@export var west_target: Vector2 = Vector2.ZERO
@export var east_target: Vector2 = Vector2.ZERO
@export var west_zone: String = ""
@export var east_zone: String = ""

const CORE_COLOR: Color = Color(0.02, 0.0, 0.05)
const RING_COLOR: Color = Color(0.55, 0.25, 0.9, 0.9)
const CORE_RADIUS: float = 16.0
const RING_RADIUS: float = 24.0
const CIRCLE_POINTS: int = 20
const VISUAL_OFFSET: Vector2 = Vector2(0, -60)
const FADE_OUT: float = 0.25
const FADE_IN: float = 0.35
const REARM_DELAY: float = 0.8

var _armed: bool = true
var _ring: Polygon2D = null
var _pulse: Tween = null
var _spin: Tween = null


func _ready() -> void:
	_build_visuals()
	body_entered.connect(_on_body_entered)


func _exit_tree() -> void:
	for tween in [_pulse, _spin]:
		if tween != null and tween.is_valid():
			tween.kill()


func is_armed() -> bool:
	return _armed


func _build_visuals() -> void:
	_ring = Polygon2D.new()
	_ring.name = "Ring"
	_ring.color = RING_COLOR
	_ring.polygon = _circle_points(RING_RADIUS)
	_ring.position = VISUAL_OFFSET
	add_child(_ring)
	var core := Polygon2D.new()
	core.name = "Core"
	core.color = CORE_COLOR
	core.polygon = _circle_points(CORE_RADIUS)
	core.position = VISUAL_OFFSET
	add_child(core)
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_ring, "scale", Vector2(1.15, 1.15), 0.6)
	_pulse.tween_property(_ring, "scale", Vector2.ONE, 0.6)
	_spin = create_tween().set_loops()
	_spin.tween_property(_ring, "rotation", TAU, 4.0).from(0.0)


func _circle_points(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in CIRCLE_POINTS:
		var angle: float = TAU * float(i) / float(CIRCLE_POINTS)
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts


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


func _finish(layer: CanvasLayer, from_zone: String, to_zone: String) -> void:
	layer.queue_free()
	traveled.emit(from_zone, to_zone)
	_rearm()


func _rearm() -> void:
	await get_tree().create_timer(REARM_DELAY).timeout
	_armed = true
