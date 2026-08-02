# 导师小人（FR-M-01）：房间内 32×32 像素小人，idle 两帧。
# 实现 SPEC-03 §5 交互三方法；玩家交互系统不需要认识它的具体类型。
# 只发信号（ask_requested），由场景所有者把它接到聊天框——场景间不横向直连（§1）。
extends Area2D

signal ask_requested(mentor_id: String)

# ==== 常量区 ====
const Art: GDScript = preload("res://scenes/mentor/mentor_art.gd")

# 提示气泡 id：ui_strings.prompt_ask（「按 E 提问」），文案不进代码（NFR-04）。
const PROMPT_ID: String = "prompt_ask"
# 像素小人规格（SPEC-08 §2）：32×32，横向两帧 sprite sheet。
const SPRITE_SIZE: Vector2i = Vector2i(32, 32)

const F_ID: String = "id"
const F_SPRITE: String = "sprite"

# ==== 状态区 ====
var mentor_id: String = ""

@onready var _sprite: AnimatedSprite2D = %Sprite


# ==== 逻辑区 ====
# 由学院场景在 add_child 之后调用：行数据驱动，节点自身不读数据表（SPEC-03 §1）。
func setup(row: Dictionary) -> void:
	mentor_id = str(row.get(F_ID, ""))
	if not is_node_ready():
		push_warning("[mentor] setup() 需在节点入树后调用，sprite 未设置")
		return
	_sprite.sprite_frames = Art.idle_frames(str(row.get(F_SPRITE, "")), SPRITE_SIZE, mentor_id)
	_sprite.play(Art.ANIM_IDLE)


func get_interact_prompt() -> String:
	return PROMPT_ID


func can_interact() -> bool:
	return not mentor_id.is_empty()


func interact(_player: Node) -> void:
	if mentor_id.is_empty():
		return
	ask_requested.emit(mentor_id)
