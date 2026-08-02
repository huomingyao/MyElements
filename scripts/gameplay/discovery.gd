# Discovery（FR-G-03，UT-G03）：首次收集统计。重复拾取只计一次。
# 纯逻辑 RefCounted，可直接实例化（SPEC-06 §3 可测性约束）。
# HUD 计数集合来自 substances.json 的 count_in_hud 字段，总数不写死（NFR-04）。
extends RefCounted

signal substance_discovered(substance_id: String)

# ==== 常量区 ====

const KEY_ID: String = "id"
const KEY_COUNT_IN_HUD: String = "count_in_hud"

# ==== 逻辑区 ====

# id -> true。用字典当集合，查询 O(1)。
var _discovered: Dictionary = {}

# 记一次发现。首次返回 true 并发信号，重复或非法 id 返回 false（AC1）。
func discover(substance_id: String) -> bool:
	if substance_id.is_empty():
		return false
	if _discovered.has(substance_id):
		return false
	if not _is_known(substance_id):
		push_warning("[discovery] 物质表里没有这个 id：%s" % substance_id)
		return false
	_discovered[substance_id] = true
	substance_discovered.emit(substance_id)
	return true


# AC2：供图鉴查询。co2 也在其中（图鉴展示全部 17 张卡）。
func is_discovered(substance_id: String) -> bool:
	return _discovered.has(substance_id)


func discovered_count() -> int:
	return _discovered.size()


func discovered_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _discovered.keys():
		out.append(id)
	return out


# HUD 计数集合总数：数数据表里 count_in_hud=true 的条数，不写死（NFR-04）。
func count_total() -> int:
	var total: int = 0
	for row: Dictionary in _all_substances():
		if bool(row.get(KEY_COUNT_IN_HUD, true)):
			total += 1
	return total


# HUD 已收集数：只统计计数集合内的已发现物质（co2 不计入，口径见 SPEC-05 §1）。
func counted_count() -> int:
	var total: int = 0
	for row: Dictionary in _all_substances():
		if not bool(row.get(KEY_COUNT_IN_HUD, true)):
			continue
		if _discovered.has(str(row.get(KEY_ID, ""))):
			total += 1
	return total


# 复位（新开局/测试用）。
func reset() -> void:
	_discovered.clear()


func _is_known(substance_id: String) -> bool:
	for row: Dictionary in _all_substances():
		if str(row.get(KEY_ID, "")) == substance_id:
			return true
	return false


# 物质表只由 autoload 读取（SPEC-03 §1）；RecipeDB 缺失时返回空表，不崩溃。
func _all_substances() -> Array:
	var db: Node = _recipe_db()
	if db == null:
		push_warning("[discovery] RecipeDB 不可用，物质表为空")
		return []
	return db.all_substances()


func _recipe_db() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(^"RecipeDB")

