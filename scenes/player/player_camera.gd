# PlayerCamera（FR-P-03 AC1）：跟随玩家（场景内作为子节点 + 平滑），
# 地图边界由世界场景通过 set_map_bounds 写入四条 limit，相机不越界。
extends Camera2D


# bounds：世界坐标下的可行走矩形；取整对齐像素网格。
func set_map_bounds(bounds: Rect2) -> void:
	limit_left = int(floor(bounds.position.x))
	limit_top = int(floor(bounds.position.y))
	limit_right = int(ceil(bounds.end.x))
	limit_bottom = int(ceil(bounds.end.y))
