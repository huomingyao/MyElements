# 湖水（FR-G-14 AC3）：对湖水使用肥皂水 → 消耗 1 份肥皂水，显示硬水字幕 sys_hardwater。
# 没有肥皂水时给湖水提示（zone_salt：湖水是硬水，含较多钙镁离子）。
extends "res://scenes/gameplay/facility_base.gd"

# ==== 常量区 ====

const SOAP_ID: String = "soap_water"
const TIP_HARDWATER: String = "sys_hardwater"
const TIP_NEED_SOAP: String = "zone_salt"

# ==== 逻辑区 ====

func interact(player: Node) -> void:
	var inventory: RefCounted = _inventory_of(player)
	if inventory == null or not bool(inventory.has_item(SOAP_ID, 1)):
		_show_tip(TIP_NEED_SOAP)
		return
	inventory.remove_item(SOAP_ID, 1)
	_show_tip(TIP_HARDWATER)
