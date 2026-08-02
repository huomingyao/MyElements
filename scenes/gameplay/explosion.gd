# Explosion（FR-G-08 AC2 表现层）：屏幕震动 + 火光 + 音效。
# 纯表现节点，不含玩法判定（判定在 scripts/gameplay/hydrogen_event.gd）；
# 与逻辑层的唯一接线是 bind()：HydrogenEvent.explosion_triggered → play()。
# 音效资源由 P5 后补，%BoomPlayer 无 stream 时静默跳过，不报错。
extends Node2D

# 一次表现播完（火光熄灭 + 震屏复位）。
signal finished()

# ==== 常量区 ====
# 表现参数（非 SPEC-02 §4 调参项）：火光亮度和时长、震屏强度。
const FLASH_MAX_ALPHA: float = 0.85
const FLASH_IN_SECONDS: float = 0.06
const FLASH_OUT_SECONDS: float = 0.45
const SHAKE_STRENGTH: float = 14.0

@onready var _flash: ColorRect = %Flash
@onready var _boom: AudioStreamPlayer = %BoomPlayer

var _shake_target: Camera2D = null

# ==== 逻辑区 ====

# 注入震屏目标（通常是玩家相机）；不注入则只放火光与音效。
func set_shake_target(camera: Camera2D) -> void:
	_shake_target = camera


# 与 HydrogenEvent 接线：爆炸信号驱动 play()。重复绑定或非法对象只警告，不崩溃。
func bind(event: RefCounted) -> void:
	if event == null or not event.has_signal("explosion_triggered"):
		push_warning("[fx] bind 收到无 explosion_triggered 信号的对象（忽略）")
		return
	if not event.is_connected("explosion_triggered", play):
		event.connect("explosion_triggered", play)


# 触发一次爆炸表现：火光快亮慢灭 + 相机衰减扰动 + 音效；结束后复位并发 finished。
func play() -> void:
	if not is_inside_tree():
		push_warning("[fx] play 需要在场景树内调用（忽略）")
		return
	if _boom != null and _boom.stream != null:
		_boom.play()
	_flash.modulate.a = 0.0
	var total: float = FLASH_IN_SECONDS + FLASH_OUT_SECONDS
	# 全并行：火光快亮慢灭（熄灭段延迟到点亮后），震屏覆盖整段表现。
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_flash, "modulate:a", FLASH_MAX_ALPHA, FLASH_IN_SECONDS)
	tween.tween_property(_flash, "modulate:a", 0.0, FLASH_OUT_SECONDS).set_delay(FLASH_IN_SECONDS)
	if _shake_target != null:
		# 随进度衰减的随机扰动（表现层随机，不参与玩法判定）。
		tween.tween_method(_shake_step, 0.0, 1.0, total)
	tween.chain().tween_callback(_finish)


func _shake_step(progress: float) -> void:
	if _shake_target == null:
		return
	var decay: float = 1.0 - progress
	_shake_target.offset = Vector2(
		randf_range(-SHAKE_STRENGTH, SHAKE_STRENGTH),
		randf_range(-SHAKE_STRENGTH, SHAKE_STRENGTH)
	) * decay


# 收尾：相机精确复位、火光确保熄灭，再发 finished。
func _finish() -> void:
	if _shake_target != null:
		_shake_target.offset = Vector2.ZERO
	_flash.modulate.a = 0.0
	finished.emit()
