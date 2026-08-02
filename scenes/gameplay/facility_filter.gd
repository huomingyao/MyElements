# 过滤器（FR-G-13 AC1）：水 → 纯净水，触发净水四步字幕 sys_filter。
# 没有水时提示去河边取水（zone_river：天然水含杂质，需净化后才能用于实验）。
extends "res://scenes/gameplay/facility_base.gd"

# ==== 常量区（id 与键名，不是玩家可见文案） ====

const INPUT_ID: String = "h2o"
const OUTPUT_ID: String = "h2o_clean"
const TIP_DONE: String = "sys_filter"
const TIP_NEED_WATER: String = "zone_river"

# ==== 逻辑区 ====

func interact(player: Node) -> void:
	var inventory: RefCounted = _inventory_of(player)
	if inventory == null or not bool(inventory.has_item(INPUT_ID, 1)):
		_show_tip(TIP_NEED_WATER)
		return
	inventory.remove_item(INPUT_ID, 1)
	inventory.add_item(OUTPUT_ID, 1)
	_show_tip(TIP_DONE)
