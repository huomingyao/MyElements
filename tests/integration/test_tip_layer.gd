# FR-U-01 渲染层补（UT-U01 已覆盖引擎队列）：三种样式的可见渲染——
# bubble 头顶 / banner 底部 / warning 中部红字；渲染层是唯一 advance(delta) 调用方。
extends GutTest

const LAYER_SCENE: String = "res://scenes/ui/tip_layer.tscn"
const LAYER_SCRIPT: String = "res://scenes/ui/tip_layer.gd"

var tip: Node = null
var _layer: Node = null

const TINY_TIPS: Array = [
	{"id": "t_bubble", "style": "bubble", "duration": 0.2, "text": "bubble-text"},
	{"id": "t_banner", "style": "banner", "duration": 0.2, "text": "banner-text"},
	{"id": "t_warning", "style": "warning", "duration": 0.2, "text": "warning-text"},
	{"id": "t_long", "style": "banner", "duration": 30.0, "text": "long-text"},
]


func before_each() -> void:
	tip = Engine.get_main_loop().root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if tip == null:
		return
	tip.load_from(TINY_TIPS)
	_layer = null
	if not ResourceLoader.exists(LAYER_SCENE):
		fail_test("尚未实现 %s（FR-U-01 渲染层 / TP-05 补）" % LAYER_SCENE)
		return
	_layer = (load(LAYER_SCENE) as PackedScene).instantiate()
	add_child_autofree(_layer)
	await wait_process_frames(1)


func after_each() -> void:
	if tip != null:
		tip.reload()
		tip.clear_queue()


func _skip_unless_ready() -> bool:
	return _layer == null


func _label(unique_name: String) -> Label:
	var found: Node = _layer.get_node_or_null(NodePath("%%%s" % unique_name))
	if found == null:
		fail_test("字幕层应有唯一名节点 %%%s" % unique_name)
		return null
	return found as Label


# banner：底部横幅显示文案，其余样式标签隐藏。
func test_banner_shows_at_bottom() -> void:
	if _skip_unless_ready():
		return
	var banner: Label = _label("BannerLabel")
	var bubble: Label = _label("BubbleLabel")
	var warning: Label = _label("WarningLabel")
	if banner == null or bubble == null or warning == null:
		return
	tip.show("t_banner")
	await wait_process_frames(2)
	assert_true(banner.visible, "banner 字幕应显示 BannerLabel")
	assert_eq(banner.text, "banner-text", "文案来自当前字幕")
	assert_false(bubble.visible, "非 bubble 时 BubbleLabel 隐藏")
	assert_false(warning.visible, "非 warning 时 WarningLabel 隐藏")
	assert_true(banner.anchor_top > 0.5 or banner.position.y > 180.0, "banner 位于屏幕下方")


# bubble：头顶气泡（跟随玩家投影）；warning：红字。
func test_bubble_and_warning_styles() -> void:
	if _skip_unless_ready():
		return
	var bubble: Label = _label("BubbleLabel")
	var warning: Label = _label("WarningLabel")
	if bubble == null or warning == null:
		return
	tip.show("t_bubble")
	await wait_process_frames(2)
	assert_true(bubble.visible, "bubble 字幕应显示 BubbleLabel")
	assert_eq(bubble.text, "bubble-text")
	tip.clear_queue()
	tip.show("t_warning")
	await wait_process_frames(2)
	assert_true(warning.visible, "warning 字幕应显示 WarningLabel")
	assert_eq(warning.text, "warning-text")
	assert_true(warning.modulate.r > 0.8 and warning.modulate.g < 0.4, "warning 为红字")


# bubble 跟随玩家：set_player 后气泡位置随玩家（投影到画布坐标）。
func test_bubble_follows_player() -> void:
	if _skip_unless_ready():
		return
	var bubble: Label = _label("BubbleLabel")
	if bubble == null:
		return
	if not _layer.has_method("set_player"):
		fail_test("字幕层应有 set_player()（bubble 头顶定位）")
		return
	var player: Node2D = Node2D.new()
	add_child_autofree(player)
	player.global_position = Vector2(120, 200)
	_layer.set_player(player)
	var fallback_pos: Vector2 = bubble.position
	tip.show("t_bubble")
	await wait_process_frames(2)
	assert_ne(bubble.position, fallback_pos, "有玩家时气泡应跟随玩家而非固定位置")
	# 画布投影在 headless 下为恒等变换：屏幕坐标 ≈ 世界坐标，气泡在头顶上方。
	assert_true(bubble.position.y < player.global_position.y, "气泡应在玩家头顶上方")


# 时长推进由渲染层驱动：短字幕播完后标签隐藏（advance 的唯一调用方在渲染层）。
func test_label_hides_after_duration() -> void:
	if _skip_unless_ready():
		return
	var banner: Label = _label("BannerLabel")
	if banner == null:
		return
	tip.show("t_banner")
	await wait_process_frames(2)
	assert_true(banner.visible, "显示中")
	await wait_seconds(0.4)
	assert_false(banner.visible, "播完后应隐藏")


# 队列串行：两条 banner 不同时显示，第二条等第一条播完。
func test_queue_is_serial_not_overlapping() -> void:
	if _skip_unless_ready():
		return
	var banner: Label = _label("BannerLabel")
	if banner == null:
		return
	tip.show("t_banner")
	tip.show("t_long")
	await wait_process_frames(2)
	assert_eq(banner.text, "banner-text", "先到的先显示")
	await wait_seconds(0.4)
	assert_eq(banner.text, "long-text", "第一条播完才轮到第二条")


# NFR-04：逻辑代码里不许出现中文字面量（注释与诊断日志除外）。
func test_script_has_no_hardcoded_chinese() -> void:
	if not FileAccess.file_exists(LAYER_SCRIPT):
		fail_test("尚未实现 %s" % LAYER_SCRIPT)
		return
	var text: String = FileAccess.get_file_as_string(LAYER_SCRIPT)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("push_warning") or stripped.contains("push_error") or stripped.contains("print("):
			continue
		assert_false(_has_cjk(stripped), "逻辑代码里不许硬编码中文（NFR-04）：%s" % stripped)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
