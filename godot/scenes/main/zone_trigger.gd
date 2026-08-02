# 区域触发器（FR-C-03 场景侧，SPEC-03 §8 ZoneTriggers）：玩家进入时 set_zone。
# 也可配 tip_id（如 zone_river）：进入时 show_once 一次引导字幕，不切换区域。
extends Area2D

# ==== 常量区 ====

# 区域 id（grassland/camp/saltlake/mine/academy）；空串表示不切换区域。
@export var zone_id: String = ""
# 可选：进入时只触发一次的字幕 id（引导类，走 KnowledgeTip.show_once）。
@export var tip_id: String = ""

# ==== 逻辑区 ====

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not zone_id.is_empty():
		var gm: Node = get_node_or_null(^"/root/GameManager")
		if gm != null:
			gm.set_zone(zone_id)
	if not tip_id.is_empty():
		var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
		if tip != null:
			tip.show_once(tip_id)
