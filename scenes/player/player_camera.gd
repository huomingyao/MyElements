# PlayerCamera（FR-P-03 AC1）：跟随玩家（场景内作为子节点 + 平滑），
# 地图边界由世界场景通过 set_map_bounds 写入四条 limit，相机不越界。
# 包A-4：snap_to_target() 传送后收敛平滑；包A-8：shake() 相机震动 juice。
extends Camera2D

# 震动最小幅度比例：随机幅度取 [比例, 1]×强度，避免开头几帧近似零偏移（测试可断言）。
const SHAKE_MIN_FRACTION: float = 0.5

var _shake_tween: Tween = null
var _shake_intensity: float = 0.0


# bounds：世界坐标下的可行走矩形；取整对齐像素网格。
func set_map_bounds(bounds: Rect2) -> void:
	limit_left = int(floor(bounds.position.x))
	limit_top = int(floor(bounds.position.y))
	limit_right = int(ceil(bounds.end.x))
	limit_bottom = int(ceil(bounds.end.y))


# 传送/复活后调用：平滑立即收敛到新位置，避免相机横跨地图慢追（包A-4）。
func snap_to_target() -> void:
	reset_smoothing()


# 相机震动（包A-8）：强度（像素）与时长（秒）；新震动打断旧震动，结束精确复位。
func shake(intensity: float, duration: float) -> void:
	if intensity <= 0.0 or duration <= 0.0:
		push_warning("[camera] shake 参数非法：intensity=%s duration=%s（忽略）" % [intensity, duration])
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_intensity = intensity
	_shake_tween = create_tween()
	_shake_tween.tween_method(_shake_step, 0.0, 1.0, duration)
	_shake_tween.tween_callback(_end_shake)


# 随进度衰减的随机方向扰动（表现层随机，不参与玩法判定）。
func _shake_step(progress: float) -> void:
	var decay: float = 1.0 - progress
	var angle: float = randf() * TAU
	var magnitude: float = randf_range(SHAKE_MIN_FRACTION, 1.0) * _shake_intensity * decay
	offset = Vector2(cos(angle), sin(angle)) * magnitude


func _end_shake() -> void:
	_shake_intensity = 0.0
	offset = Vector2.ZERO
