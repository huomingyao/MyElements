# UT-M04 / FR-M-04：四类分类器 + route_targets。
# 四类各 ≥3 个样例判定正确；混合样例按 combat→learning→chemistry→other 优先级归类；
# learning 派两位。关键词与派给对象全部来自 mentors.json 的 monitor.dispatch（SPEC-04 §5），
# 测试里的样例句取自 SPEC-05 §4.1 判断表，只做交叉验证。
# 用 load() 按路径取脚本：实现缺失时是断言失败而非编译错误（SPEC-06 §2）。
extends GutTest

const ROUTER_PATH: String = "res://scripts/mentor/mentor_router.gd"

const CAT_COMBAT: String = "combat"
const CAT_LEARNING: String = "learning"
const CAT_CHEMISTRY: String = "chemistry"
const CAT_OTHER: String = "other"

# SPEC-05 §4.1：每类 ≥3 个样例（AC4）。
const SAMPLES: Dictionary = {
	"combat": ["有个怪过来了怎么办", "前面很危险，我打不过", "酸雾扑上来了，掉血好快"],
	"learning": ["化学怎么学才记得牢", "这些我总是记不住", "下周考试了该怎么复习"],
	"chemistry": ["氢气和氧气怎么变成水", "这个方程式怎么配平", "为什么燃烧会生成二氧化碳"],
	"other": ["接下来我该做点啥", "我下一步去哪儿好", "这个游戏有没有目标"],
}

# 混合样例：同时命中多类，必须按数组顺序（优先级）归类。
const MIXED: Dictionary = {
	"怪物打不过，氢气能用吗": "combat",
	"记不住方程式怎么办": "learning",
	"酸雾怪要怎么用碱对付": "combat",
	"复习的时候老忘记燃烧的条件": "learning",
}

var router: RefCounted = null


func before_each() -> void:
	if not ResourceLoader.exists(ROUTER_PATH):
		fail_test("尚未实现 %s（FR-M-04）" % ROUTER_PATH)
		return
	var script: Resource = load(ROUTER_PATH)
	assert_not_null(script, "mentor_router.gd 应可加载")
	if script == null:
		return
	router = script.new()
	assert_not_null(router, "MentorRouter 应可直接实例化（SPEC-03 §6.1）")


func _has(method_name: String) -> bool:
	if router == null:
		return false
	var ok: bool = router.has_method(method_name)
	assert_true(ok, "MentorRouter 应有 %s()（SPEC-03 §6.1）" % method_name)
	return ok


# AC4：四类各 ≥3 个样例判定正确。
func test_classify_matches_spec_samples_for_every_category() -> void:
	if not _has("classify"):
		return
	for category in SAMPLES:
		var questions: Array = SAMPLES[category]
		assert_gt(questions.size(), 2, "%s 的样例应 ≥3 条（AC4）" % category)
		for question in questions:
			assert_eq(
				router.classify(str(question)), str(category),
				"「%s」应归类为 %s" % [str(question), str(category)]
			)


# 混合样例按 combat→learning→chemistry→other 的数组顺序归类。
func test_classify_uses_array_order_as_priority() -> void:
	if not _has("classify"):
		return
	for question in MIXED:
		assert_eq(
			router.classify(str(question)), str(MIXED[question]),
			"混合样例「%s」应按优先级归 %s" % [str(question), str(MIXED[question])]
		)


# 零命中走兜底类；空输入同样不许崩。
func test_classify_falls_back_to_other() -> void:
	if not _has("classify"):
		return
	assert_eq(router.classify("你好呀"), CAT_OTHER, "零命中应归兜底类")
	assert_eq(router.classify(""), CAT_OTHER, "空输入应归兜底类，不许崩")


# AC3：route_targets 只做查表；learning 返回两位。
func test_route_targets_matches_spec_table() -> void:
	if not _has("route_targets"):
		return
	assert_eq(router.route_targets(CAT_COMBAT), ["think"], "战斗类派思维老师")
	assert_eq(router.route_targets(CAT_LEARNING), ["think", "assistant"], "学习类派两位")
	assert_eq(router.route_targets(CAT_CHEMISTRY), ["chem"], "化学类派化学老师")
	assert_eq(router.route_targets(CAT_OTHER), ["assistant"], "其他类派助理")


# 未知分类返回空数组，不许返回 null 也不许崩。
func test_route_targets_of_unknown_category_is_empty() -> void:
	if not _has("route_targets"):
		return
	var targets: Array = router.route_targets("no_such_category")
	assert_eq(targets.size(), 0, "未知分类应返回空数组")


# 派给对象永不含班主任自己（否则调度自指）。
func test_route_targets_never_include_monitor() -> void:
	if not _has("route_targets"):
		return
	for category in SAMPLES:
		for target in router.route_targets(str(category)):
			assert_ne(str(target), "monitor", "%s 不该派给班主任自己" % str(category))


# 关键词与派给对象来自数据表：注入改过的行，行为随之改变（铁律 4 / SPEC-06 §3）。
func test_keywords_and_targets_come_from_injected_rows() -> void:
	if not _has("load_from"):
		return
	var rows: Array = [
		{"id": "monitor", "mention": "班主任", "dispatch": [
			{"category": CAT_COMBAT, "keywords": ["史莱姆"], "targets": ["chem"], "line": "@化学老师"},
			{"category": CAT_OTHER, "keywords": [], "targets": ["think"], "line": "@思维老师"},
		]},
		{"id": "chem", "mention": "化学老师"},
		{"id": "think", "mention": "思维老师"},
	]
	router.load_from(rows)
	assert_eq(router.classify("有只史莱姆"), CAT_COMBAT, "分类应认注入表里的关键词")
	assert_eq(router.route_targets(CAT_COMBAT), ["chem"], "派给对象应认注入表")
	assert_eq(router.classify("氢气怎么合成"), CAT_OTHER, "注入表里没有化学类 → 走兜底")


# 分类顺序也来自表：调换 dispatch 顺序即调换优先级，不改代码。
func test_priority_follows_injected_array_order() -> void:
	if not _has("load_from"):
		return
	var rows: Array = [
		{"id": "monitor", "mention": "班主任", "dispatch": [
			{"category": CAT_CHEMISTRY, "keywords": ["氢气"], "targets": ["chem"], "line": "@化学老师"},
			{"category": CAT_COMBAT, "keywords": ["怪"], "targets": ["think"], "line": "@思维老师"},
			{"category": CAT_OTHER, "keywords": [], "targets": ["chem"], "line": "@化学老师"},
		]},
		{"id": "chem", "mention": "化学老师"},
		{"id": "think", "mention": "思维老师"},
	]
	router.load_from(rows)
	assert_eq(
		router.classify("怪物来了，氢气能用吗"), CAT_CHEMISTRY,
		"chemistry 排在 combat 前 → 混合样例应归 chemistry"
	)


# 数据表缺 monitor 行时不崩：分类回兜底、派活为空（数据坏了由校验器报错，运行时不许炸）。
func test_missing_monitor_row_degrades_safely() -> void:
	if not _has("load_from"):
		return
	router.load_from([{"id": "chem", "mention": "化学老师"}])
	assert_eq(router.classify("氢气怎么合成"), CAT_OTHER, "缺 dispatch 时应回兜底类")
	assert_eq(router.route_targets(CAT_CHEMISTRY).size(), 0, "缺 dispatch 时派活为空")

