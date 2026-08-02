# 字幕渲染层（FR-U-01，TP-05 补）：KnowledgeTip 的唯一 advance(delta) 调用方。
# 三种样式三个标签：bubble 头顶（set_player 后跟随投影）/ banner 底部 / warning 中部红字。
# 本层只读 current_text/current_style，不碰队列逻辑（引擎侧已被 UT-U01 覆盖）。
extends Control

# ==== 常量区 ====

const STYLE_BUBBLE: String = "bubble"
const STYLE_BANNER: String = "banner"
const STYLE_WARNING: String = "warning"

# bubble 头顶偏移（表现参数，非调参项）。
const BUBBLE_HEAD_OFFSET: Vector2 = Vector2(0, -56)
# 无玩家时 bubble 的落点（屏幕上缘中部）。
const BUBBLE_FALLBACK_ANCHOR: Vector2 = Vector2(0.5, 0.12)

const WARNING_COLOR: Color = Color(1.0, 0.25, 0.2)

# ==== 逻辑区 ====

var _player: Node2D = null

@onready var _bubble: Label = %BubbleLabel
@onready var _banner: Label = %BannerLabel
@onready var _warning: Label = %WarningLabel


func _ready() -> void:
	_bubble.visible = false
	_banner.visible = false
	_warning.visible = false
	_warning.modulate = WARNING_COLOR


# 世界接线入口：bubble 需要知道跟在谁头顶。
func set_player(player: Node2D) -> void:
	_player = player


# 唯一时间推进入口（SPEC-03 §3：autoload 自己不跑 _process）。
func _process(delta: float) -> void:
	var tip: Node = _knowledge_tip()
	if tip == null:
		return
	tip.advance(delta)
	_sync(tip)


func _sync(tip: Node) -> void:
	var style: String = str(tip.current_style())
	var text: String = str(tip.current_text())
	_bubble.visible = style == STYLE_BUBBLE and not text.is_empty()
	_banner.visible = style == STYLE_BANNER and not text.is_empty()
	_warning.visible = style == STYLE_WARNING and not text.is_empty()
	if _bubble.visible:
		_bubble.text = text
		_place_bubble()
	if _banner.visible:
		_banner.text = text
	if _warning.visible:
		_warning.text = text


# bubble 定位：有玩家投影玩家头顶到画布坐标；没有则落在上缘中部。
func _place_bubble() -> void:
	if _player != null and is_instance_valid(_player):
		var screen_pos: Vector2 = _player.get_global_transform_with_canvas().origin
		_bubble.position = screen_pos + BUBBLE_HEAD_OFFSET - _bubble.size * 0.5
		return
	_bubble.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bubble.anchor_left = BUBBLE_FALLBACK_ANCHOR.x
	_bubble.anchor_right = BUBBLE_FALLBACK_ANCHOR.x
	_bubble.anchor_top = BUBBLE_FALLBACK_ANCHOR.y
	_bubble.anchor_bottom = BUBBLE_FALLBACK_ANCHOR.y


func _knowledge_tip() -> Node:
	return get_node_or_null(^"/root/KnowledgeTip")
