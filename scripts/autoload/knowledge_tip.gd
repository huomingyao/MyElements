# KnowledgeTip（SPEC-03 §3，FR-U-01）：字幕引擎，全项目唯一文案出口。
# 时间只从 advance(delta) 进（SPEC-06 §3 可测性约束）：autoload 自己不跑 _process，
# 测试可一次注入任意秒数。渲染层（scenes/ui/tip_*.tscn）监听 tip_shown / tip_finished 画。
extends Node

signal tip_shown(tip_id: String)
signal tip_finished(tip_id: String)

# ==== 常量区 ====

const STYLES: Array[String] = ["bubble", "banner", "warning"]
const DEFAULT_STYLE: String = "banner"

# 三种样式的默认时长（SPEC-04 §4：bubble 3s 头顶 / banner 4s 底部 / warning 5s 红字）。
const STYLE_DURATIONS: Dictionary = {"bubble": 3.0, "banner": 4.0, "warning": 5.0}

# 可打断其他样式的高优先级样式（SPEC-03 §3：危险优先）。
const INTERRUPT_STYLE: String = "warning"

# 单次 advance 允许结算的字幕条数上限，防止坏配置（duration<=0）造成死循环。
const MAX_ADVANCE_STEPS: int = 64

const KEY_ID: String = "id"
const KEY_STYLE: String = "style"
const KEY_TEXT: String = "text"
const KEY_DURATION: String = "duration"
const KEY_ONCE: String = "once"

# ==== 逻辑区 ====

var _tips: Dictionary = {}
var _shown: Dictionary = {}
var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _elapsed: float = 0.0


func _ready() -> void:
	reload()


func reload() -> void:
	load_from(DataLoader.load_table("tips.json", TYPE_ARRAY, []))


# 数据注入口（SPEC-06 §3 可测性约束）：测试用内存数组替代 tips.json，
# 不依赖数据交付进度；顺带复位展示记录与队列。
func load_from(rows: Array) -> void:
	_tips = DataLoader.index_by_id(rows)
	_shown.clear()
	clear_queue()


func show(tip_id: String) -> void:
	var tip: Dictionary = _tips.get(tip_id, {})
	if tip.is_empty():
		push_warning("[tip] 不存在的 tip_id：%s（忽略）" % tip_id)
		return
	# 表里标了 once 的字幕（区域横幅、首次拾取）即使走 show() 也只显示一次。
	if bool(tip.get(KEY_ONCE, false)) and _shown.has(tip_id):
		return
	var style: String = str(tip.get(KEY_STYLE, DEFAULT_STYLE))
	if not STYLES.has(style):
		push_warning("[tip] tip %s 的 style 非法：%s（按 %s 处理）" % [tip_id, style, DEFAULT_STYLE])
		style = DEFAULT_STYLE
	_enqueue({
		KEY_ID: tip_id,
		KEY_TEXT: str(tip.get(KEY_TEXT, "")),
		KEY_STYLE: style,
		KEY_DURATION: _resolve_duration(tip, style),
	})


# 表里没写 duration 时按 style 默认值（SPEC-04 §4）。
func _resolve_duration(tip: Dictionary, style: String) -> float:
	var fallback: float = float(STYLE_DURATIONS.get(style, STYLE_DURATIONS[DEFAULT_STYLE]))
	var raw: float = float(tip.get(KEY_DURATION, fallback))
	if raw <= 0.0:
		return fallback
	return raw


# 同一 id 只显示一次（区域横幅、首次拾取）。
func show_once(tip_id: String) -> void:
	if _shown.has(tip_id):
		return
	show(tip_id)


# 仅用于必须动态拼接的极少场景（物质名 + 数量），不得用来绕过数据表。
func show_custom(text: String, style: String, duration: float) -> void:
	if text.is_empty():
		push_warning("[tip] show_custom 文本为空（忽略）")
		return
	var safe_style: String = style if STYLES.has(style) else DEFAULT_STYLE
	_enqueue({
		KEY_ID: "",
		KEY_TEXT: text,
		KEY_STYLE: safe_style,
		KEY_DURATION: maxf(duration, 0.0),
	})


func is_shown(tip_id: String) -> bool:
	return _shown.has(tip_id)


# 清空排队项与当前显示（场景切换/测试用）。
func clear_queue() -> void:
	_queue.clear()
	_current = {}
	_elapsed = 0.0


# 排队中的条数，不含当前正在显示的那条。
func queue_size() -> int:
	return _queue.size()


# 当前正在显示的字幕 id；无显示或为 show_custom 时返回空串。
func current_tip_id() -> String:
	return str(_current.get(KEY_ID, ""))


# 当前正在显示的文案；供渲染层与测试读取。
func current_text() -> String:
	return str(_current.get(KEY_TEXT, ""))


func current_style() -> String:
	return str(_current.get(KEY_STYLE, ""))


# 唯一时间推进入口：由渲染层在 _process(delta) 里调用。
# 支持一次注入超过一条时长的大 delta，逐条结算不丢 tip_finished。
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var remaining: float = delta
	var steps: int = 0
	while remaining > 0.0 and not _current.is_empty() and steps < MAX_ADVANCE_STEPS:
		steps += 1
		var left: float = float(_current.get(KEY_DURATION, 0.0)) - _elapsed
		if left <= 0.0:
			_finish_current()
			continue
		if remaining < left:
			_elapsed += remaining
			return
		remaining -= left
		_finish_current()


# 入队：warning 抢占当前非 warning 字幕；其余按先后顺序排队串行播放（AC3 不重叠）。
func _enqueue(entry: Dictionary) -> void:
	var tip_id: String = str(entry[KEY_ID])
	if not tip_id.is_empty():
		_shown[tip_id] = true
	if str(entry[KEY_STYLE]) == INTERRUPT_STYLE and _is_preemptable():
		# 被打断的字幕直接作废，不重播（避免危险提示过后又弹回旧内容）。
		_drop_current()
		_start(entry)
		return
	if _current.is_empty():
		_start(entry)
		return
	_queue.append(entry)


func _is_preemptable() -> bool:
	if _current.is_empty():
		return false
	return str(_current.get(KEY_STYLE, "")) != INTERRUPT_STYLE


func _start(entry: Dictionary) -> void:
	_current = entry
	_elapsed = 0.0
	var tip_id: String = str(entry[KEY_ID])
	if not tip_id.is_empty():
		tip_shown.emit(tip_id)


# 当前字幕播完：发 tip_finished，然后把队首接上台。
func _finish_current() -> void:
	_drop_current()
	if _queue.is_empty():
		return
	_start(_queue.pop_front())


func _drop_current() -> void:
	if _current.is_empty():
		return
	var tip_id: String = str(_current.get(KEY_ID, ""))
	_current = {}
	_elapsed = 0.0
	if not tip_id.is_empty():
		tip_finished.emit(tip_id)
