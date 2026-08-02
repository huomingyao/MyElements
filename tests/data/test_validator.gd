# UT-D07 / FR-D-07：校验器单测。喂入 SPEC-04 §12 的 10 类坏数据，逐类必须报错；
# 真实数据零 error 且退出码 0。
# 资源文件缺失按约定只产生 warning，不进 error、不影响退出码（P4 未开工，见 validate_data.gd 顶部说明）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")
const Validator: GDScript = preload("res://scripts/tools/validate_data.gd")

const ARRAY_TABLES: Array[String] = [
	"substances.json", "recipes.json", "fail_messages.json", "tips.json",
	"mentors.json", "qa_fallback.json", "worldmap.json", "items.json",
]
const OBJECT_TABLES: Array[String] = ["balance.json", "ui_strings.json"]


# 从磁盘读出的真实数据，作为各类坏数据的基线。
func _baseline() -> Dictionary:
	var tables: Dictionary = {}
	for table_name in ARRAY_TABLES:
		tables[table_name] = Fixture.read_array(table_name)
	for table_name in OBJECT_TABLES:
		tables[table_name] = Fixture.read_object(table_name)
	return tables


func _errors_of(tables: Dictionary) -> Array:
	return Validator.validate_all(tables).get("errors", []) as Array


func _warnings_of(tables: Dictionary) -> Array:
	return Validator.validate_all(tables).get("warnings", []) as Array


# 断言错误列表里至少有一条同时提到全部关键片段（表名 / id / 字段）。
func _assert_error_mentions(errors: Array, fragments: Array, context: String) -> void:
	var found: bool = false
	for error in errors:
		var text: String = str(error)
		var all_present: bool = true
		for fragment in fragments:
			if not text.contains(str(fragment)):
				all_present = false
				break
		if all_present:
			found = true
			break
	assert_true(found, "%s：期望错误提到 %s，实际错误列表 %s" % [context, str(fragments), str(errors)])


# 取某表的第一行副本，改一个字段后写回，构造单点坏数据。
func _with_mutated_row(table_name: String, index: int, changes: Dictionary) -> Dictionary:
	var tables: Dictionary = _baseline()
	var rows: Array = (tables[table_name] as Array).duplicate(true)
	var row: Dictionary = (rows[index] as Dictionary).duplicate(true)
	for key in changes:
		row[key] = changes[key]
	rows[index] = row
	tables[table_name] = rows
	return tables


func _row_index_by_id(table_name: String, id: String) -> int:
	var rows: Array = Fixture.read_array(table_name)
	for i in range(rows.size()):
		if str((rows[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


# 好数据：零 error。
func test_real_data_has_no_errors() -> void:
	var errors: Array = _errors_of(_baseline())
	assert_eq(errors.size(), 0, "真实数据不应有 error，实际：%s" % str(errors))


# AC2：零 error 退出码 0，有 error 退出码 1。
func test_exit_code_reflects_error_presence() -> void:
	assert_eq(Validator.exit_code_for([]), 0, "零 error 时退出码应为 0")
	assert_eq(Validator.exit_code_for(["boom"]), 1, "有 error 时退出码应为 1")


# 约定：资源文件缺失只进 warning，不进 error，不影响退出码。
func test_missing_asset_file_is_warning_not_error() -> void:
	var report: Dictionary = Validator.validate_all(_baseline())
	var warnings: Array = report.get("warnings", []) as Array
	assert_gt(warnings.size(), 0, "P4 未开工，图标文件缺失应产生 warning")
	assert_eq((report.get("errors", []) as Array).size(), 0, "资源缺失不该进 error")
	assert_eq(Validator.exit_code_for(report.get("errors", []) as Array), 0, "资源缺失不该影响退出码")


# 第 1 类：JSON 不可解析（顶层类型不符 / 缺表）。
func test_check1_unparsable_table_reports_error() -> void:
	var tables: Dictionary = _baseline()
	tables["substances.json"] = Validator.PARSE_FAILED
	_assert_error_mentions(_errors_of(tables), ["substances.json"], "第 1 类：解析失败")

	var missing: Dictionary = _baseline()
	missing["tips.json"] = Validator.PARSE_FAILED
	_assert_error_mentions(_errors_of(missing), ["tips.json"], "第 1 类：缺表")

	var wrong_type: Dictionary = _baseline()
	wrong_type["ui_strings.json"] = []
	_assert_error_mentions(_errors_of(wrong_type), ["ui_strings.json"], "第 1 类：顶层类型不符")


# 第 2 类：id 全表唯一。
func test_check2_duplicate_id_reports_table_and_id() -> void:
	var tables: Dictionary = _baseline()
	var rows: Array = (tables["substances.json"] as Array).duplicate(true)
	rows.append((rows[0] as Dictionary).duplicate(true))
	tables["substances.json"] = rows
	_assert_error_mentions(_errors_of(tables), ["substances.json", "o2"], "第 2 类：重复 id")


# 第 3 类：必填字段非空（表名 + id + 字段名）。
func test_check3_empty_required_field_reports_table_id_field() -> void:
	var tables: Dictionary = _with_mutated_row("substances.json", 0, {"name": ""})
	_assert_error_mentions(
		_errors_of(tables), ["substances.json", "o2", "name"], "第 3 类：必填字段为空"
	)

	var missing: Dictionary = _baseline()
	var rows: Array = (missing["mentors.json"] as Array).duplicate(true)
	var row: Dictionary = (rows[0] as Dictionary).duplicate(true)
	row.erase("system_prompt")
	rows[0] = row
	missing["mentors.json"] = rows
	_assert_error_mentions(
		_errors_of(missing), ["mentors.json", "chem", "system_prompt"], "第 3 类：必填字段缺失"
	)


# 第 4 类：枚举值合法（表名 + id + 字段 + 实际值）。
func test_check4_invalid_enum_reports_actual_value() -> void:
	var bad_category: Dictionary = _with_mutated_row("substances.json", 0, {"category": "魔法"})
	_assert_error_mentions(
		_errors_of(bad_category), ["substances.json", "o2", "category", "魔法"], "第 4 类：category"
	)

	var tip_index: int = _row_index_by_id("tips.json", "tip_o2")
	var bad_style: Dictionary = _with_mutated_row("tips.json", tip_index, {"style": "toast"})
	_assert_error_mentions(
		_errors_of(bad_style), ["tips.json", "tip_o2", "style", "toast"], "第 4 类：style"
	)

	var recipe_index: int = _row_index_by_id("recipes.json", "r_sulfur_torch")
	var bad_tool: Dictionary = _with_mutated_row("recipes.json", recipe_index, {"tool": "hammer"})
	_assert_error_mentions(
		_errors_of(bad_tool), ["recipes.json", "r_sulfur_torch", "tool", "hammer"], "第 4 类：tool"
	)


# 第 5 类：交叉引用存在（tip_id / inputs / outputs / effect_value_key）。
func test_check5_broken_tip_id_reference_reports_error() -> void:
	var tables: Dictionary = _with_mutated_row("substances.json", 0, {"tip_id": "tip_ghost"})
	_assert_error_mentions(
		_errors_of(tables), ["substances.json", "o2", "tips.json", "tip_ghost"], "第 5 类：tip_id"
	)


func test_check5_broken_recipe_input_output_reports_error() -> void:
	var index: int = _row_index_by_id("recipes.json", "r_sulfur_torch")
	var bad_input: Dictionary = _with_mutated_row("recipes.json", index, {"inputs": ["stick", "unobtainium"]})
	_assert_error_mentions(
		_errors_of(bad_input), ["recipes.json", "r_sulfur_torch", "unobtainium"], "第 5 类：inputs"
	)

	var bad_output: Dictionary = _with_mutated_row("recipes.json", index, {"outputs": ["philosopher_stone"]})
	_assert_error_mentions(
		_errors_of(bad_output), ["recipes.json", "r_sulfur_torch", "philosopher_stone"], "第 5 类：outputs"
	)


func test_check5_broken_effect_value_key_reports_error() -> void:
	var index: int = _row_index_by_id("items.json", "oxygen_tank")
	var tables: Dictionary = _with_mutated_row(
		"items.json", index, {"effect_value_key": "items.no_such_key"}
	)
	_assert_error_mentions(
		_errors_of(tables),
		["items.json", "oxygen_tank", "balance.json", "items.no_such_key"],
		"第 5 类：effect_value_key"
	)


# 第 6 类：资源路径。非法路径（不在 res://assets/ 下或扩展名非法）算 error。
func test_check6_invalid_asset_path_reports_error() -> void:
	var outside: Dictionary = _with_mutated_row("substances.json", 0, {"icon": "res://o2.png"})
	_assert_error_mentions(
		_errors_of(outside), ["substances.json", "o2", "res://o2.png"], "第 6 类：路径不在 assets 下"
	)

	var bad_ext: Dictionary = _with_mutated_row(
		"substances.json", 0, {"icon": "res://assets/art/icons/o2.txt"}
	)
	_assert_error_mentions(
		_errors_of(bad_ext), ["substances.json", "o2", "o2.txt"], "第 6 类：扩展名非法"
	)


# 第 7 类：条数约束（表名 + 期望 + 实际）。
func test_check7_substance_count_violation_reports_expected_and_actual() -> void:
	var tables: Dictionary = _baseline()
	var rows: Array = (tables["substances.json"] as Array).duplicate(true)
	rows.remove_at(rows.size() - 1)
	tables["substances.json"] = rows
	_assert_error_mentions(_errors_of(tables), ["substances.json", "17", "16"], "第 7 类：物质条数")


func test_check7_hud_count_set_violation_reports_error() -> void:
	var index: int = _row_index_by_id("substances.json", "o2")
	var tables: Dictionary = _with_mutated_row("substances.json", index, {"count_in_hud": false})
	_assert_error_mentions(_errors_of(tables), ["substances.json", "16", "15"], "第 7 类：HUD 计数集合")


func test_check7_recipe_and_mentor_and_worldmap_counts_reported() -> void:
	var recipes: Dictionary = _baseline()
	var recipe_rows: Array = (recipes["recipes.json"] as Array).duplicate(true)
	recipe_rows.remove_at(0)
	recipes["recipes.json"] = recipe_rows
	_assert_error_mentions(_errors_of(recipes), ["recipes.json", "11", "10"], "第 7 类：配方条数")

	var mentors: Dictionary = _baseline()
	var mentor_rows: Array = (mentors["mentors.json"] as Array).duplicate(true)
	mentor_rows.remove_at(0)
	mentors["mentors.json"] = mentor_rows
	_assert_error_mentions(_errors_of(mentors), ["mentors.json", "4", "3"], "第 7 类：导师条数")

	var zones: Dictionary = _baseline()
	var zone_rows: Array = (zones["worldmap.json"] as Array).duplicate(true)
	zone_rows.remove_at(zone_rows.size() - 1)
	zones["worldmap.json"] = zone_rows
	_assert_error_mentions(_errors_of(zones), ["worldmap.json", "13", "12"], "第 7 类：区域条数")


func test_check7_unlocked_zone_count_violation_reports_error() -> void:
	var index: int = _row_index_by_id("worldmap.json", "deep_mine")
	var tables: Dictionary = _with_mutated_row(
		"worldmap.json", index, {"unlocked": true, "brief": "临时"}
	)
	_assert_error_mentions(_errors_of(tables), ["worldmap.json", "5", "6"], "第 7 类：解锁数量")


func test_check7_qa_minimum_count_violation_reports_error() -> void:
	var tables: Dictionary = _baseline()
	var rows: Array = (tables["qa_fallback.json"] as Array).duplicate(true)
	tables["qa_fallback.json"] = rows.slice(0, 19)
	_assert_error_mentions(_errors_of(tables), ["qa_fallback.json", "20", "19"], "第 7 类：问答条数")


# 第 7 类补充：qa_fallback 必须有且仅有一行 keywords 为空——那行就是零命中兜底话术
# （SPEC-04 §7 兜底行约定）。少了它零命中话术只能硬编码进代码，违反 NFR-04。
func test_check7_qa_without_fallback_row_reports_error() -> void:
	var tables: Dictionary = _baseline()
	var rows: Array = []
	for row_value in (tables["qa_fallback.json"] as Array):
		var row: Dictionary = (row_value as Dictionary).duplicate(true)
		if (row.get("keywords", []) as Array).is_empty():
			row["keywords"] = ["随便一个关键词"]
		rows.append(row)
	tables["qa_fallback.json"] = rows
	_assert_error_mentions(
		_errors_of(tables), ["qa_fallback.json", "keywords"], "第 7 类：缺兜底行"
	)


func test_check7_qa_with_two_fallback_rows_reports_error() -> void:
	var index: int = _row_index_by_id("qa_fallback.json", "qa_o2")
	var tables: Dictionary = _with_mutated_row("qa_fallback.json", index, {"keywords": []})
	_assert_error_mentions(
		_errors_of(tables), ["qa_fallback.json", "keywords"], "第 7 类：兜底行重复"
	)


# 兜底行合法：真实数据里那一行空 keywords 不该被第 3 类必填检查判成错。
func test_qa_fallback_row_with_empty_keywords_is_accepted() -> void:
	var offenders: Array = []
	for error in _errors_of(_baseline()):
		if str(error).contains("qa_no_match"):
			offenders.append(str(error))
	assert_eq(
		offenders.size(), 0,
		"兜底行 keywords 允许为空（SPEC-04 §7），实际报错：%s" % str(offenders)
	)


# 兜底行的其余字段照旧必填：answer 空了仍要报错。
func test_check3_qa_fallback_row_still_needs_answer() -> void:
	var index: int = _row_index_by_id("qa_fallback.json", "qa_no_match")
	var tables: Dictionary = _with_mutated_row("qa_fallback.json", index, {"answer": ""})
	_assert_error_mentions(
		_errors_of(tables), ["qa_fallback.json", "qa_no_match", "answer"], "第 3 类：兜底行 answer"
	)


# 非兜底行的 keywords 里不许有空字符串（空串会命中任何文本）。
func test_check3_qa_blank_keyword_reports_error() -> void:
	var index: int = _row_index_by_id("qa_fallback.json", "qa_o2")
	var tables: Dictionary = _with_mutated_row("qa_fallback.json", index, {"keywords": ["氧气", "  "]})
	_assert_error_mentions(
		_errors_of(tables), ["qa_fallback.json", "qa_o2", "keywords"], "第 3 类：空关键词"
	)


# 第 7 类补充：requires_pure_check 必须有且仅有一条（SPEC-04 §3）。
func test_check7_pure_check_uniqueness_violation_reports_error() -> void:
	var index: int = _row_index_by_id("recipes.json", "r_carbon_burn")
	var tables: Dictionary = _with_mutated_row("recipes.json", index, {"requires_pure_check": true})
	_assert_error_mentions(
		_errors_of(tables), ["recipes.json", "requires_pure_check"], "第 7 类：验纯标记数量"
	)


# 第 7 类补充：每个 reason 池至少 2 条，否则 FR-G-07 AC2「连续两次文案不同」不可满足
# （判定口径见 SPEC-01 FR-G-07 / SPEC-04 §3.1）。
func test_check7_fail_message_pool_below_minimum_reports_reason() -> void:
	var tables: Dictionary = _baseline()
	var kept: Array = []
	var dropped_one: bool = false
	for row_value in (tables["fail_messages.json"] as Array):
		var row: Dictionary = row_value as Dictionary
		if str(row.get("reason", "")) == "wrong_condition" and not dropped_one:
			dropped_one = true
			continue
		kept.append(row.duplicate(true))
	tables["fail_messages.json"] = kept
	_assert_error_mentions(
		_errors_of(tables),
		["fail_messages.json", "wrong_condition", "2", "1"],
		"第 7 类：失败文案池下限"
	)


# 真实数据里两个 reason 池都已达标（fail_wrong_tool 补入后）。
func test_real_data_fail_pools_meet_minimum() -> void:
	var rows: Array = Fixture.read_array("fail_messages.json")
	var by_reason: Dictionary = {}
	for row_value in rows:
		var reason: String = str((row_value as Dictionary).get("reason", ""))
		by_reason[reason] = int(by_reason.get(reason, 0)) + 1
	assert_gt(int(by_reason.get("no_match", 0)), 1, "no_match 池需 ≥2 条")
	assert_gt(int(by_reason.get("wrong_condition", 0)), 1, "wrong_condition 池需 ≥2 条")


# 失败池 id 只存在于 fail_messages.json，不进 tips.json（主 Agent 2026-08-02 裁决）。
func test_fail_message_ids_stay_out_of_tips_table() -> void:
	var tip_ids: Array = Fixture.ids_of(Fixture.rows_of("tips.json"))
	for row_value in Fixture.read_array("fail_messages.json"):
		var id: String = str((row_value as Dictionary).get("id", ""))
		assert_false(tip_ids.has(id), "失败文案 id 不应出现在 tips.json：%s" % id)


# 第 8 类：配方三元组无歧义（报出冲突的两个 recipe id）。
func test_check8_ambiguous_recipe_triple_reports_both_ids() -> void:
	var index: int = _row_index_by_id("recipes.json", "r_carbon_incomplete")
	# 把 R3 的 condition 改成与 R2 相同 → (inputs, tool, condition) 三元组撞车。
	var tables: Dictionary = _with_mutated_row("recipes.json", index, {"condition": "ignite"})
	_assert_error_mentions(
		_errors_of(tables),
		["recipes.json", "r_carbon_burn", "r_carbon_incomplete"],
		"第 8 类：三元组歧义"
	)


# 第 9 类：monitor prompt 含调度关键字。
func test_check9_monitor_prompt_missing_dispatch_keyword_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "monitor")
	var tables: Dictionary = _with_mutated_row(
		"mentors.json", index, {"system_prompt": "你是苏婉清，负责接住学生。"}
	)
	_assert_error_mentions(_errors_of(tables), ["mentors.json", "monitor"], "第 9 类：缺调度关键字")


# 第 9 类：非 monitor 三位必须含"绝不出现 @"。
func test_check9_non_monitor_prompt_missing_no_at_clause_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "chem")
	var tables: Dictionary = _with_mutated_row(
		"mentors.json", index, {"system_prompt": "你是袁仲衡，严谨的化学老师。"}
	)
	_assert_error_mentions(_errors_of(tables), ["mentors.json", "chem"], "第 9 类：缺禁 @ 约束")


# 第 9 类：mention 缺失（parse_mentions 的映射来源，SPEC-04 §5）。
func test_check9_missing_mention_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "think")
	var tables: Dictionary = _baseline()
	var rows: Array = (tables["mentors.json"] as Array).duplicate(true)
	var row: Dictionary = (rows[index] as Dictionary).duplicate(true)
	row.erase("mention")
	rows[index] = row
	tables["mentors.json"] = rows
	_assert_error_mentions(
		_errors_of(tables), ["mentors.json", "think", "mention"], "第 9 类：缺 mention"
	)


# 第 9 类：mention 重复会让 @ 句柄映射有歧义。
func test_check9_duplicate_mention_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "think")
	var tables: Dictionary = _with_mutated_row("mentors.json", index, {"mention": "助理"})
	_assert_error_mentions(
		_errors_of(tables), ["mentors.json", "mention"], "第 9 类：mention 重复"
	)


# 第 9 类：dispatch 少一类会让该类问题永不可达。
func test_check9_dispatch_missing_category_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "monitor")
	var entries: Array = _dispatch_of(_baseline()).duplicate(true)
	entries.remove_at(0)
	var tables: Dictionary = _with_mutated_row("mentors.json", index, {"dispatch": entries})
	_assert_error_mentions(
		_errors_of(tables), ["mentors.json", "monitor", "dispatch"], "第 9 类：dispatch 缺分类"
	)


# 第 9 类：dispatch 顺序即优先级，乱序即行为错误。
func test_check9_dispatch_wrong_priority_order_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "monitor")
	var entries: Array = _dispatch_of(_baseline()).duplicate(true)
	var first: Variant = entries[0]
	entries[0] = entries[2]
	entries[2] = first
	var tables: Dictionary = _with_mutated_row("mentors.json", index, {"dispatch": entries})
	_assert_error_mentions(
		_errors_of(tables), ["mentors.json", "monitor", "dispatch"], "第 9 类：dispatch 顺序错"
	)


# 第 9 类：targets 指向不存在的导师。
func test_check9_dispatch_unknown_target_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "monitor")
	var entries: Array = _dispatch_of(_baseline()).duplicate(true)
	var entry: Dictionary = (entries[0] as Dictionary).duplicate(true)
	entry["targets"] = ["nobody"]
	entries[0] = entry
	var tables: Dictionary = _with_mutated_row("mentors.json", index, {"dispatch": entries})
	_assert_error_mentions(
		_errors_of(tables), ["mentors.json", "monitor", "nobody"], "第 9 类：target 不存在"
	)


# 第 9 类：不许派给班主任自己（否则调度会自指）。
func test_check9_dispatch_target_monitor_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "monitor")
	var entries: Array = _dispatch_of(_baseline()).duplicate(true)
	var entry: Dictionary = (entries[0] as Dictionary).duplicate(true)
	entry["targets"] = ["monitor"]
	entries[0] = entry
	var tables: Dictionary = _with_mutated_row("mentors.json", index, {"dispatch": entries})
	_assert_error_mentions(
		_errors_of(tables), ["mentors.json", "monitor", "targets"], "第 9 类：派给自己"
	)


# 第 9 类：line 必须含每个 target 的 @mention，否则离线调度语与实际派活不一致。
func test_check9_dispatch_line_missing_mention_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "monitor")
	var entries: Array = _dispatch_of(_baseline()).duplicate(true)
	var entry: Dictionary = (entries[0] as Dictionary).duplicate(true)
	entry["line"] = "别慌，我来安排。"
	entries[0] = entry
	var tables: Dictionary = _with_mutated_row("mentors.json", index, {"dispatch": entries})
	_assert_error_mentions(
		_errors_of(tables), ["mentors.json", "monitor", "line"], "第 9 类：line 缺 @mention"
	)


# 第 9 类：非兜底类 keywords 为空 → 该类永不命中。
func test_check9_dispatch_empty_keywords_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "monitor")
	var entries: Array = _dispatch_of(_baseline()).duplicate(true)
	var entry: Dictionary = (entries[0] as Dictionary).duplicate(true)
	entry["keywords"] = []
	entries[0] = entry
	var tables: Dictionary = _with_mutated_row("mentors.json", index, {"dispatch": entries})
	_assert_error_mentions(
		_errors_of(tables), ["mentors.json", "monitor", "keywords"], "第 9 类：keywords 为空"
	)


# 第 9 类：非 monitor 不得有 dispatch。
func test_check9_non_monitor_with_dispatch_reports_error() -> void:
	var index: int = _row_index_by_id("mentors.json", "chem")
	var entries: Array = _dispatch_of(_baseline()).duplicate(true)
	var tables: Dictionary = _with_mutated_row("mentors.json", index, {"dispatch": entries})
	_assert_error_mentions(
		_errors_of(tables), ["mentors.json", "chem", "dispatch"], "第 9 类：非 monitor 带 dispatch"
	)


func _dispatch_of(tables: Dictionary) -> Array:
	for row_value in tables["mentors.json"] as Array:
		var row: Dictionary = row_value as Dictionary
		if str(row.get("id", "")) == "monitor":
			return row.get("dispatch", []) as Array
	return []


# 第 10 类：ui_strings 覆盖 SPEC-05 §9 全部 key。
func test_check10_missing_ui_string_key_reports_key_name() -> void:
	var tables: Dictionary = _baseline()
	var strings: Dictionary = (tables["ui_strings.json"] as Dictionary).duplicate(true)
	strings.erase("collected_counter")
	tables["ui_strings.json"] = strings
	_assert_error_mentions(
		_errors_of(tables), ["ui_strings.json", "collected_counter"], "第 10 类：缺 key"
	)


# 第 10 类：value 非空。
func test_check10_empty_ui_string_value_reports_error() -> void:
	var tables: Dictionary = _baseline()
	var strings: Dictionary = (tables["ui_strings.json"] as Dictionary).duplicate(true)
	strings["menu_start"] = ""
	tables["ui_strings.json"] = strings
	_assert_error_mentions(_errors_of(tables), ["ui_strings.json", "menu_start"], "第 10 类：空 value")


# 第 10 类：占位符只允许 {n}。
func test_check10_illegal_placeholder_reports_error() -> void:
	var tables: Dictionary = _baseline()
	var strings: Dictionary = (tables["ui_strings.json"] as Dictionary).duplicate(true)
	strings["collected_counter"] = "已收集 {count}/16"
	tables["ui_strings.json"] = strings
	_assert_error_mentions(
		_errors_of(tables), ["ui_strings.json", "collected_counter", "{count}"], "第 10 类：非法占位符"
	)


# 10 类检查逐类都要有覆盖：确认校验器自报的检查项编号齐全（AC1 可自动断言的部分）。
func test_validator_declares_all_ten_check_categories() -> void:
	var report: Dictionary = Validator.validate_all(_baseline())
	var checks: Array = report.get("checks", []) as Array
	assert_eq(checks.size(), 10, "校验器应声明 SPEC-04 §12 的 10 类检查，实际：%s" % str(checks))
	for i in range(1, 11):
		assert_true(checks.has(i), "缺第 %d 类检查" % i)
