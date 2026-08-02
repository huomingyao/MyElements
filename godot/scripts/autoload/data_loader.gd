# 数据表读取工具（SPEC-03 §1：数据表只由 autoload 读取）。
# 纯静态类，不进 autoload 注册；给五个 autoload 共用，避免各写一份解析。
class_name DataLoader
extends RefCounted

const DATA_DIR: String = "res://data/"


# 读一张 JSON 表。顶层类型不符或文件缺失时返回 fallback 并打印可读警告，不崩溃。
static func load_table(file_name: String, expected_type: int, fallback: Variant) -> Variant:
	var path: String = DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_warning("[data] 数据表缺失：%s（使用内置默认值）" % path)
		return fallback
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[data] 数据表打开失败：%s（错误码 %d）" % [path, FileAccess.get_open_error()])
		return fallback
	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_error("[data] 数据表解析失败：%s 第 %d 行：%s" % [path, json.get_error_line(), json.get_error_message()])
		return fallback
	if typeof(json.data) != expected_type:
		push_error("[data] 数据表顶层类型不符：%s（期望 %d，实际 %d）" % [path, expected_type, typeof(json.data)])
		return fallback
	return json.data


# 按点分键在嵌套字典里取值；任一段缺失或中途踩到非字典 → 返回 default_value + 警告。
static func dig(data: Dictionary, dotted_key: String, default_value: Variant) -> Variant:
	if dotted_key.is_empty():
		push_warning("[data] 点分键为空，返回默认值")
		return default_value
	var node: Variant = data
	for part in dotted_key.split("."):
		if typeof(node) != TYPE_DICTIONARY:
			push_warning("[data] 键路径中途不是字典：%s（返回默认值）" % dotted_key)
			return default_value
		var dict: Dictionary = node
		if not dict.has(part):
			push_warning("[data] 缺键：%s（返回默认值）" % dotted_key)
			return default_value
		node = dict[part]
	return node


# 按 id 建索引，供 O(1) 查询。
static func index_by_id(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = row
		var id: String = str(dict.get("id", ""))
		if id.is_empty():
			continue
		out[id] = dict
	return out
