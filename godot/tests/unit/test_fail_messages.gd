# UT-G07 / FR-G-07：失败文案。三类失败文案不混用（按 reason 分池）；
# 连续两次同类失败文案不同（确定性轮转，禁止 randi）。判定口径见 SPEC-01 FR-G-07。
extends GutTest

# 没有任何配方使用的器材，用来稳定制造 wrong_condition。
const UNUSED_TOOL: String = "filter"

var db: Node = null
var gm: Node = null


func before_each() -> void:
	var root: Node = Engine.get_main_loop().root
	db = root.get_node_or_null(^"RecipeDB")
	gm = root.get_node_or_null(^"GameManager")
	assert_not_null(db, "RecipeDB autoload 必须存在")
	assert_not_null(gm, "GameManager autoload 必须存在")
	if db == null or gm == null:
		return
	assert_true(db.has_method("get_fail_message"), "RecipeDB 必须有 get_fail_message()（SPEC-03 §4）")
	assert_true(db.has_method("reset_rotation"), "RecipeDB 必须有 reset_rotation()")
	assert_true(db.has_method("all_fail_messages"), "RecipeDB 必须有 all_fail_messages()")
	if not (db.has_method("get_fail_message") and db.has_method("reset_rotation")
			and db.has_method("all_fail_messages")):
		return
	db.reload()
	db.reset_rotation()
	gm.set_flag("purity_check_unlocked", false)


# 通用 no_match 轮转池的条数：fail_copper_acid 是铜+酸专属彩蛋（包B-A7），不计入通用池。
func _generic_no_match_pool_size() -> int:
	var size: int = 0
	for row: Dictionary in db.all_fail_messages():
		if str(row.get("reason", "")) != "no_match":
			continue
		if str(row.get("id", "")) == "fail_copper_acid":
			continue
		size += 1
	return size


# 制造一次 no_match 失败并返回 fail_tip_id。
func _no_match_id() -> String:
	return str(db.try_craft(["stick", "stick"], "bench", "none").get("fail_tip_id", ""))


# 制造一次 wrong_condition 失败并返回 fail_tip_id。
func _wrong_condition_id() -> String:
	return str(db.try_craft(["stick", "s"], UNUSED_TOOL, "ignite").get("fail_tip_id", ""))


# 数据前提（SPEC-04 §3.1）：每个 reason 池至少 2 条，否则 AC2 数学上不可满足。
func test_each_reason_pool_has_at_least_two_messages() -> void:
	var by_reason: Dictionary = {}
	for row: Dictionary in db.all_fail_messages():
		var reason: String = str(row.get("reason", ""))
		by_reason[reason] = int(by_reason.get(reason, 0)) + 1
	for reason: String in ["no_match", "wrong_condition"]:
		assert_gt(int(by_reason.get(reason, 0)), 1, "%s 池需 ≥2 条以支持轮换" % reason)


# AC1：失败文案 id 必须真在 fail_messages.json 里，且其 reason 与失败原因一致（不跨池取用）。
func test_fail_tip_id_matches_its_reason_pool() -> void:
	var no_match: Dictionary = db.get_fail_message(_no_match_id())
	assert_false(no_match.is_empty(), "no_match 的 fail_tip_id 必须能在失败池里查到")
	assert_eq(str(no_match.get("reason", "")), "no_match", "no_match 只能取 no_match 池的文案")
	db.reset_rotation()
	var wrong: Dictionary = db.get_fail_message(_wrong_condition_id())
	assert_false(wrong.is_empty(), "wrong_condition 的 fail_tip_id 必须能在失败池里查到")
	assert_eq(str(wrong.get("reason", "")), "wrong_condition", "wrong_condition 只能取本池文案")


# AC1：两个池的 id 集合互不相交——池间绝不混用。
func test_reason_pools_do_not_share_ids() -> void:
	var seen: Dictionary = {}
	for row: Dictionary in db.all_fail_messages():
		var id: String = str(row.get("id", ""))
		assert_false(seen.has(id), "失败池 id 重复：%s" % id)
		seen[id] = str(row.get("reason", ""))
	var no_match_id: String = _no_match_id()
	db.reset_rotation()
	var wrong_id: String = _wrong_condition_id()
	assert_ne(no_match_id, wrong_id, "两类失败不应取到同一条文案")


# AC2：连续两次 no_match 文案不同（确定性轮转）。
func test_consecutive_no_match_messages_differ() -> void:
	var first: String = _no_match_id()
	var second: String = _no_match_id()
	assert_false(first.is_empty(), "第一次 no_match 应有文案 id")
	assert_ne(first, second, "连续两次 no_match 文案必须不同（FR-G-07 AC2）")


# AC2：连续两次 wrong_condition 文案不同。
func test_consecutive_wrong_condition_messages_differ() -> void:
	var first: String = _wrong_condition_id()
	var second: String = _wrong_condition_id()
	assert_false(first.is_empty(), "第一次 wrong_condition 应有文案 id")
	assert_ne(first, second, "连续两次 wrong_condition 文案必须不同（FR-G-07 AC2）")


# 两个池各自独立轮转：夹在中间的另一类失败不打乱本池的轮转位置。
func test_pools_rotate_independently() -> void:
	var a: String = _no_match_id()
	_wrong_condition_id()
	var b: String = _no_match_id()
	assert_ne(a, b, "另一类失败插在中间，no_match 仍应继续轮转")


# 轮转是确定性的、可预测的（SPEC-06 §3：随机必须可预测，禁止 randi）：
# 复位后重跑同一串失败，得到完全相同的 id 序列。
func test_rotation_is_deterministic_after_reset() -> void:
	var first_pass: Array[String] = []
	for i: int in 5:
		first_pass.append(_no_match_id())
	db.reset_rotation()
	var second_pass: Array[String] = []
	for i: int in 5:
		second_pass.append(_no_match_id())
	assert_eq(second_pass, first_pass, "复位后同样的失败序列应给出同样的文案序列")


# 轮转走满一圈后回到第一条（取模，不越界、不停在最后一条）。
# 包B-A7：fail_copper_acid 已移出通用轮转池，池长按通用条数计算。
func test_rotation_wraps_around_pool() -> void:
	var pool_size: int = _generic_no_match_pool_size()
	assert_gt(pool_size, 1, "no_match 通用池应有多条")
	var first: String = _no_match_id()
	var seen: Array[String] = [first]
	for i: int in pool_size - 1:
		seen.append(_no_match_id())
	assert_eq(seen.size(), pool_size, "一圈内应取到池内每一条")
	assert_eq(_no_match_id(), first, "走满一圈后应回到第一条")
	# 一圈之内不出现重复，说明是轮转而不是随机抽。
	var unique: Dictionary = {}
	for id: String in seen:
		unique[id] = true
	assert_eq(unique.size(), pool_size, "一圈内不应出现重复文案")


# 包B-A7（FR-G-07 口径）：铜+酸组合命中专属彩蛋文案，且确定性返回（顺序无关、不随机）。
func test_copper_acid_combo_returns_easter_egg_message() -> void:
	var first: Dictionary = db.try_craft(["cu", "hcl"], "bench", "none")
	assert_eq(str(first.get("fail_reason", "")), "no_match", "铜+酸应报 no_match")
	assert_eq(str(first.get("fail_tip_id", "")), "fail_copper_acid", "铜+酸应命中彩蛋文案")
	var second: Dictionary = db.try_craft(["hcl", "cu"], "portable", "none")
	assert_eq(str(second.get("fail_tip_id", "")), "fail_copper_acid", "彩蛋文案应确定性返回（顺序无关）")


# 包B-A7：通用 no_match 池转满一圈也不许轮出铜酸彩蛋。
func test_generic_no_match_pool_excludes_copper_acid() -> void:
	var pool_size: int = _generic_no_match_pool_size()
	for i: int in pool_size + 1:
		var id: String = _no_match_id()
		assert_ne(id, "fail_copper_acid", "通用 no_match 池不许轮出铜酸彩蛋（FR-G-07 口径）")


# 包B-A7：彩蛋路径不消耗通用池的轮转位置（各池确定性互不干扰）。
func test_copper_acid_does_not_consume_generic_rotation() -> void:
	var expected: String = _no_match_id()
	db.reset_rotation()
	db.try_craft(["cu", "hcl"], "bench", "none")
	assert_eq(_no_match_id(), expected, "彩蛋文案不应推进通用池轮转")


# 失败文案的 text 非空且来自数据表（调用方靠它走 show_custom 显示）。
func test_fail_messages_carry_non_empty_text() -> void:
	for row: Dictionary in db.all_fail_messages():
		var id: String = str(row.get("id", ""))
		assert_false(str(row.get("text", "")).is_empty(), "%s 的 text 不应为空" % id)
		assert_true(id.begins_with("fail_"), "%s 应以 fail_ 前缀命名" % id)


# needs_purity_check 不取失败池文案（该路径由 FR-G-08 爆炸事件接管）。
func test_needs_purity_check_has_no_fail_message() -> void:
	gm.set_flag("purity_check_unlocked", false)
	var result: Dictionary = db.try_craft(["h2", "o2"], "portable", "ignite")
	assert_eq(str(result.get("fail_reason", "")), "needs_purity_check", "未验纯应报 needs_purity_check")
	assert_eq(str(result.get("fail_tip_id", "")), "", "needs_purity_check 不取失败池文案")


# 成功时不取失败文案，也不推进任何池的轮转。
func test_success_does_not_consume_rotation() -> void:
	var before: String = _no_match_id()
	var ok: Dictionary = db.try_craft(["hcl", "naoh"], "bench", "none")
	assert_true(bool(ok.get("success", false)), "中和反应应成功")
	assert_eq(str(ok.get("fail_tip_id", "")), "", "成功时 fail_tip_id 应为空串")
	db.reset_rotation()
	assert_eq(_no_match_id(), before, "成功不应消耗轮转位置")


# 逻辑代码不许出现中文文案（NFR-04；push_warning/push_error/print 的诊断日志除外）。
func test_recipe_db_source_has_no_chinese_literals() -> void:
	var file: FileAccess = FileAccess.open("res://scripts/autoload/recipe_db.gd", FileAccess.READ)
	assert_not_null(file, "recipe_db.gd 应可读")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("#"):
			continue
		# NFR-04 判定口径：开发者诊断日志不受管制。
		if line.contains("push_warning(") or line.contains("push_error(") or line.contains("print("):
			continue
		var code: String = line
		var comment_at: int = code.find("#")
		if comment_at >= 0:
			code = code.substr(0, comment_at)
		for i: int in code.length():
			var c: int = code.unicode_at(i)
			assert_false(c >= 0x4E00 and c <= 0x9FFF, "逻辑代码出现中文字面量：%s" % line)


# 轮转计数器不许用 randi/randf（确定性硬约束，SPEC-06 §3）。只查代码行，注释里提到不算。
func test_recipe_db_source_uses_no_randomness() -> void:
	var file: FileAccess = FileAccess.open("res://scripts/autoload/recipe_db.gd", FileAccess.READ)
	assert_not_null(file, "recipe_db.gd 应可读")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()
	for raw_line: String in source.split("\n"):
		var code: String = raw_line.strip_edges()
		if code.begins_with("#"):
			continue
		var comment_at: int = code.find("#")
		if comment_at >= 0:
			code = code.substr(0, comment_at)
		for token: String in ["randi(", "randf(", "randi_range(", "pick_random("]:
			assert_false(code.contains(token), "失败文案轮转不许用随机：%s" % token)

