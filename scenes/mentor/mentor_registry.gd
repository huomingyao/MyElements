# 导师数据查询（FR-M-01/M-02）：mentors.json 的只读视图。
# 纯逻辑 RefCounted（同 SPEC-03 §6.1 MentorRouter 的定位），经静态 DataLoader 读表，
# 场景不自己 FileAccess.open 数据表（SPEC-03 §1）。代码里零内容文本（FR-M-06 AC1）。
extends RefCounted

# ==== 常量区 ====
const TABLE_FILE: String = "mentors.json"

const F_ID: String = "id"
const F_NAME: String = "name"
const F_TITLE: String = "title"
const F_ROOM: String = "room"
const F_SPRITE: String = "sprite"
const F_AVATAR_IDLE: String = "avatar_idle"
const F_AVATAR_TALK: String = "avatar_talk"

# ==== 状态区 ====
var _by_id: Dictionary = {}
var _order: Array = []


# ==== 逻辑区 ====
func _init() -> void:
	load_from(DataLoader.load_table(TABLE_FILE, TYPE_ARRAY, []) as Array)


# 数据注入口（SPEC-06 §3 可测性约束）。
func load_from(rows: Array) -> void:
	_by_id = DataLoader.index_by_id(rows)
	_order = []
	for row_value in rows:
		if typeof(row_value) != TYPE_DICTIONARY:
			continue
		var id: String = str((row_value as Dictionary).get(F_ID, ""))
		if not id.is_empty():
			_order.append(id)


# 全部导师 id，按表中顺序（学院摆放顺序即数据顺序，铁律 4）。
func mentor_ids() -> Array:
	return _order.duplicate()


func record(mentor_id: String) -> Dictionary:
	return (_by_id.get(mentor_id, {}) as Dictionary).duplicate()


func name_of(mentor_id: String) -> String:
	return str((_by_id.get(mentor_id, {}) as Dictionary).get(F_NAME, ""))


func title_of(mentor_id: String) -> String:
	return str((_by_id.get(mentor_id, {}) as Dictionary).get(F_TITLE, ""))


func room_of(mentor_id: String) -> String:
	return str((_by_id.get(mentor_id, {}) as Dictionary).get(F_ROOM, ""))


func sprite_of(mentor_id: String) -> String:
	return str((_by_id.get(mentor_id, {}) as Dictionary).get(F_SPRITE, ""))


func avatar_idle_of(mentor_id: String) -> String:
	return str((_by_id.get(mentor_id, {}) as Dictionary).get(F_AVATAR_IDLE, ""))


func avatar_talk_of(mentor_id: String) -> String:
	return str((_by_id.get(mentor_id, {}) as Dictionary).get(F_AVATAR_TALK, ""))
