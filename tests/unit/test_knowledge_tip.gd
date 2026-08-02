# UT-U01 / FR-U-01：三种 style 时长、缺 id 不崩溃、队列串行不重叠、warning 打断 bubble、show_once 只显示一次。
# 时间通过 advance(delta) 注入（SPEC-06 §3 可测性约束），不读 Time。
extends GutTest

const SOURCE_PATH: String = "res://scripts/autoload/knowledge_tip.gd"

# 注入表替代 tips.json，测试不依赖 TP-02 的数据交付。
const FIXTURE: Array = [
	{"id": "t_bubble", "style": "bubble", "text": "bubble one"},
	{"id": "t_bubble2", "style": "bubble", "text": "bubble two"},
	{"id": "t_banner", "style": "banner", "text": "banner one"},
	{"id": "t_warning", "style": "warning", "text": "warning one"},
	{"id": "t_custom_dur", "style": "banner", "duration": 9.0, "text": "long banner"},
	{"id": "t_once", "style": "banner", "once": true, "text": "only once"},
]

var tip: Node = null


func before_each() -> void:
	tip = Engine.get_main_loop().root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if tip == null:
		return
	# 先断言注入口与时间入口存在，避免脚本错误中断 before_each 造成假绿。
	assert_true(tip.has_method("load_from"), "KnowledgeTip 必须有 load_from(rows)")
	assert_true(tip.has_method("advance"), "KnowledgeTip 必须有 advance(delta)")
	assert_true(tip.has_method("current_tip_id"), "KnowledgeTip 必须有 current_tip_id()")
	if not (tip.has_method("load_from") and tip.has_method("advance")):
		return
	tip.load_from(FIXTURE)


# AC1：三种 style 的默认时长为 3 / 4 / 5 秒。
func test_style_default_durations() -> void:
	var expected: Dictionary = {"t_bubble": 3.0, "t_banner": 4.0, "t_warning": 5.0}
	for tip_id: String in expected:
		tip.clear_queue()
		tip.show(tip_id)
		var duration: float = expected[tip_id]
		tip.advance(duration - 0.1)
		assert_eq(tip.current_tip_id(), tip_id, "%s 在时长内应仍在显示" % tip_id)
		tip.advance(0.2)
		assert_eq(tip.current_tip_id(), "", "%s 超过时长后应结束" % tip_id)


# AC1：数据表里的 duration 覆盖 style 默认值（改数值不改代码）。
func test_table_duration_overrides_style_default() -> void:
	tip.show("t_custom_dur")
	tip.advance(4.5)
	assert_eq(tip.current_tip_id(), "t_custom_dur", "表里 9 秒应盖过 banner 默认 4 秒")
	tip.advance(5.0)
	assert_eq(tip.current_tip_id(), "", "9 秒后应结束")


# AC2：不存在的 tip_id 不崩溃、不入队，并留下警告日志。
func test_unknown_tip_id_does_not_crash() -> void:
	tip.show("no_such_tip")
	assert_eq(tip.queue_size(), 0, "未知 id 不应入队")
	assert_eq(tip.current_tip_id(), "", "未知 id 不应显示")
	assert_false(tip.is_shown("no_such_tip"), "未知 id 不应记为已展示")


# AC3：多条同时触发时排队串行，同一时刻只有一条在显示。
func test_tips_queue_serially_without_overlap() -> void:
	tip.show("t_bubble")
	tip.show("t_bubble2")
	assert_eq(tip.current_tip_id(), "t_bubble", "第一条应立即显示")
	assert_eq(tip.queue_size(), 1, "第二条应排队等待")
	tip.advance(3.0)
	assert_eq(tip.current_tip_id(), "t_bubble2", "第一条结束后第二条接上")
	assert_eq(tip.queue_size(), 0, "队列应已排空")
	tip.advance(3.0)
	assert_eq(tip.current_tip_id(), "", "两条都播完后无显示")


# AC3：tip_shown / tip_finished 各自按条发一次，顺序与队列一致。
func test_shown_and_finished_signals_per_tip() -> void:
	watch_signals(tip)
	tip.show("t_bubble")
	tip.show("t_banner")
	assert_signal_emitted_with_parameters(tip, "tip_shown", ["t_bubble"])
	assert_signal_emit_count(tip, "tip_shown", 1, "排队中的第二条还不该发 tip_shown")
	tip.advance(3.0)
	assert_signal_emitted_with_parameters(tip, "tip_finished", ["t_bubble"])
	assert_signal_emit_count(tip, "tip_shown", 2, "第二条上场时才发 tip_shown")


# AC1 + SPEC-03 §3：warning 可打断 bubble，危险优先。
func test_warning_interrupts_bubble() -> void:
	tip.show("t_bubble")
	assert_eq(tip.current_tip_id(), "t_bubble", "前置条件：bubble 正在显示")
	tip.show("t_warning")
	assert_eq(tip.current_tip_id(), "t_warning", "warning 应立刻抢占当前显示")
	tip.advance(5.0)
	assert_eq(tip.current_tip_id(), "", "warning 播完后被打断的 bubble 不重播")


# warning 不打断另一条 warning（否则连续危险会互相吞掉）。
func test_warning_does_not_interrupt_warning() -> void:
	tip.show("t_warning")
	tip.show("t_warning")
	assert_eq(tip.current_tip_id(), "t_warning", "仍显示第一条 warning")
	assert_eq(tip.queue_size(), 1, "第二条 warning 应排队而非抢占")


# 优化包C-3：once 字幕被 warning 抢占后不许永久丢失——撤销已展示记录，之后可再次触发。
func test_preempted_once_tip_can_be_triggered_again() -> void:
	tip.show("t_once")
	assert_eq(tip.current_tip_id(), "t_once", "前置：once 字幕正在显示")
	tip.show("t_warning")
	assert_eq(tip.current_tip_id(), "t_warning", "前置：warning 应抢占 once 字幕")
	tip.advance(5.0)
	assert_eq(tip.current_tip_id(), "", "warning 播完后无显示")
	tip.show_once("t_once")
	assert_eq(tip.current_tip_id(), "t_once", "被抢占的 once 字幕应能再次触发（不许永久丢失）")


# 优化包C-3：once 字幕在 _start 时才记已展示，入队不记；
# 排队中被 clear_queue 清掉或未来被抢占都不至于永久锁死；排队期间重复触发去重。
func test_once_tip_marked_shown_at_start_not_enqueue() -> void:
	tip.show("t_bubble")
	tip.show("t_once")
	assert_eq(tip.current_tip_id(), "t_bubble", "前置：bubble 正在显示")
	assert_eq(tip.queue_size(), 1, "once 字幕应在排队")
	assert_false(tip.is_shown("t_once"), "排队中不应记为已展示（_shown 应在 _start 时标记）")
	tip.show("t_once")
	assert_eq(tip.queue_size(), 1, "排队期间重复触发同一条 once 字幕应去重")
	tip.advance(3.0)
	assert_eq(tip.current_tip_id(), "t_once", "bubble 播完后 once 字幕开播")
	assert_true(tip.is_shown("t_once"), "开播后才记为已展示")


# AC4：show_once 的 id 重复调用不再显示。
func test_show_once_only_displays_once() -> void:
	tip.show_once("t_once")
	assert_eq(tip.current_tip_id(), "t_once", "首次 show_once 应显示")
	tip.advance(4.0)
	watch_signals(tip)
	tip.show_once("t_once")
	tip.show_once("t_once")
	assert_signal_emit_count(tip, "tip_shown", 0, "重复 show_once 不应再显示")
	assert_true(tip.is_shown("t_once"), "已展示记录应保留")


# 数据表里 once=true 的字幕即使走 show() 也只显示一次（区域字幕靠这条兜底）。
func test_table_once_flag_enforced_via_show() -> void:
	tip.show("t_once")
	tip.advance(4.0)
	watch_signals(tip)
	tip.show("t_once")
	assert_signal_emit_count(tip, "tip_shown", 0, "表里 once=true 的字幕不应重复显示")


# once=false 的字幕允许重复显示。
func test_non_once_tip_can_repeat() -> void:
	tip.show("t_banner")
	tip.advance(4.0)
	tip.show("t_banner")
	assert_eq(tip.current_tip_id(), "t_banner", "once=false 的字幕应能重复显示")


# clear_queue 清掉排队项与当前显示，场景切换不残留。
func test_clear_queue_drops_pending_and_current() -> void:
	tip.show("t_bubble")
	tip.show("t_banner")
	tip.clear_queue()
	assert_eq(tip.queue_size(), 0, "队列应清空")
	assert_eq(tip.current_tip_id(), "", "当前显示也应清掉")


# show_custom 用于动态拼接文案；空文本被拒绝。
func test_show_custom_displays_and_rejects_empty() -> void:
	tip.show_custom("动态文案", "banner", 2.0)
	assert_eq(tip.current_text(), "动态文案", "show_custom 应显示传入文本")
	tip.advance(2.0)
	tip.show_custom("", "banner", 2.0)
	assert_eq(tip.current_text(), "", "空文本不应显示")


# 非法 style 退回默认 banner，不崩溃。
func test_invalid_style_falls_back() -> void:
	tip.load_from([{"id": "t_bad_style", "style": "explode", "text": "bad"}])
	tip.show("t_bad_style")
	assert_eq(tip.current_tip_id(), "t_bad_style", "非法 style 仍应显示")
	tip.advance(4.0)
	assert_eq(tip.current_tip_id(), "", "非法 style 应按 banner 的 4 秒处理")


# 非正 delta 不推进（防御性输入校验）。
func test_non_positive_delta_does_not_advance() -> void:
	tip.show("t_bubble")
	tip.advance(0.0)
	tip.advance(-5.0)
	assert_eq(tip.current_tip_id(), "t_bubble", "非正 delta 不应结束字幕")


# NFR-04：字幕引擎源码里不许出现中文字面量，文案只能来自数据表。
func test_source_has_no_chinese_literals() -> void:
	var file: FileAccess = FileAccess.open(SOURCE_PATH, FileAccess.READ)
	assert_not_null(file, "应能读到 knowledge_tip.gd 源码")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()
	var offenders: Array[String] = []
	for line: String in source.split("\n"):
		var code: String = line
		var comment_at: int = code.find("#")
		if comment_at >= 0:
			code = code.substr(0, comment_at)
		if not code.contains("\""):
			continue
		# 开发者诊断日志不受 NFR-04 管制（SPEC-01 §10 NFR-04 判定口径）。
		if code.contains("push_warning(") or code.contains("push_error(") or code.contains("print("):
			continue
		for i: int in code.length():
			# CJK 统一汉字区：文案必须走 tips.json，不许写在逻辑里。
			var c: int = code.unicode_at(i)
			if c >= 0x4E00 and c <= 0x9FFF:
				offenders.append(code.strip_edges())
				break
	assert_eq(offenders.size(), 0, "源码非注释部分不应含中文字面量：%s" % str(offenders))
