# 数据校验器（FR-D-07，检查项见 SPEC-04 §12 的 10 类）。可 headless 运行：
#   ./validate_data.sh        全通过打印 DATA OK 且退出码 0；任一失败退出码 1 并逐条列出
#
# 资源路径检查（第 6 类）的口径——P4 美术未开工，图标文件大多尚不存在，因此：
#   * 路径必须以 res://assets/ 开头且扩展名合法，否则算 error；
#   * 路径合法但文件不存在时只输出 warning，不进 error、不影响退出码。
# 等 P4 交付资源后可把 warning 收紧为 error（改这一处即可，见 _check_asset_path）。
#
# 诊断文案用中文（属工具日志），但表名、字段名、枚举值、期望条数一律取自本文件顶部常量区，
# 逻辑里不写裸字面量（NFR-04）。
extends SceneTree

# 表缺失或 JSON 不可解析时的占位值（第 1 类检查的输入）。
const PARSE_FAILED: String = "__parse_failed__"
const DATA_DIR: String = "res://data/"

# ---- 表名 ----
const T_SUBSTANCES: String = "substances.json"
const T_RECIPES: String = "recipes.json"
const T_FAIL_MESSAGES: String = "fail_messages.json"
const T_TIPS: String = "tips.json"
const T_MENTORS: String = "mentors.json"
const T_QA: String = "qa_fallback.json"
const T_WORLDMAP: String = "worldmap.json"
const T_BALANCE: String = "balance.json"
const T_ITEMS: String = "items.json"
const T_UI_STRINGS: String = "ui_strings.json"

const ARRAY_TABLES: Array[String] = [
	T_SUBSTANCES, T_RECIPES, T_FAIL_MESSAGES, T_TIPS,
	T_MENTORS, T_QA, T_WORLDMAP, T_ITEMS,
]
const OBJECT_TABLES: Array[String] = [T_BALANCE, T_UI_STRINGS]

# SPEC-04 §12 的检查项编号（供自检与报告）。
const CHECK_IDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

# ---- 字段名 ----
const F_ID: String = "id"
const F_TIP_ID: String = "tip_id"
const F_ICON: String = "icon"
const F_ZONE: String = "zone"
const F_CATEGORY: String = "category"
const F_COUNT_IN_HUD: String = "count_in_hud"
const F_INPUTS: String = "inputs"
const F_OUTPUTS: String = "outputs"
const F_TOOL: String = "tool"
const F_CONDITION: String = "condition"
const F_UNLOCK_TIP: String = "unlock_tip"
const F_REQUIRES_PURE_CHECK: String = "requires_pure_check"
const F_STYLE: String = "style"
const F_ROUTE_CLASS: String = "route_class"
const F_SYSTEM_PROMPT: String = "system_prompt"
const F_EFFECT_VALUE_KEY: String = "effect_value_key"
const F_UNLOCKED: String = "unlocked"
const F_BRIEF: String = "brief"
const F_TEASER: String = "teaser"
const F_HOTSPOT: String = "hotspot"
const F_AVATAR_IDLE: String = "avatar_idle"
const F_AVATAR_TALK: String = "avatar_talk"
const F_SPRITE: String = "sprite"
const F_MENTOR_ID: String = "mentor_id"
const F_NAME: String = "name"
const F_FORMULA: String = "formula"
const F_CODEX_LINE: String = "codex_line"
const F_TEXT: String = "text"
const F_REASON: String = "reason"
const F_TITLE: String = "title"
const F_ROOM: String = "room"
const F_CATCHPHRASES: String = "catchphrases"
const F_MENTION: String = "mention"
const F_DISPATCH: String = "dispatch"
const F_TARGETS: String = "targets"
const F_LINE: String = "line"
const F_KEYWORDS: String = "keywords"
const F_ANSWER: String = "answer"
const F_TYPE: String = "type"
const F_EFFECT: String = "effect"
const F_EQUATION: String = "equation"
const F_CARD_TITLE: String = "card_title"
const F_CARD_BODY: String = "card_body"
const F_CARD_APPLICATION: String = "card_application"

# ---- 枚举允许值（SPEC-04 各表「约束」列）----
const CATEGORIES: Array[String] = ["单质", "化合物", "氧化物", "酸", "碱", "盐"]
const ZONES: Array[String] = ["grassland", "camp", "saltlake", "mine", "academy"]
const TOOLS: Array[String] = ["portable", "alcohol_lamp", "bench", "electrolyzer", "filter"]
const CONDITIONS: Array[String] = [
	"none", "ignite", "heat", "electrify", "catalyst", "low_oxygen", "three_step",
]
const FAIL_REASONS: Array[String] = ["no_match", "wrong_condition"]
const TIP_STYLES: Array[String] = ["bubble", "banner", "warning"]
const ROUTE_CLASSES: Array[String] = ["chemistry", "dispatch", "planning", "thinking"]
const ITEM_TYPES: Array[String] = ["equip", "consume", "material"]
const ITEM_EFFECTS: Array[String] = [
	"light", "kill_co", "kill_acid", "extinguish", "immune_co",
	"restore_oxygen", "restore_energy", "test_hardwater", "none",
]

# 表 → 字段 → 允许值（第 4 类检查的输入）。
const ENUM_FIELDS: Dictionary = {
	T_SUBSTANCES: {F_CATEGORY: CATEGORIES},
	T_RECIPES: {F_TOOL: TOOLS, F_CONDITION: CONDITIONS},
	T_FAIL_MESSAGES: {F_REASON: FAIL_REASONS},
	T_TIPS: {F_STYLE: TIP_STYLES},
	T_MENTORS: {F_ROUTE_CLASS: ROUTE_CLASSES},
	T_ITEMS: {F_TYPE: ITEM_TYPES, F_EFFECT: ITEM_EFFECTS},
}
# zone 是数组型枚举，单列出来（第 4 类检查的数组分支）。
const ARRAY_ENUM_FIELDS: Dictionary = {
	T_SUBSTANCES: {F_ZONE: ZONES},
}

# ---- 必填字段（第 3 类检查）----
const REQUIRED_FIELDS: Dictionary = {
	T_SUBSTANCES: [
		F_ID, F_NAME, F_FORMULA, F_CATEGORY, F_TIP_ID, F_ICON, F_CODEX_LINE,
	],
	T_RECIPES: [
		F_ID, F_INPUTS, F_TOOL, F_CONDITION, F_OUTPUTS,
		F_EQUATION, F_CARD_TITLE, F_CARD_BODY, F_CARD_APPLICATION,
	],
	T_FAIL_MESSAGES: [F_ID, F_REASON, F_TEXT],
	T_TIPS: [F_ID, F_STYLE, F_TEXT],
	T_MENTORS: [
		F_ID, F_NAME, F_TITLE, F_ROOM, F_AVATAR_IDLE, F_AVATAR_TALK,
		F_SPRITE, F_ROUTE_CLASS, F_CATCHPHRASES, F_SYSTEM_PROMPT, F_MENTION,
	],
	# keywords 不在此列：兜底行允许为空数组（SPEC-04 §7），改由 _check_qa_keywords 专管。
	T_QA: [F_ID, F_MENTOR_ID, F_ANSWER],
	T_WORLDMAP: [F_ID, F_NAME, F_HOTSPOT],
	T_ITEMS: [F_ID, F_NAME, F_TYPE, F_ICON, F_EFFECT],
}

# ---- 资源路径字段（第 6 类检查）----
const ASSET_FIELDS: Dictionary = {
	T_SUBSTANCES: [F_ICON],
	T_ITEMS: [F_ICON],
	T_MENTORS: [F_AVATAR_IDLE, F_AVATAR_TALK, F_SPRITE],
}
const ASSET_PREFIX: String = "res://assets/"
const ASSET_EXTENSIONS: Array[String] = ["png", "svg", "webp"]

# ---- 条数约束（第 7 类检查）----
const COUNT_SUBSTANCES: int = 17
const COUNT_SUBSTANCES_IN_HUD: int = 16
const COUNT_RECIPES: int = 12
const COUNT_MENTORS: int = 4
const COUNT_WORLDMAP: int = 13
const COUNT_WORLDMAP_UNLOCKED: int = 5
const COUNT_QA_MIN: int = 20
# SPEC-04 §7：恰好一行 keywords 为空数组，那行就是零命中兜底话术。
const COUNT_QA_FALLBACK_ROWS: int = 1
const COUNT_PURE_CHECK_RECIPES: int = 1
const MIN_FAIL_MESSAGES_PER_REASON: int = 2
const EXACT_COUNTS: Dictionary = {
	T_SUBSTANCES: COUNT_SUBSTANCES,
	T_RECIPES: COUNT_RECIPES,
	T_MENTORS: COUNT_MENTORS,
	T_WORLDMAP: COUNT_WORLDMAP,
}

# ---- 第 9 类：导师 prompt ----
const MONITOR_ID: String = "monitor"
const DISPATCH_KEYWORDS: Array[String] = ["@化学老师", "@思维老师", "@助理"]
const NO_AT_CLAUSE: String = "回答里绝不出现 @。"
const AT_SIGN: String = "@"
# SPEC-04 §5：数组顺序即分类优先级，逐位比对。
const DISPATCH_CATEGORIES: Array[String] = ["combat", "learning", "chemistry", "other"]
const DISPATCH_FIELDS: Array[String] = [F_CATEGORY, F_KEYWORDS, F_TARGETS, F_LINE]
# 兜底类：keywords 必须为空（其余类必须非空）。
const DISPATCH_FALLBACK_CATEGORY: String = "other"
const DISPATCH_TARGETS_MAX: int = 2
# 派活人数硬约束（SPEC-05 §4.1 判断表：learning 是「方法 + 计划」两位）。
const DISPATCH_EXACT_TARGETS: Dictionary = {"learning": 2}

# ---- 第 10 类：ui_strings（SPEC-05 §9 全部 key）----
const UI_STRING_KEYS: Array[String] = [
	"prompt_interact", "prompt_ask", "menu_start", "menu_academy", "menu_codex",
	"menu_quit", "craft_react", "craft_purity", "craft_ignite", "codex_locked",
	"map_locked_badge", "chat_placeholder", "chat_offline_badge",
	"collected_counter", "death_title", "config_note",
	"death_info", "death_day", "death_hint",
	"config_apply", "chat_config",
	"hud_day", "hud_night", "hud_oxygen", "hud_energy", "hud_health",
	"pause_title", "pause_continue", "pause_to_menu",
	"menu_map", "chat_send", "chat_close", "chat_player_label",
	"craft_title", "craft_tool_portable", "craft_tool_lamp", "craft_tool_bench",
	"craft_cancel", "craft_slot_empty", "inventory_title",
	"inventory_craft_hint",
	"mentor_room_title", "mentor_room_hint", "mentor_room_back",
]
const ALLOWED_PLACEHOLDER: String = "{n}"
const PLACEHOLDER_PATTERN: String = "\\{[^}]*\\}"

const OK_MESSAGE: String = "DATA OK"

# 第 7 类诊断里的"被计数对象"标签（属工具日志文案，集中在此便于统一改口径）。
const SUBJECT_ROW_COUNT: String = "条数"
const SUBJECT_MIN_ROW_COUNT: String = "条数下限"
const SUBJECT_FAIL_POOL_FORMAT: String = "%s=%s 的文案池"


# ---------------------------------------------------------------- 对外接口 ----
# 全量校验。tables 形如 {"substances.json": [...], "balance.json": {...}}；
# 解析失败的表传 PARSE_FAILED。返回 {"errors": Array, "warnings": Array, "checks": Array}。
static func validate_all(tables: Dictionary) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var usable: Array[String] = _check_parsable(tables, errors)
	_check_unique_ids(tables, usable, errors)
	_check_required_fields(tables, usable, errors)
	_check_enums(tables, usable, errors)
	_check_cross_references(tables, usable, errors)
	_check_asset_paths(tables, usable, errors, warnings)
	_check_counts(tables, usable, errors)
	_check_recipe_triples(tables, usable, errors)
	_check_mentor_prompts(tables, usable, errors)
	_check_ui_strings(tables, usable, errors)
	return {"errors": errors, "warnings": warnings, "checks": CHECK_IDS.duplicate()}


# AC2：零 error 退出码 0，有 error 退出码 1。
static func exit_code_for(errors: Array) -> int:
	return 1 if errors.size() > 0 else 0


# 从 res://data/ 读全部表；缺失或不可解析的记为 PARSE_FAILED（交给第 1 类检查报错）。
# parse_notes 收集"文件名 + 解析错误行"的细节（SPEC-04 §12 第 1 类的失败输出要求）。
static func load_tables(parse_notes: Array = []) -> Dictionary:
	var tables: Dictionary = {}
	for table_name in ARRAY_TABLES:
		tables[table_name] = _read_json(table_name, parse_notes)
	for table_name in OBJECT_TABLES:
		tables[table_name] = _read_json(table_name, parse_notes)
	return tables


# ------------------------------------------------------------- 通用小工具 ----
static func _read_json(file_name: String, parse_notes: Array) -> Variant:
	var path: String = DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		parse_notes.append("%s：文件不存在（%s）" % [file_name, path])
		return PARSE_FAILED
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		parse_notes.append(
			"%s：JSON 解析失败，第 %d 行——%s"
			% [file_name, json.get_error_line(), json.get_error_message()]
		)
		return PARSE_FAILED
	return json.data


static func _id_of(row: Dictionary) -> String:
	return str(row.get(F_ID, ""))


# 空判定：字符串去空白后为空、数组/字典为空、null 都算空（第 3 类检查用）。
static func _is_blank(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return true
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).strip_edges().is_empty()
		TYPE_ARRAY:
			return (value as Array).is_empty()
		TYPE_DICTIONARY:
			return (value as Dictionary).is_empty()
	return false


static func _rows(tables: Dictionary, table_name: String) -> Array:
	return tables.get(table_name, []) as Array


static func _ids_of(tables: Dictionary, usable: Array[String], table_name: String) -> Dictionary:
	var ids: Dictionary = {}
	if not usable.has(table_name):
		return ids
	for row in _rows(tables, table_name):
		ids[_id_of(row as Dictionary)] = true
	return ids


# 点分键在 balance.json 中的解析（第 5 类 effect_value_key 用）。
static func _dig(data: Variant, dotted_key: String) -> Variant:
	var cursor: Variant = data
	for part in dotted_key.split("."):
		if typeof(cursor) != TYPE_DICTIONARY:
			return null
		var branch: Dictionary = cursor as Dictionary
		if not branch.has(part):
			return null
		cursor = branch[part]
	return cursor


# --------------------------------------- 第 1 类：每张表 JSON 可解析且类型正确 ----
# 返回"可用于后续检查"的表名列表——不可解析的表跳过，避免后续检查刷一堆连带错误。
static func _check_parsable(tables: Dictionary, errors: Array) -> Array[String]:
	var usable: Array[String] = []
	for table_name in ARRAY_TABLES:
		if _check_one_parsable(tables, table_name, TYPE_ARRAY, errors):
			usable.append(table_name)
	for table_name in OBJECT_TABLES:
		if _check_one_parsable(tables, table_name, TYPE_DICTIONARY, errors):
			usable.append(table_name)
	return usable


static func _check_one_parsable(
	tables: Dictionary, table_name: String, expected_type: int, errors: Array
) -> bool:
	if not tables.has(table_name):
		errors.append("%s：表缺失，无法解析" % table_name)
		return false
	var value: Variant = tables[table_name]
	if typeof(value) == TYPE_STRING and str(value) == PARSE_FAILED:
		errors.append("%s：JSON 不可解析" % table_name)
		return false
	if typeof(value) != expected_type:
		errors.append(
			"%s：顶层类型不符，期望 %s，实际 %s"
			% [table_name, type_string(expected_type), type_string(typeof(value))]
		)
		return false
	if expected_type == TYPE_ARRAY:
		for i in range((value as Array).size()):
			if typeof((value as Array)[i]) != TYPE_DICTIONARY:
				errors.append("%s：第 %d 项不是对象" % [table_name, i])
				return false
	return true


# ---------------------------------------------- 第 2 类：id 全表唯一 ----
static func _check_unique_ids(tables: Dictionary, usable: Array[String], errors: Array) -> void:
	for table_name in ARRAY_TABLES:
		if not usable.has(table_name):
			continue
		var seen: Dictionary = {}
		for row in _rows(tables, table_name):
			var id: String = _id_of(row as Dictionary)
			if seen.has(id):
				errors.append("%s：重复 id「%s」" % [table_name, id])
			seen[id] = true


# ------------------------------------------ 第 3 类：必填字段非空 ----
static func _check_required_fields(
	tables: Dictionary, usable: Array[String], errors: Array
) -> void:
	for table_name in REQUIRED_FIELDS:
		if not usable.has(table_name):
			continue
		var fields: Array = REQUIRED_FIELDS[table_name] as Array
		for row_value in _rows(tables, table_name):
			var row: Dictionary = row_value as Dictionary
			var id: String = _id_of(row)
			for field in fields:
				var field_name: String = str(field)
				if not row.has(field_name):
					errors.append(
						"%s：id「%s」缺少必填字段「%s」" % [table_name, id, field_name]
					)
				elif _is_blank(row[field_name]):
					errors.append(
						"%s：id「%s」的必填字段「%s」为空" % [table_name, id, field_name]
					)
	_check_worldmap_conditional_fields(tables, usable, errors)


# worldmap：解锁项 brief 非空，未解锁项 teaser 非空（SPEC-04 §8）。
static func _check_worldmap_conditional_fields(
	tables: Dictionary, usable: Array[String], errors: Array
) -> void:
	if not usable.has(T_WORLDMAP):
		return
	for row_value in _rows(tables, T_WORLDMAP):
		var row: Dictionary = row_value as Dictionary
		var id: String = _id_of(row)
		var field_name: String = F_BRIEF if bool(row.get(F_UNLOCKED, false)) else F_TEASER
		if _is_blank(row.get(field_name, null)):
			errors.append("%s：id「%s」的必填字段「%s」为空" % [T_WORLDMAP, id, field_name])


# ------------------------------------------------ 第 4 类：枚举值合法 ----
static func _check_enums(tables: Dictionary, usable: Array[String], errors: Array) -> void:
	for table_name in ENUM_FIELDS:
		if not usable.has(table_name):
			continue
		var field_rules: Dictionary = ENUM_FIELDS[table_name] as Dictionary
		for row_value in _rows(tables, table_name):
			var row: Dictionary = row_value as Dictionary
			for field in field_rules:
				var field_name: String = str(field)
				if not row.has(field_name):
					continue
				var allowed: Array = field_rules[field_name] as Array
				var actual: String = str(row[field_name])
				if not allowed.has(actual):
					errors.append(_enum_error(table_name, _id_of(row), field_name, actual, allowed))
	_check_array_enums(tables, usable, errors)
	_check_mentor_id_enum(tables, usable, errors)


static func _check_array_enums(tables: Dictionary, usable: Array[String], errors: Array) -> void:
	for table_name in ARRAY_ENUM_FIELDS:
		if not usable.has(table_name):
			continue
		var field_rules: Dictionary = ARRAY_ENUM_FIELDS[table_name] as Dictionary
		for row_value in _rows(tables, table_name):
			var row: Dictionary = row_value as Dictionary
			for field in field_rules:
				var field_name: String = str(field)
				if typeof(row.get(field_name, null)) != TYPE_ARRAY:
					continue
				var allowed: Array = field_rules[field_name] as Array
				for entry in (row[field_name] as Array):
					var actual: String = str(entry)
					if not allowed.has(actual):
						errors.append(
							_enum_error(table_name, _id_of(row), field_name, actual, allowed)
						)


# qa_fallback 的 mentor_id 取值必须是 mentors 表的 id（枚举来源是数据本身，不写死）。
static func _check_mentor_id_enum(
	tables: Dictionary, usable: Array[String], errors: Array
) -> void:
	if not usable.has(T_QA) or not usable.has(T_MENTORS):
		return
	var mentor_ids: Dictionary = _ids_of(tables, usable, T_MENTORS)
	for row_value in _rows(tables, T_QA):
		var row: Dictionary = row_value as Dictionary
		var actual: String = str(row.get(F_MENTOR_ID, ""))
		if not mentor_ids.has(actual):
			errors.append(
				_enum_error(T_QA, _id_of(row), F_MENTOR_ID, actual, mentor_ids.keys())
			)


static func _enum_error(
	table_name: String, id: String, field_name: String, actual: String, allowed: Array
) -> String:
	return (
		"%s：id「%s」的字段「%s」取值「%s」非法，允许值 %s"
		% [table_name, id, field_name, actual, str(allowed)]
	)


# ----------------------------- 第 5 类：交叉引用存在（来源表 + id + 目标表 + 缺失 id）----
static func _check_cross_references(
	tables: Dictionary, usable: Array[String], errors: Array
) -> void:
	var tip_ids: Dictionary = _ids_of(tables, usable, T_TIPS)
	var craftables: Dictionary = _ids_of(tables, usable, T_SUBSTANCES)
	for item_id in _ids_of(tables, usable, T_ITEMS):
		craftables[item_id] = true

	if usable.has(T_TIPS):
		_check_reference_field(tables, usable, T_SUBSTANCES, F_TIP_ID, tip_ids, T_TIPS, errors)
		_check_reference_field(tables, usable, T_ITEMS, F_TIP_ID, tip_ids, T_TIPS, errors)
		_check_reference_field(tables, usable, T_RECIPES, F_UNLOCK_TIP, tip_ids, T_TIPS, errors)
	if usable.has(T_RECIPES) and usable.has(T_SUBSTANCES) and usable.has(T_ITEMS):
		for field_name in [F_INPUTS, F_OUTPUTS]:
			_check_reference_array(tables, T_RECIPES, str(field_name), craftables, errors)
	_check_effect_value_keys(tables, usable, errors)


# 单值引用字段：字段缺失或为空视为"未填"，跳过（必填性由第 3 类负责）。
static func _check_reference_field(
	tables: Dictionary,
	usable: Array[String],
	table_name: String,
	field_name: String,
	target_ids: Dictionary,
	target_table: String,
	errors: Array
) -> void:
	if not usable.has(table_name):
		return
	for row_value in _rows(tables, table_name):
		var row: Dictionary = row_value as Dictionary
		var reference: String = str(row.get(field_name, ""))
		if reference.is_empty():
			continue
		if not target_ids.has(reference):
			errors.append(
				_reference_error(table_name, _id_of(row), field_name, target_table, reference)
			)


static func _check_reference_array(
	tables: Dictionary,
	table_name: String,
	field_name: String,
	target_ids: Dictionary,
	errors: Array
) -> void:
	for row_value in _rows(tables, table_name):
		var row: Dictionary = row_value as Dictionary
		if typeof(row.get(field_name, null)) != TYPE_ARRAY:
			continue
		for entry in (row[field_name] as Array):
			var reference: String = str(entry)
			if not target_ids.has(reference):
				errors.append(
					_reference_error(
						table_name,
						_id_of(row),
						field_name,
						"%s / %s" % [T_SUBSTANCES, T_ITEMS],
						reference
					)
				)


# items.effect_value_key 必须能在 balance.json 中解析到（FR-G-12 AC1）。
static func _check_effect_value_keys(
	tables: Dictionary, usable: Array[String], errors: Array
) -> void:
	if not usable.has(T_ITEMS) or not usable.has(T_BALANCE):
		return
	var balance: Dictionary = tables[T_BALANCE] as Dictionary
	for row_value in _rows(tables, T_ITEMS):
		var row: Dictionary = row_value as Dictionary
		var dotted_key: String = str(row.get(F_EFFECT_VALUE_KEY, ""))
		if dotted_key.is_empty():
			continue
		if _dig(balance, dotted_key) == null:
			errors.append(
				_reference_error(T_ITEMS, _id_of(row), F_EFFECT_VALUE_KEY, T_BALANCE, dotted_key)
			)


static func _reference_error(
	table_name: String, id: String, field_name: String, target: String, reference: String
) -> String:
	return (
		"%s：id「%s」的字段「%s」引用的「%s」在 %s 中不存在"
		% [table_name, id, field_name, reference, target]
	)


# ------------------------------------------------- 第 6 类：资源路径 ----
# 路径必须在 res://assets/ 下且扩展名合法（否则 error）；文件不存在只 warning（见文件头说明）。
static func _check_asset_paths(
	tables: Dictionary, usable: Array[String], errors: Array, warnings: Array
) -> void:
	for table_name in ASSET_FIELDS:
		if not usable.has(table_name):
			continue
		var fields: Array = ASSET_FIELDS[table_name] as Array
		for row_value in _rows(tables, table_name):
			var row: Dictionary = row_value as Dictionary
			for field in fields:
				var field_name: String = str(field)
				var path: String = str(row.get(field_name, ""))
				if path.is_empty():
					continue
				_check_asset_path(table_name, _id_of(row), field_name, path, errors, warnings)


static func _check_asset_path(
	table_name: String,
	id: String,
	field_name: String,
	path: String,
	errors: Array,
	warnings: Array
) -> void:
	if not path.begins_with(ASSET_PREFIX):
		errors.append(
			"%s：id「%s」的字段「%s」路径「%s」不在 %s 下"
			% [table_name, id, field_name, path, ASSET_PREFIX]
		)
		return
	if not ASSET_EXTENSIONS.has(path.get_extension().to_lower()):
		errors.append(
			"%s：id「%s」的字段「%s」路径「%s」扩展名非法，允许 %s"
			% [table_name, id, field_name, path, str(ASSET_EXTENSIONS)]
		)
		return
	# P4 美术未交付前，文件缺失只警告——收紧为 error 就改这一处。
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		warnings.append(
			"%s：id「%s」的字段「%s」路径「%s」文件尚不存在（P4 未交付，仅警告）"
			% [table_name, id, field_name, path]
		)


# ------------------------------------------------- 第 7 类：条数约束 ----
static func _check_counts(tables: Dictionary, usable: Array[String], errors: Array) -> void:
	for table_name in EXACT_COUNTS:
		if not usable.has(table_name):
			continue
		var expected: int = int(EXACT_COUNTS[table_name])
		var actual: int = _rows(tables, table_name).size()
		if actual != expected:
			errors.append(_count_error(table_name, SUBJECT_ROW_COUNT, expected, actual))

	if usable.has(T_SUBSTANCES):
		var in_hud: int = 0
		for row_value in _rows(tables, T_SUBSTANCES):
			if bool((row_value as Dictionary).get(F_COUNT_IN_HUD, true)):
				in_hud += 1
		if in_hud != COUNT_SUBSTANCES_IN_HUD:
			errors.append(
				_count_error(T_SUBSTANCES, F_COUNT_IN_HUD, COUNT_SUBSTANCES_IN_HUD, in_hud)
			)

	if usable.has(T_WORLDMAP):
		var unlocked: int = 0
		for row_value in _rows(tables, T_WORLDMAP):
			if bool((row_value as Dictionary).get(F_UNLOCKED, false)):
				unlocked += 1
		if unlocked != COUNT_WORLDMAP_UNLOCKED:
			errors.append(
				_count_error(T_WORLDMAP, F_UNLOCKED, COUNT_WORLDMAP_UNLOCKED, unlocked)
			)

	if usable.has(T_QA):
		var qa_count: int = _rows(tables, T_QA).size()
		if qa_count < COUNT_QA_MIN:
			errors.append(_count_error(T_QA, SUBJECT_MIN_ROW_COUNT, COUNT_QA_MIN, qa_count))
		_check_qa_keywords(tables, errors)

	if usable.has(T_RECIPES):
		var pure_checks: int = 0
		for row_value in _rows(tables, T_RECIPES):
			if bool((row_value as Dictionary).get(F_REQUIRES_PURE_CHECK, false)):
				pure_checks += 1
		if pure_checks != COUNT_PURE_CHECK_RECIPES:
			errors.append(
				_count_error(
					T_RECIPES, F_REQUIRES_PURE_CHECK, COUNT_PURE_CHECK_RECIPES, pure_checks
				)
			)

	_check_fail_message_pools(tables, usable, errors)


# SPEC-04 §7：keywords 必须是数组；恰好一行为空数组（零命中兜底行，答案因此不必硬编码
# 进代码，NFR-04）；其余行 ≥1 项且无空串（空串会命中任何文本，让匹配失去意义）。
static func _check_qa_keywords(tables: Dictionary, errors: Array) -> void:
	var fallback_rows: int = 0
	for row_value in _rows(tables, T_QA):
		var row: Dictionary = row_value as Dictionary
		var id: String = _id_of(row)
		if not row.has(F_KEYWORDS):
			errors.append("%s：id「%s」缺少必填字段「%s」" % [T_QA, id, F_KEYWORDS])
			continue
		if typeof(row[F_KEYWORDS]) != TYPE_ARRAY:
			errors.append("%s：id「%s」的「%s」应为数组" % [T_QA, id, F_KEYWORDS])
			continue
		var keywords: Array = row[F_KEYWORDS] as Array
		if keywords.is_empty():
			fallback_rows += 1
			continue
		for keyword_value in keywords:
			if str(keyword_value).strip_edges().is_empty():
				errors.append("%s：id「%s」的「%s」含空关键词" % [T_QA, id, F_KEYWORDS])
	if fallback_rows != COUNT_QA_FALLBACK_ROWS:
		errors.append(
			_count_error(T_QA, F_KEYWORDS, COUNT_QA_FALLBACK_ROWS, fallback_rows)
		)


# 每个 reason 池至少 2 条，否则"连续两次同类失败文案不同"不可满足（FR-G-07 AC2 判定口径）。
static func _check_fail_message_pools(
	tables: Dictionary, usable: Array[String], errors: Array
) -> void:
	if not usable.has(T_FAIL_MESSAGES):
		return
	var by_reason: Dictionary = {}
	for reason in FAIL_REASONS:
		by_reason[reason] = 0
	for row_value in _rows(tables, T_FAIL_MESSAGES):
		var reason: String = str((row_value as Dictionary).get(F_REASON, ""))
		if by_reason.has(reason):
			by_reason[reason] = int(by_reason[reason]) + 1
	for reason in by_reason:
		var actual: int = int(by_reason[reason])
		if actual < MIN_FAIL_MESSAGES_PER_REASON:
			errors.append(
				_count_error(
					T_FAIL_MESSAGES,
					SUBJECT_FAIL_POOL_FORMAT % [F_REASON, str(reason)],
					MIN_FAIL_MESSAGES_PER_REASON,
					actual
				)
			)


static func _count_error(table_name: String, subject: String, expected: int, actual: int) -> String:
	return "%s：%s 期望 %d，实际 %d" % [table_name, subject, expected, actual]


# --------------------------- 第 8 类：配方三元组无歧义（报冲突的两个 recipe id）----
static func _check_recipe_triples(
	tables: Dictionary, usable: Array[String], errors: Array
) -> void:
	if not usable.has(T_RECIPES):
		return
	var seen: Dictionary = {}
	for row_value in _rows(tables, T_RECIPES):
		var row: Dictionary = row_value as Dictionary
		var id: String = _id_of(row)
		var inputs: Array = []
		if typeof(row.get(F_INPUTS, null)) == TYPE_ARRAY:
			inputs = (row[F_INPUTS] as Array).duplicate()
		inputs.sort()
		var key: String = "%s|%s|%s" % [str(inputs), str(row.get(F_TOOL, "")), str(row.get(F_CONDITION, ""))]
		if seen.has(key):
			errors.append(
				"%s：三元组（%s / %s / %s）歧义，「%s」与「%s」撞车"
				% [
					T_RECIPES,
					str(inputs),
					str(row.get(F_TOOL, "")),
					str(row.get(F_CONDITION, "")),
					str(seen[key]),
					id,
				]
			)
		else:
			seen[key] = id


# ----------- 第 9 类：monitor prompt 含调度关键字；其余三位含"绝不出现 @" ----
static func _check_mentor_prompts(
	tables: Dictionary, usable: Array[String], errors: Array
) -> void:
	if not usable.has(T_MENTORS):
		return
	for row_value in _rows(tables, T_MENTORS):
		var row: Dictionary = row_value as Dictionary
		var id: String = _id_of(row)
		var prompt: String = str(row.get(F_SYSTEM_PROMPT, ""))
		if id == MONITOR_ID:
			for keyword in DISPATCH_KEYWORDS:
				if not prompt.contains(keyword):
					errors.append(
						"%s：导师 id「%s」的 %s 缺调度关键字「%s」"
						% [T_MENTORS, id, F_SYSTEM_PROMPT, keyword]
					)
		elif not prompt.contains(NO_AT_CLAUSE):
			errors.append(
				"%s：导师 id「%s」的 %s 缺约束「%s」"
				% [T_MENTORS, id, F_SYSTEM_PROMPT, NO_AT_CLAUSE]
			)
	_check_mentions(tables, errors)
	_check_dispatch(tables, errors)


# SPEC-04 §5：mention 是 parse_mentions 的 @句柄 → 导师 id 映射来源。
# 必须非空、不自带 @、全表唯一（重复会让映射有歧义）。
static func _check_mentions(tables: Dictionary, errors: Array) -> void:
	var seen: Dictionary = {}
	for row_value in _rows(tables, T_MENTORS):
		var row: Dictionary = row_value as Dictionary
		var id: String = _id_of(row)
		var mention: String = str(row.get(F_MENTION, "")).strip_edges()
		if mention.is_empty():
			# 缺失/为空已由第 3 类必填检查报出，这里不重复计数。
			continue
		if mention.begins_with(AT_SIGN):
			errors.append(
				"%s：导师 id「%s」的 %s 不该自带「%s」：%s"
				% [T_MENTORS, id, F_MENTION, AT_SIGN, mention]
			)
		if seen.has(mention):
			errors.append(
				"%s：%s「%s」重复，导师「%s」与「%s」撞车"
				% [T_MENTORS, F_MENTION, mention, str(seen[mention]), id]
			)
		else:
			seen[mention] = id


# SPEC-04 §5：仅 monitor 有 dispatch；四类齐全且顺序即优先级；
# targets 存在、不含 monitor、数量合规；line 含每个 target 的 @mention；
# 除兜底类外 keywords 非空。
static func _check_dispatch(tables: Dictionary, errors: Array) -> void:
	var mention_of: Dictionary = {}
	var monitor_row: Dictionary = {}
	for row_value in _rows(tables, T_MENTORS):
		var row: Dictionary = row_value as Dictionary
		var id: String = _id_of(row)
		mention_of[id] = str(row.get(F_MENTION, "")).strip_edges()
		if id == MONITOR_ID:
			monitor_row = row
		elif row.has(F_DISPATCH):
			errors.append(
				"%s：导师 id「%s」不该有 %s 字段（仅「%s」有）"
				% [T_MENTORS, id, F_DISPATCH, MONITOR_ID]
			)
	if monitor_row.is_empty():
		return
	if not monitor_row.has(F_DISPATCH):
		errors.append("%s：导师 id「%s」缺 %s 字段" % [T_MENTORS, MONITOR_ID, F_DISPATCH])
		return
	var entries: Array = monitor_row.get(F_DISPATCH, []) as Array
	if entries.size() != DISPATCH_CATEGORIES.size():
		errors.append(
			"%s：导师 id「%s」的 %s 应恰好 %d 项，实际 %d 项"
			% [T_MENTORS, MONITOR_ID, F_DISPATCH, DISPATCH_CATEGORIES.size(), entries.size()]
		)
	for i in range(entries.size()):
		_check_dispatch_entry(entries[i], i, mention_of, errors)


# 单项 dispatch 校验。index 参与判定：数组顺序即分类优先级。
static func _check_dispatch_entry(
	entry_value: Variant, index: int, mention_of: Dictionary, errors: Array
) -> void:
	if typeof(entry_value) != TYPE_DICTIONARY:
		errors.append(
			"%s：导师 id「%s」的 %s[%d] 不是对象"
			% [T_MENTORS, MONITOR_ID, F_DISPATCH, index]
		)
		return
	var entry: Dictionary = entry_value as Dictionary
	var category: String = str(entry.get(F_CATEGORY, ""))
	if index < DISPATCH_CATEGORIES.size() and category != DISPATCH_CATEGORIES[index]:
		errors.append(
			"%s：导师 id「%s」的 %s 顺序即优先级，第 %d 项应为「%s」，实际「%s」"
			% [
				T_MENTORS, MONITOR_ID, F_DISPATCH, index + 1,
				DISPATCH_CATEGORIES[index], category,
			]
		)
	for field in DISPATCH_FIELDS:
		if not entry.has(field):
			errors.append(
				"%s：导师 id「%s」的 %s[%s] 缺字段「%s」"
				% [T_MENTORS, MONITOR_ID, F_DISPATCH, category, field]
			)
	_check_dispatch_keywords(entry, category, errors)
	_check_dispatch_targets(entry, category, mention_of, errors)


# 兜底类 keywords 必须为空（它靠兜底命中）；其余类必须非空，否则该类永不命中。
static func _check_dispatch_keywords(entry: Dictionary, category: String, errors: Array) -> void:
	var keywords: Array = entry.get(F_KEYWORDS, []) as Array
	var is_fallback: bool = category == DISPATCH_FALLBACK_CATEGORY
	if is_fallback:
		if not keywords.is_empty():
			errors.append(
				"%s：导师 id「%s」的 %s[%s] 是兜底类，%s 应为空数组"
				% [T_MENTORS, MONITOR_ID, F_DISPATCH, category, F_KEYWORDS]
			)
		return
	if keywords.is_empty():
		errors.append(
			"%s：导师 id「%s」的 %s[%s] 的 %s 不许为空（该类永不命中）"
			% [T_MENTORS, MONITOR_ID, F_DISPATCH, category, F_KEYWORDS]
		)
		return
	for keyword in keywords:
		if str(keyword).strip_edges().is_empty():
			errors.append(
				"%s：导师 id「%s」的 %s[%s] 的 %s 含空关键词"
				% [T_MENTORS, MONITOR_ID, F_DISPATCH, category, F_KEYWORDS]
			)


# targets 非空、≤2 项、id 存在、不含 monitor；line 含每个 target 的 @mention。
static func _check_dispatch_targets(
	entry: Dictionary, category: String, mention_of: Dictionary, errors: Array
) -> void:
	var targets: Array = entry.get(F_TARGETS, []) as Array
	var line: String = str(entry.get(F_LINE, ""))
	if targets.is_empty():
		errors.append(
			"%s：导师 id「%s」的 %s[%s] 的 %s 不许为空"
			% [T_MENTORS, MONITOR_ID, F_DISPATCH, category, F_TARGETS]
		)
	if targets.size() > DISPATCH_TARGETS_MAX:
		errors.append(
			"%s：导师 id「%s」的 %s[%s] 的 %s 最多 %d 项，实际 %d 项"
			% [
				T_MENTORS, MONITOR_ID, F_DISPATCH, category, F_TARGETS,
				DISPATCH_TARGETS_MAX, targets.size(),
			]
		)
	if DISPATCH_EXACT_TARGETS.has(category):
		var expected: int = int(DISPATCH_EXACT_TARGETS[category])
		if targets.size() != expected:
			errors.append(
				"%s：导师 id「%s」的 %s[%s] 的 %s 应恰好 %d 项，实际 %d 项"
				% [
					T_MENTORS, MONITOR_ID, F_DISPATCH, category, F_TARGETS,
					expected, targets.size(),
				]
			)
	for target in targets:
		var target_id: String = str(target)
		if not mention_of.has(target_id):
			errors.append(
				"%s：导师 id「%s」的 %s[%s] 的 %s 指向不存在的导师「%s」"
				% [T_MENTORS, MONITOR_ID, F_DISPATCH, category, F_TARGETS, target_id]
			)
			continue
		if target_id == MONITOR_ID:
			errors.append(
				"%s：导师 id「%s」的 %s[%s] 的 %s 不许派给班主任自己"
				% [T_MENTORS, MONITOR_ID, F_DISPATCH, category, F_TARGETS]
			)
			continue
		var handle: String = AT_SIGN + str(mention_of[target_id])
		if not line.contains(handle):
			errors.append(
				"%s：导师 id「%s」的 %s[%s] 的 %s 缺「%s」：%s"
				% [T_MENTORS, MONITOR_ID, F_DISPATCH, category, F_LINE, handle, line]
			)


# ------------- 第 10 类：ui_strings 覆盖 SPEC-05 §9 全部 key，占位符仅 {n} ----
static func _check_ui_strings(tables: Dictionary, usable: Array[String], errors: Array) -> void:
	if not usable.has(T_UI_STRINGS):
		return
	var strings: Dictionary = tables[T_UI_STRINGS] as Dictionary
	for key in UI_STRING_KEYS:
		if not strings.has(key):
			errors.append("%s：缺少 key「%s」" % [T_UI_STRINGS, key])
	var placeholder: RegEx = RegEx.new()
	placeholder.compile(PLACEHOLDER_PATTERN)
	for key in strings:
		var key_name: String = str(key)
		if not UI_STRING_KEYS.has(key_name):
			errors.append("%s：多余 key「%s」不在 SPEC-05 §9 内" % [T_UI_STRINGS, key_name])
			continue
		var value: String = str(strings[key_name])
		if value.strip_edges().is_empty():
			errors.append("%s：key「%s」的 value 为空" % [T_UI_STRINGS, key_name])
			continue
		for found in placeholder.search_all(value):
			var token: String = found.get_string()
			if token != ALLOWED_PLACEHOLDER:
				errors.append(
					"%s：key「%s」含非法占位符「%s」，只允许「%s」"
					% [T_UI_STRINGS, key_name, token, ALLOWED_PLACEHOLDER]
				)


# ----------------------------------------------------- headless 入口 ----
func _initialize() -> void:
	var parse_notes: Array = []
	var tables: Dictionary = load_tables(parse_notes)
	var report: Dictionary = validate_all(tables)
	var errors: Array = report.get("errors", []) as Array
	var warnings: Array = report.get("warnings", []) as Array

	for note in parse_notes:
		print("PARSE: %s" % str(note))
	for warning in warnings:
		print("WARN: %s" % str(warning))
	for error in errors:
		printerr("ERROR: %s" % str(error))

	var code: int = exit_code_for(errors)
	if code == 0:
		print(OK_MESSAGE)
	else:
		printerr("%s：%d 条 error" % [DATA_DIR, errors.size()])
	quit(code)
