# UT-M06 / FR-M-06：导师人设一致性。
# AC1 代码中不含任何人设文本（grep 式扫 scripts/）；
# AC2 三位非班主任 prompt 含"绝不出现 @"；
# AC3 通用后缀（SPEC-04 §6）拼接在每个人设段之后。
# 后缀是**唯一**允许写在代码里的 prompt 文本（SPEC-04 §6 约束），位置 scripts/mentor/prompt_suffix.gd。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const ROUTER_PATH: String = "res://scripts/mentor/mentor_router.gd"
const SUFFIX_PATH: String = "res://scripts/mentor/prompt_suffix.gd"

const SCAN_ROOT: String = "res://scripts"
# 后缀自身住在这里，扫描时跳过（否则 AC1 会把合法后缀判成违规）。
const SCAN_SKIP: Array[String] = [SUFFIX_PATH]

const MONITOR_ID: String = "monitor"
const NO_AT_CLAUSE: String = "回答里绝不出现 @。"
# 人设文本的取样长度：够长到不会误伤普通注释，够短到能抓住复制粘贴。
const PERSONA_PROBE_LENGTH: int = 12

var suffix: RefCounted = null
var router: RefCounted = null


func before_each() -> void:
	if not ResourceLoader.exists(SUFFIX_PATH):
		fail_test("尚未实现 %s（SPEC-04 §6）" % SUFFIX_PATH)
		return
	if not ResourceLoader.exists(ROUTER_PATH):
		fail_test("尚未实现 %s（FR-M-06）" % ROUTER_PATH)
		return
	suffix = (load(SUFFIX_PATH) as Resource).new()
	router = (load(ROUTER_PATH) as Resource).new()
	assert_not_null(suffix, "PromptSuffix 应可直接实例化")
	assert_not_null(router, "MentorRouter 应可直接实例化")


func _mentor_rows() -> Array[Dictionary]:
	return Fixture.rows_of("mentors.json")


# AC1：代码里不含任何人设文本。取每位导师 prompt 的前若干字当探针扫 scripts/。
func test_no_persona_text_appears_in_code() -> void:
	var files: Array[String] = _gd_files_under(SCAN_ROOT)
	assert_gt(files.size(), 0, "scripts/ 下应能扫到 .gd 文件")
	for row in _mentor_rows():
		var id: String = str(row.get("id", ""))
		var prompt: String = str(row.get("system_prompt", ""))
		assert_gt(prompt.length(), PERSONA_PROBE_LENGTH, "%s 的 system_prompt 过短" % id)
		var probe: String = prompt.substr(0, PERSONA_PROBE_LENGTH)
		for file_path in files:
			assert_false(
				FileAccess.get_file_as_string(file_path).contains(probe),
				"%s 含 %s 的人设文本「%s」（FR-M-06 AC1）" % [file_path, id, probe]
			)


# AC1 补充：口头禅同样是内容，不许进代码。
func test_no_catchphrase_appears_in_code() -> void:
	var files: Array[String] = _gd_files_under(SCAN_ROOT)
	for row in _mentor_rows():
		for phrase_value in row.get("catchphrases", []) as Array:
			var phrase: String = str(phrase_value)
			if phrase.length() < PERSONA_PROBE_LENGTH:
				continue
			for file_path in files:
				assert_false(
					FileAccess.get_file_as_string(file_path).contains(phrase),
					"%s 含口头禅「%s」（FR-M-06 AC1）" % [file_path, phrase]
				)


# AC1 补充：调度语（玩家可见聊天文本）也只许在数据表里，不许进代码。
func test_no_dispatch_line_appears_in_code() -> void:
	var files: Array[String] = _gd_files_under(SCAN_ROOT)
	for row in _mentor_rows():
		if str(row.get("id", "")) != MONITOR_ID:
			continue
		for entry_value in row.get("dispatch", []) as Array:
			var line: String = str((entry_value as Dictionary).get("line", ""))
			assert_false(line.is_empty(), "dispatch 的 line 不该为空")
			for file_path in files:
				assert_false(
					FileAccess.get_file_as_string(file_path).contains(line),
					"%s 含调度语「%s」（NFR-04 / FR-M-06 AC1）" % [file_path, line]
				)


# AC2：三位非班主任的 prompt 含"绝不出现 @"约束。
func test_non_monitor_prompts_contain_no_at_clause() -> void:
	var checked: int = 0
	for row in _mentor_rows():
		var id: String = str(row.get("id", ""))
		if id == MONITOR_ID:
			continue
		checked += 1
		assert_true(
			str(row.get("system_prompt", "")).contains(NO_AT_CLAUSE),
			"%s 的 prompt 缺「%s」（AC2）" % [id, NO_AT_CLAUSE]
		)
	assert_eq(checked, 3, "除班主任外应有三位导师")


# AC3：通用后缀拼在人设段之后，且人设段原文完整保留在前。
func test_system_prompt_appends_generic_suffix() -> void:
	if router == null or suffix == null:
		return
	if not router.has_method("system_prompt_for"):
		fail_test("MentorRouter 应有 system_prompt_for(mentor_id)（AC3）")
		return
	if not suffix.has_method("text"):
		fail_test("PromptSuffix 应有 text()（SPEC-04 §6）")
		return
	var suffix_text: String = str(suffix.text())
	assert_false(suffix_text.strip_edges().is_empty(), "通用后缀不许为空")
	for row in _mentor_rows():
		var id: String = str(row.get("id", ""))
		var persona: String = str(row.get("system_prompt", ""))
		var full: String = str(router.system_prompt_for(id))
		assert_true(full.begins_with(persona), "%s 的人设段应原样在前（AC3）" % id)
		assert_true(full.ends_with(suffix_text), "%s 的 prompt 应以通用后缀结尾（AC3）" % id)


# 未知导师 id 返回空串，不许把后缀单独喂给 LLM。
func test_system_prompt_of_unknown_mentor_is_empty() -> void:
	if router == null or not router.has_method("system_prompt_for"):
		return
	assert_eq(str(router.system_prompt_for("no_such_mentor")), "", "未知导师应返回空串")


# 后缀内容对齐 SPEC-04 §6 的技术约束要点（改后缀要同步改 spec）。
func test_generic_suffix_states_technical_constraints() -> void:
	if suffix == null or not suffix.has_method("text"):
		return
	var text: String = str(suffix.text())
	for keyword in ["初中化学", "120", "方程式", "AI"]:
		assert_true(text.contains(keyword), "通用后缀应提到「%s」（SPEC-04 §6）" % keyword)


# 递归收集 scripts/ 下的 .gd（跳过后缀自身）。
func _gd_files_under(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			continue
		for name in dir.get_directories():
			pending.append(dir_path.path_join(name))
		for name in dir.get_files():
			if not name.ends_with(".gd"):
				continue
			var file_path: String = dir_path.path_join(name)
			if SCAN_SKIP.has(file_path):
				continue
			out.append(file_path)
	return out

