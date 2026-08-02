# UT-D04 / FR-D-04：mentors.json 恰好 4 条、id 集合正确、必填字段齐全、
# monitor prompt 含三个 @ 关键字、其余三位含"绝不出现 @"。
# 断言依据：SPEC-04 §5 校验规则 + SPEC-05 §4 人设终稿。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const EXPECTED_COUNT: int = 4
const MONITOR_ID: String = "monitor"
const EXPECTED_IDS: Array[String] = ["chem", "monitor", "assistant", "think"]
const ROUTE_CLASSES: Array[String] = ["chemistry", "dispatch", "planning", "thinking"]
const REQUIRED_FIELDS: Array[String] = [
	"id", "name", "title", "room", "avatar_idle", "avatar_talk",
	"sprite", "route_class", "system_prompt",
]
const ASSET_PREFIX: String = "res://assets/"
const NO_AT_CLAUSE: String = "回答里绝不出现 @。"
const DISPATCH_KEYWORDS: Array[String] = ["@化学老师", "@思维老师", "@助理"]

# SPEC-04 §5：@ 句柄字段。title 不能当句柄（think 的 title 是「实用思维老师」）。
const SPEC_MENTIONS: Dictionary = {
	"chem": "化学老师",
	"monitor": "班主任",
	"assistant": "助理",
	"think": "思维老师",
}

# SPEC-04 §5 monitor.dispatch：数组顺序即分类优先级。
const DISPATCH_CATEGORIES: Array[String] = ["combat", "learning", "chemistry", "other"]
const DISPATCH_TARGETS: Dictionary = {
	"combat": ["think"],
	"learning": ["think", "assistant"],
	"chemistry": ["chem"],
	"other": ["assistant"],
}
const DISPATCH_FIELDS: Array[String] = ["category", "keywords", "targets", "line"]

# SPEC-05 §4.2：id -> [name, title, room, route_class]。
const SPEC_PROFILES: Dictionary = {
	"chem": ["袁仲衡", "化学老师", "化学实验室", "chemistry"],
	"monitor": ["苏婉清", "班主任", "班主任办公室", "dispatch"],
	"assistant": ["周启明", "助理", "自习室", "planning"],
	"think": ["曲嫣然", "实用思维老师", "思维工坊", "thinking"],
}

# SPEC-05 §4.2 口头禅。
const SPEC_CATCHPHRASES: Dictionary = {
	"chem": ["配平了吗？", "万物皆由元素构成。"],
	"monitor": ["别慌，这件事我来安排。", "该找谁，我清楚。"],
	"assistant": ["先别急，我给你列个三步计划。", "今天只做这一格，做到了就算赢。"],
	"think": ["别急着背公式，先想想它能在哪儿用。"],
}

var _rows: Array[Dictionary] = []
var _by_id: Dictionary = {}


func before_each() -> void:
	_rows = Fixture.rows_of("mentors.json")
	_by_id = {}
	for row in _rows:
		_by_id[str(row.get("id", ""))] = row


# AC1：恰好 4 条且 id 集合等于 {chem, monitor, assistant, think}。
func test_mentor_count_is_four_with_exact_id_set() -> void:
	assert_eq(_rows.size(), EXPECTED_COUNT, "mentors.json 必须恰好 4 条")
	for id in EXPECTED_IDS:
		assert_true(_by_id.has(id), "导师 id 缺失：%s" % id)
	assert_eq(_by_id.size(), EXPECTED_IDS.size(), "导师 id 集合与 SPEC-04 §5 不一致")


# AC2：每位有 name/title/room/avatar_idle/avatar_talk/route_class/system_prompt。
func test_required_fields_present_and_non_empty() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		for field in REQUIRED_FIELDS:
			assert_true(row.has(field), "%s 缺字段 %s" % [id, field])
			assert_false(str(row.get(field, "")).is_empty(), "%s 的 %s 为空" % [id, field])


# 姓名/职称/房间/route_class 逐字对齐 SPEC-05 §4.2。
func test_profiles_match_spec_verbatim() -> void:
	for id in SPEC_PROFILES:
		var row: Dictionary = _by_id.get(id, {})
		assert_false(row.is_empty(), "导师 %s 不存在" % id)
		var expected: Array = SPEC_PROFILES[id]
		assert_eq(str(row.get("name", "")), str(expected[0]), "%s 的 name 与 SPEC-05 §4.2 不一致" % id)
		assert_eq(str(row.get("title", "")), str(expected[1]), "%s 的 title 与 SPEC-05 §4.2 不一致" % id)
		assert_eq(str(row.get("room", "")), str(expected[2]), "%s 的 room 与 SPEC-05 §4.2 不一致" % id)
		assert_eq(
			str(row.get("route_class", "")), str(expected[3]),
			"%s 的 route_class 与 SPEC-05 §4.2 不一致" % id
		)


# route_class 在枚举内且四位互不重复。
func test_route_classes_in_enum_and_distinct() -> void:
	var seen: Dictionary = {}
	for row in _rows:
		var route_class: String = str(row.get("route_class", ""))
		assert_true(
			ROUTE_CLASSES.has(route_class),
			"%s 的 route_class 非法：%s" % [str(row.get("id", "")), route_class]
		)
		assert_false(seen.has(route_class), "route_class 重复：%s" % route_class)
		seen[route_class] = true


# 口头禅逐字对齐 SPEC-05 §4.2（离线模式拼接要用）。
func test_catchphrases_match_spec_verbatim() -> void:
	for id in SPEC_CATCHPHRASES:
		var row: Dictionary = _by_id.get(id, {})
		var expected: Array = SPEC_CATCHPHRASES[id]
		var actual: Array = row.get("catchphrases", []) as Array
		assert_eq(actual.size(), expected.size(), "%s 的 catchphrases 条数与 SPEC-05 §4.2 不一致" % id)
		for i in range(mini(actual.size(), expected.size())):
			assert_eq(str(actual[i]), str(expected[i]), "%s 的第 %d 条口头禅不一致" % [id, i + 1])


# AC3：monitor 的 prompt 含三个调度关键字（SPEC-04 §5 校验规则）。
func test_monitor_prompt_contains_dispatch_keywords() -> void:
	var prompt: String = str(_by_id.get(MONITOR_ID, {}).get("system_prompt", ""))
	assert_false(prompt.is_empty(), "monitor 的 system_prompt 为空")
	for keyword in DISPATCH_KEYWORDS:
		assert_true(prompt.contains(keyword), "monitor 的 prompt 缺调度关键字：%s" % keyword)


# AC3：非 monitor 的三位 prompt 含"绝不出现 @"约束（FR-M-06 AC2）。
func test_non_monitor_prompts_forbid_at_mentions() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		if id == MONITOR_ID:
			continue
		var prompt: String = str(row.get("system_prompt", ""))
		assert_true(prompt.contains(NO_AT_CLAUSE), "%s 的 prompt 缺「%s」约束" % [id, NO_AT_CLAUSE])


# 只有 monitor 的 prompt 允许出现 @ 调度语（机制二：只有班主任能 @）。
func test_only_monitor_prompt_uses_at_dispatch() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		if id == MONITOR_ID:
			continue
		var prompt: String = str(row.get("system_prompt", ""))
		for keyword in DISPATCH_KEYWORDS:
			assert_false(prompt.contains(keyword), "%s 的 prompt 不该含调度语 %s" % [id, keyword])


# 立绘与像素小人路径在 res://assets/ 下（文件缺失由校验器 warning，见 validate_data.gd 顶部说明）。
func test_avatar_and_sprite_paths_under_assets() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		for field in ["avatar_idle", "avatar_talk", "sprite"]:
			var path: String = str(row.get(field, ""))
			assert_true(
				path.begins_with(ASSET_PREFIX),
				"%s 的 %s 必须以 %s 开头：%s" % [id, field, ASSET_PREFIX, path]
			)
			assert_eq(path.get_extension().to_lower(), "png", "%s 的 %s 扩展名应为 png" % [id, field])


# SPEC-04 §5：mention 四条齐全、非空、唯一、不以 @ 开头，取值与 SPEC-05 §4.1/§4.3 一致。
func test_mention_handles_match_spec_and_are_unique() -> void:
	var seen: Dictionary = {}
	for row in _rows:
		var id: String = str(row.get("id", ""))
		assert_true(row.has("mention"), "%s 缺 mention 字段（parse_mentions 的映射来源）" % id)
		var mention: String = str(row.get("mention", ""))
		assert_false(mention.strip_edges().is_empty(), "%s 的 mention 不许为空" % id)
		assert_false(mention.begins_with("@"), "%s 的 mention 不该自带 @：%s" % [id, mention])
		assert_eq(mention, str(SPEC_MENTIONS.get(id, "")), "%s 的 mention 与 SPEC-04 §5 不符" % id)
		assert_false(seen.has(mention), "mention 重复：%s" % mention)
		seen[mention] = id
	assert_eq(seen.size(), EXPECTED_COUNT, "四个 mention 必须互不相同")


# SPEC-04 §5：只有 monitor 有 dispatch，四类齐全且顺序即优先级。
func test_monitor_dispatch_covers_four_categories_in_priority_order() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		if id != MONITOR_ID:
			assert_false(row.has("dispatch"), "%s 不该有 dispatch 字段（仅 monitor 有）" % id)
			continue
		assert_true(row.has("dispatch"), "monitor 必须有 dispatch 字段（FR-M-04 落地口径）")
		var dispatch: Array = row.get("dispatch", []) as Array
		assert_eq(dispatch.size(), DISPATCH_CATEGORIES.size(), "dispatch 应恰好 4 项")
		var actual: Array[String] = []
		for entry_value in dispatch:
			actual.append(str((entry_value as Dictionary).get("category", "")))
		assert_eq(actual, DISPATCH_CATEGORIES, "dispatch 顺序即分类优先级，必须与 SPEC-05 §4.1 一致")


# SPEC-04 §5：每项字段齐全；targets 合法且不含 monitor；learning 恰好两位。
func test_dispatch_entries_have_valid_targets() -> void:
	for entry in _dispatch_entries():
		var category: String = str(entry.get("category", ""))
		for field in DISPATCH_FIELDS:
			assert_true(entry.has(field), "dispatch[%s] 缺字段 %s" % [category, field])
		var targets: Array = entry.get("targets", []) as Array
		assert_false(targets.is_empty(), "dispatch[%s] 的 targets 不许为空" % category)
		assert_true(targets.size() <= 2, "dispatch[%s] 的 targets 最多 2 项" % category)
		for target in targets:
			var target_id: String = str(target)
			assert_true(_by_id.has(target_id), "dispatch[%s] 的 target 不存在：%s" % [category, target_id])
			assert_ne(target_id, MONITOR_ID, "dispatch[%s] 不许派给班主任自己" % category)
		assert_eq(
			targets, DISPATCH_TARGETS.get(category, []),
			"dispatch[%s] 的 targets 与 SPEC-05 §4.1 判断表不符" % category
		)


# SPEC-04 §5：line 非空且含每个 target 的 @mention（离线调度语，SPEC-05 §4.3）。
func test_dispatch_lines_mention_every_target() -> void:
	for entry in _dispatch_entries():
		var category: String = str(entry.get("category", ""))
		var line: String = str(entry.get("line", ""))
		assert_false(line.strip_edges().is_empty(), "dispatch[%s] 的 line 不许为空" % category)
		for target in entry.get("targets", []) as Array:
			var mention: String = "@" + str((_by_id.get(str(target), {}) as Dictionary).get("mention", ""))
			assert_true(line.contains(mention), "dispatch[%s] 的 line 缺 %s：%s" % [category, mention, line])


# 除兜底类 other 外，每项 keywords 非空（否则该类永不命中）。
func test_dispatch_keywords_present_except_fallback() -> void:
	for entry in _dispatch_entries():
		var category: String = str(entry.get("category", ""))
		var keywords: Array = entry.get("keywords", []) as Array
		if category == "other":
			assert_true(keywords.is_empty(), "other 是兜底类，keywords 应为空数组")
			continue
		assert_false(keywords.is_empty(), "dispatch[%s] 的 keywords 不许为空" % category)
		for keyword in keywords:
			assert_false(str(keyword).strip_edges().is_empty(), "dispatch[%s] 含空关键词" % category)


func _dispatch_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var monitor: Dictionary = _by_id.get(MONITOR_ID, {}) as Dictionary
	for entry_value in monitor.get("dispatch", []) as Array:
		if typeof(entry_value) == TYPE_DICTIONARY:
			out.append(entry_value as Dictionary)
	return out
