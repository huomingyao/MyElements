# UT-M05 / FR-M-05：@ 解析与终止约束。
# 首条消息 mentor_id=="monitor"；返回长度 ≤3；非 monitor 消息里的 @ 被忽略；
# 构造循环 @ 不递归不卡死；调度计数硬上限 1（代码保证，不依赖 prompt 自觉）。
# 回复来源通过 set_reply_provider 注入，测试不发任何网络请求（SPEC-06 §3）。
extends GutTest

const ROUTER_PATH: String = "res://scripts/mentor/mentor_router.gd"

const MONITOR_ID: String = "monitor"
const KEY_MENTOR_ID: String = "mentor_id"
const KEY_TEXT: String = "text"
const KEY_OFFLINE: String = "offline"
const MAX_MESSAGES: int = 3

var router: RefCounted = null


func before_each() -> void:
	if not ResourceLoader.exists(ROUTER_PATH):
		fail_test("尚未实现 %s（FR-M-05）" % ROUTER_PATH)
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


func _ids_of(messages: Array) -> Array[String]:
	var out: Array[String] = []
	for message in messages:
		out.append(str((message as Dictionary).get(KEY_MENTOR_ID, "")))
	return out


# 注入一个固定回复源，避免网络。provider 收 (mentor_id, question) 返回文本。
func _use_provider(provider: Callable) -> bool:
	if not _has("set_reply_provider"):
		return false
	router.set_reply_provider(provider)
	return true


# parse_mentions：@句柄 → 导师 id，映射来源是 mentors.json 的 mention 字段。
func test_parse_mentions_maps_handles_to_mentor_ids() -> void:
	if not _has("parse_mentions"):
		return
	assert_eq(
		router.parse_mentions("别慌。@思维老师 快告诉孩子该用什么元素对付它！"), ["think"],
		"@思维老师 应映射到 think（title 是「实用思维老师」，只有 mention 能匹配）"
	)
	assert_eq(
		router.parse_mentions("这我熟。@思维老师 讲方法，@助理 列计划。"), ["think", "assistant"],
		"多个 @ 按出现顺序返回"
	)


func test_parse_mentions_ignores_unknown_and_duplicate_handles() -> void:
	if not _has("parse_mentions"):
		return
	assert_eq(router.parse_mentions("@校长 你来"), [], "未知句柄应被忽略")
	assert_eq(router.parse_mentions("@助理 @助理 排计划"), ["assistant"], "重复 @ 只算一次")
	assert_eq(router.parse_mentions(""), [], "空文本返回空数组")


# AC1：第一条消息必须来自班主任，不论问什么。
func test_first_message_is_always_from_monitor() -> void:
	if not _has("handle_message"):
		return
	if not _use_provider(func(mentor_id: String, _q: String) -> String: return "回复自 %s" % mentor_id):
		return
	for question in ["有个怪过来了", "氢气怎么合成水", "记不住方程式", "接下来干啥"]:
		var messages: Array = await router.handle_message(question)
		assert_gt(messages.size(), 0, "「%s」应至少有班主任一条回复" % question)
		if messages.is_empty():
			continue
		assert_eq(
			str((messages[0] as Dictionary).get(KEY_MENTOR_ID, "")), MONITOR_ID,
			"「%s」的首条消息必须来自班主任（AC1）" % question
		)


# AC1：返回长度 ≤3（班主任 + 最多 2 位被派老师）。
func test_message_count_never_exceeds_three() -> void:
	if not _has("handle_message"):
		return
	if not _use_provider(func(mentor_id: String, _q: String) -> String: return "回复自 %s" % mentor_id):
		return
	for question in ["记不住方程式怎么复习", "氢气怎么合成水", "怪物打不过"]:
		var messages: Array = await router.handle_message(question)
		assert_true(
			messages.size() <= MAX_MESSAGES,
			"「%s」返回 %d 条，超过上限 %d" % [question, messages.size(), MAX_MESSAGES]
		)


# 学习方法类派两位 → 班主任 + think + assistant 共三条，顺序与 targets 一致。
func test_learning_question_yields_monitor_plus_two_mentors() -> void:
	if not _has("handle_message"):
		return
	if not _use_provider(func(mentor_id: String, _q: String) -> String: return "回复自 %s" % mentor_id):
		return
	var messages: Array = await router.handle_message("这些方程式我总是记不住，怎么复习")
	assert_eq(_ids_of(messages), [MONITOR_ID, "think", "assistant"], "学习类应是班主任 + 两位老师")


# 每条消息结构齐全（SPEC-03 §6.1 返回结构）。
func test_every_message_has_contract_fields() -> void:
	if not _has("handle_message"):
		return
	if not _use_provider(func(mentor_id: String, _q: String) -> String: return "回复自 %s" % mentor_id):
		return
	for message_value in await router.handle_message("氢气怎么合成水"):
		var message: Dictionary = message_value as Dictionary
		for field in [KEY_MENTOR_ID, KEY_TEXT, KEY_OFFLINE]:
			assert_true(message.has(field), "消息缺字段 %s：%s" % [field, str(message)])
		assert_false(str(message.get(KEY_TEXT, "")).is_empty(), "消息文本不许为空")
		assert_eq(typeof(message.get(KEY_OFFLINE)), TYPE_BOOL, "offline 应为 bool")


# AC2：被派老师回复里的 @ 不触发新一轮（只解析 monitor 的消息）。
func test_at_mentions_in_non_monitor_reply_are_ignored() -> void:
	if not _has("handle_message"):
		return
	# 化学老师违规带 @：真实数据里 prompt 禁止，这里模拟 LLM 不听话的情况。
	if not _use_provider(func(mentor_id: String, _q: String) -> String:
		if mentor_id == MONITOR_ID:
			return "别慌，这件事我来安排。@化学老师 你来把原理讲透！"
		return "@思维老师 @助理 你们也来看看"):
		return
	var messages: Array = await router.handle_message("氢气怎么合成水")
	assert_eq(_ids_of(messages), [MONITOR_ID, "chem"], "非 monitor 消息里的 @ 必须被忽略（AC2）")


# AC3：循环 @ 的对抗输入不无限递归。班主任 @ 自己 + 老师 @ 回班主任。
func test_circular_at_mentions_do_not_recurse() -> void:
	if not _has("handle_message"):
		return
	if not _use_provider(func(_mentor_id: String, _q: String) -> String:
		return "@班主任 @化学老师 @思维老师 @助理 都来"):
		return
	var messages: Array = await router.handle_message("怪物打不过，氢气能用吗")
	assert_true(messages.size() <= MAX_MESSAGES, "循环 @ 下仍不许超过 %d 条" % MAX_MESSAGES)
	var ids: Array[String] = _ids_of(messages)
	assert_eq(ids[0], MONITOR_ID, "首条仍是班主任")
	assert_eq(
		ids.count(MONITOR_ID), 1, "班主任只出场一次，不许被自己的 @ 再拉进来：%s" % str(ids)
	)


# AC1：调度计数硬上限 1，用计数器保证而非 prompt 自觉。
func test_dispatch_count_is_capped_at_one() -> void:
	if not _has("handle_message"):
		return
	if not _has("dispatch_count"):
		return
	if not _use_provider(func(_mentor_id: String, _q: String) -> String:
		return "@化学老师 @思维老师 @助理 都来"):
		return
	await router.handle_message("氢气怎么合成水")
	assert_eq(int(router.dispatch_count()), 1, "一次 handle_message 只许调度 1 次（AC1）")


# 每次 handle_message 都从零开始计数，不许跨调用累积。
func test_dispatch_count_resets_per_call() -> void:
	if not _has("handle_message") or not _has("dispatch_count"):
		return
	if not _use_provider(func(mentor_id: String, _q: String) -> String: return "回复自 %s" % mentor_id):
		return
	await router.handle_message("氢气怎么合成水")
	await router.handle_message("怪物打不过")
	assert_eq(int(router.dispatch_count()), 1, "计数应每次调用重置")


# 离线角标透传（优化包C-1）：回复来源自报离线时，即使文本非空，offline 也必须为 true——
# 否则离线兜底（qa_fallback）的回答会被 UI 当成在线回复，离线角标漏显。
# provider 可返回 {text, offline} 字典表达来源的在线状态；返回字符串时维持旧语义（空串=离线）。
func test_offline_flag_follows_reply_source_not_text_emptiness() -> void:
	if not _has("handle_message"):
		return
	if not _use_provider(func(mentor_id: String, _q: String) -> Dictionary:
		return {KEY_TEXT: "离线兜底回复 %s" % mentor_id, KEY_OFFLINE: true}):
		return
	var messages: Array = await router.handle_message("氢气怎么合成水")
	assert_gt(messages.size(), 0, "应有回复")
	for message_value in messages:
		var message: Dictionary = message_value as Dictionary
		assert_true(
			bool(message.get(KEY_OFFLINE, false)),
			"来源自报离线时 offline 必须透传到每条消息（含被派导师，不许硬编码 false）：%s" % str(message)
		)


# 在线来源自报在线：文本非空且 offline=false 时，每条消息 offline 均为 false。
func test_online_source_marks_all_messages_online() -> void:
	if not _has("handle_message"):
		return
	if not _use_provider(func(mentor_id: String, _q: String) -> Dictionary:
		return {KEY_TEXT: "在线回复 %s" % mentor_id, KEY_OFFLINE: false}):
		return
	for message_value in await router.handle_message("氢气怎么合成水"):
		var message: Dictionary = message_value as Dictionary
		assert_false(
			bool(message.get(KEY_OFFLINE, true)),
			"来源自报在线时 offline 应为 false：%s" % str(message)
		)


# 空输入不产生任何消息（与 FR-M-03 AC2 一致：不发起请求）。
func test_blank_question_yields_no_messages() -> void:
	if not _has("handle_message"):
		return
	if not _use_provider(func(mentor_id: String, _q: String) -> String: return "回复自 %s" % mentor_id):
		return
	assert_eq((await router.handle_message("   ")).size(), 0, "空输入不该产生消息")


# 回复源返回空串时也不许崩：班主任那条走兜底文本，链条正常终止。
func test_empty_reply_does_not_break_the_chain() -> void:
	if not _has("handle_message"):
		return
	if not _use_provider(func(_mentor_id: String, _q: String) -> String: return ""):
		return
	var messages: Array = await router.handle_message("氢气怎么合成水")
	assert_gt(messages.size(), 0, "回复为空时仍应有班主任的离线调度语")
	assert_eq(str((messages[0] as Dictionary).get(KEY_MENTOR_ID, "")), MONITOR_ID, "首条仍是班主任")
	assert_true(
		bool((messages[0] as Dictionary).get(KEY_OFFLINE, false)), "走兜底时 offline 应为 true"
	)

