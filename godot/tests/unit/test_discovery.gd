# UT-G03 / FR-G-03：首次收集统计。重复拾取只计一次；is_discovered 正确；
# HUD 计数集合恰好 16（co2 不计入，口径见 SPEC-05 §1）。
extends GutTest

const DISCOVERY_PATH: String = "res://scripts/gameplay/discovery.gd"

# SPEC-05 §1 HUD 计数口径：17 条物质中 co2 标 count_in_hud=false，故计数集合为 16。
const EXPECTED_COUNT_TOTAL: int = 16
const EXCLUDED_FROM_HUD: String = "co2"

var dis: RefCounted = null
var db: Node = null


func before_each() -> void:
	db = Engine.get_main_loop().root.get_node_or_null(^"RecipeDB")
	assert_not_null(db, "RecipeDB autoload 必须存在（物质表来源）")
	if not ResourceLoader.exists(DISCOVERY_PATH):
		fail_test("尚未实现 %s（FR-G-03）" % DISCOVERY_PATH)
		return
	var script: Resource = load(DISCOVERY_PATH)
	assert_not_null(script, "discovery.gd 应可加载")
	if script == null:
		return
	dis = script.new()
	assert_not_null(dis, "Discovery 应可直接实例化（SPEC-06 §3 纯逻辑可测性）")


# 新集合是空的。
func test_new_discovery_is_empty() -> void:
	if dis == null:
		return
	assert_eq(dis.discovered_count(), 0, "初始已发现计数应为 0")
	assert_false(dis.is_discovered("s"), "初始不应有任何已发现物质")
	assert_eq(dis.discovered_ids().size(), 0, "初始已发现集合应为空")


# AC1：同一物质重复拾取只计一次；首次返回 true，之后返回 false。
func test_repeated_discovery_counts_once() -> void:
	if dis == null:
		return
	assert_true(dis.discover("s"), "首次发现应返回 true")
	assert_false(dis.discover("s"), "重复发现应返回 false")
	assert_false(dis.discover("s"), "再次重复仍应返回 false")
	assert_eq(dis.discovered_count(), 1, "重复拾取只应计一次")


# AC2：is_discovered 供图鉴查询，已发现/未发现都要答对。
func test_is_discovered_reflects_state() -> void:
	if dis == null:
		return
	dis.discover("fe")
	assert_true(dis.is_discovered("fe"), "已发现的应为 true")
	assert_false(dis.is_discovered("nacl"), "未发现的应为 false")


# 多个不同物质各计一次。
func test_distinct_substances_accumulate() -> void:
	if dis == null:
		return
	for id: String in ["o2", "h2", "c", "s"]:
		assert_true(dis.discover(id), "首次发现 %s 应返回 true" % id)
	assert_eq(dis.discovered_count(), 4, "四种不同物质应计 4")
	assert_eq(dis.discovered_ids().size(), 4, "集合大小应为 4")


# HUD 计数口径：计数总数恰好 16，且集合来自数据表而非代码写死。
func test_count_total_is_sixteen_from_data() -> void:
	if dis == null:
		return
	assert_eq(dis.count_total(), EXPECTED_COUNT_TOTAL, "HUD 计数集合应恰好 16 条")
	var expected: int = 0
	for row: Dictionary in db.all_substances():
		if bool(row.get("count_in_hud", true)):
			expected += 1
	assert_eq(dis.count_total(), expected, "计数总数应等于数据表中 count_in_hud=true 的条数")


# 计数口径：co2 不计入 HUD 计数，但仍算「已发现」（图鉴要展示它）。
func test_co2_is_discovered_but_not_counted() -> void:
	if dis == null:
		return
	assert_true(dis.discover(EXCLUDED_FROM_HUD), "co2 应能被记为已发现")
	assert_true(dis.is_discovered(EXCLUDED_FROM_HUD), "图鉴需要知道 co2 已发现")
	assert_eq(dis.counted_count(), 0, "co2 不应计入 HUD 计数")
	assert_eq(dis.discovered_count(), 1, "但已发现总数应为 1")


# HUD 计数只统计计数集合内的物质。
func test_counted_count_only_counts_hud_set() -> void:
	if dis == null:
		return
	dis.discover("s")
	dis.discover(EXCLUDED_FROM_HUD)
	dis.discover("fe")
	assert_eq(dis.counted_count(), 2, "只有 s 与 fe 计入 HUD 计数")
	assert_eq(dis.discovered_count(), 3, "已发现总数为 3")


# 收集齐全时 HUD 计数达到 16/16（演示收尾要能显示满值）。
func test_full_collection_reaches_total() -> void:
	if dis == null:
		return
	for row: Dictionary in db.all_substances():
		dis.discover(str(row.get("id", "")))
	assert_eq(dis.counted_count(), dis.count_total(), "全收集时计数应等于总数")
	assert_eq(dis.discovered_count(), 17, "已发现应含全部 17 条（含 co2）")


# 防御性输入：不存在的 id 与空 id 不计入，也不崩溃。
func test_unknown_and_empty_ids_are_rejected() -> void:
	if dis == null:
		return
	assert_false(dis.discover(""), "空 id 不应计入")
	assert_false(dis.discover("unobtainium"), "数据表里没有的 id 不应计入")
	assert_eq(dis.discovered_count(), 0, "非法 id 不应改变计数")
	assert_false(dis.is_discovered("unobtainium"), "非法 id 不应为已发现")


# 首次发现要发信号供 HUD 刷新计数、字幕引擎弹气泡（重复拾取不发）。
func test_first_discovery_emits_signal() -> void:
	if dis == null:
		return
	assert_true(dis.has_signal("substance_discovered"), "Discovery 应有 substance_discovered 信号")
	if not dis.has_signal("substance_discovered"):
		return
	watch_signals(dis)
	dis.discover("s")
	assert_signal_emitted_with_parameters(dis, "substance_discovered", ["s"])
	assert_signal_emit_count(dis, "substance_discovered", 1, "首次发现应发一次信号")
	dis.discover("s")
	assert_signal_emit_count(dis, "substance_discovered", 1, "重复拾取不应再发信号")


# 集合可复位（新开局/测试用）。
func test_reset_clears_the_set() -> void:
	if dis == null:
		return
	dis.discover("s")
	dis.discover("fe")
	dis.reset()
	assert_eq(dis.discovered_count(), 0, "复位后计数应为 0")
	assert_false(dis.is_discovered("s"), "复位后不应有已发现物质")


# 逻辑代码不许出现中文文案与写死的计数值（NFR-04：16 必须来自数据表）。
func test_source_has_no_chinese_or_hardcoded_total() -> void:
	var file: FileAccess = FileAccess.open(DISCOVERY_PATH, FileAccess.READ)
	assert_not_null(file, "discovery.gd 应可读")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("#"):
			continue
		if line.contains("push_warning(") or line.contains("push_error(") or line.contains("print("):
			continue
		var code: String = line
		var comment_at: int = code.find("#")
		if comment_at >= 0:
			code = code.substr(0, comment_at)
		assert_false(code.contains("16"), "计数总数不许写死，必须数 count_in_hud：%s" % line)
		for i: int in code.length():
			var c: int = code.unicode_at(i)
			assert_false(c >= 0x4E00 and c <= 0x9FFF, "逻辑代码出现中文字面量：%s" % line)

