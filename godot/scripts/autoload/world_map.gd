# WorldMap（SPEC-03 §7，FR-U-03）：13 区域状态与地图页开关。
# 区域数据全部来自 worldmap.json，UI 不硬编码区域名与预告语。
extends Node

signal map_opened()
signal map_closed()

var _zones: Array = []
var _zones_by_id: Dictionary = {}
var _open: bool = false


func _ready() -> void:
	reload()


func reload() -> void:
	_zones = DataLoader.load_table("worldmap.json", TYPE_ARRAY, [])
	_zones_by_id = DataLoader.index_by_id(_zones)


# 打开地图页。autoload 不直接持有 UI 节点，只发信号（SPEC-03 §1 依赖方向铁律）。
func open() -> void:
	if _open:
		return
	_open = true
	map_opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	map_closed.emit()


func is_open() -> bool:
	return _open


func is_unlocked(zone_id: String) -> bool:
	var zone: Dictionary = _zones_by_id.get(zone_id, {})
	if zone.is_empty():
		push_warning("[worldmap] 未知区域 id：%s（按未解锁处理）" % zone_id)
		return false
	return bool(zone.get("unlocked", false))


func all_zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in _zones:
		if typeof(row) == TYPE_DICTIONARY:
			out.append(row)
	return out


func get_zone(zone_id: String) -> Dictionary:
	return _zones_by_id.get(zone_id, {})
