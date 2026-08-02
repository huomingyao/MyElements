# 营地路牌（FR-U-03 AC1，SPEC-03 §5）：交互打开世界地图页。
# 复用设施基类的三方法约定与 autoload 访问助手；地图页开关由 WorldMap autoload 裁决。
extends "res://scenes/gameplay/facility_base.gd"

# ==== 逻辑区 ====

func interact(_player: Node) -> void:
	var wm: Node = get_node_or_null(^"/root/WorldMap")
	if wm == null:
		push_warning("[signpost] WorldMap 不可用，地图页未打开")
		return
	wm.open()
