# tests/data 共用的 JSON 读取工具。
# 文件名不以 test_ 开头，GUT 不会把它当测试脚本收集。
extends RefCounted

const DATA_DIR: String = "res://data/"


# 读顶层为数组的表；文件缺失或不可解析时返回空数组（让断言报"条数不符"而不是脚本崩）。
static func read_array(file_name: String) -> Array:
	var parsed: Variant = _parse(DATA_DIR + file_name)
	if typeof(parsed) != TYPE_ARRAY:
		return []
	return parsed


# 读顶层为对象的表；文件缺失或不可解析时返回空字典。
static func read_object(file_name: String) -> Dictionary:
	var parsed: Variant = _parse(DATA_DIR + file_name)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func rows_of(file_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in read_array(file_name):
		if typeof(row) == TYPE_DICTIONARY:
			out.append(row)
	return out


static func ids_of(rows: Array) -> Array[String]:
	var out: Array[String] = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		out.append(str((row as Dictionary).get("id", "")))
	return out


static func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
