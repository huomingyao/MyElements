# Player（FR-P-01..03，IT-P01/02/03，TP-04）：横版移动/跳跃/重力/朝向，
# 统一交互键 E + 提示气泡 + 最近目标，相机边界，火把照明半径。
# 数值全部读自 balance.json（经 GameManager.get_balance），逻辑代码不出现魔法数字与中文文案。
extends CharacterBody2D

# ==== 常量区 ====

const BAL_MOVE_SPEED: String = "player.move_speed"
const BAL_JUMP_VELOCITY: String = "player.jump_velocity"
const BAL_GRAVITY: String = "player.gravity"
const BAL_INTERACT_RADIUS: String = "player.interact_radius"
const BAL_DARK_VIEW_RADIUS: String = "daynight.dark_view_radius"
const BAL_TORCH_VIEW_RADIUS: String = "daynight.torch_view_radius"

# 数据表缺失时的兜底默认值（不属调参项）。
const FALLBACK_MOVE_SPEED: float = 110.0
const FALLBACK_JUMP_VELOCITY: float = -300.0
const FALLBACK_GRAVITY: float = 900.0
const FALLBACK_INTERACT_RADIUS: float = 28.0
const FALLBACK_DARK_VIEW_RADIUS: float = 80.0
const FALLBACK_TORCH_VIEW_RADIUS: float = 220.0

# 黑暗区域：矿洞一层（SPEC-02 §3：黑暗需火把）。
const DARK_ZONE: String = "mine"

# ViewLight 贴图基准半径：纹理到位后 texture_scale = view_radius / 基准值。
const LIGHT_TEXTURE_BASE_RADIUS: float = 64.0

# ==== 逻辑区 ====

# 移动参数（_ready 时从 balance.json 读入；reload_config 可重读，调参与测试用）。
var move_speed: float = FALLBACK_MOVE_SPEED
var jump_velocity: float = FALLBACK_JUMP_VELOCITY
var gravity: float = FALLBACK_GRAVITY
var interact_radius: float = FALLBACK_INTERACT_RADIUS

# 朝向：1 右 / -1 左。美术到位后由它驱动贴图翻转。
var facing: int = 1

# 背包实例挂载点（TP-06 Inventory，RefCounted）：由世界场景在生成玩家后注入。
# 设施经 player.get("inventory") 鸭子类型取用（TP-10 约定）。
var inventory: RefCounted = null

# 道具效果实例挂载点（TP-09 ItemEffects，RefCounted）：同样由世界场景注入。
var item_effects: RefCounted = null

var _torch_equipped: bool = false
var _current_target: Node = null

@onready var _interactor: Area2D = %Interactor
@onready var _prompt: Label = %PromptBubble
@onready var _light: PointLight2D = %ViewLight
@onready var _camera: Camera2D = %Camera


func _ready() -> void:
	add_to_group("player")
	reload_config()
	_prompt.visible = false
	_light.enabled = false


# 从 balance.json 重读玩家参数（铁律 4：改表即改行为）。
func reload_config() -> void:
	var gm: Node = _game_manager()
	move_speed = _balance(gm, BAL_MOVE_SPEED, FALLBACK_MOVE_SPEED)
	jump_velocity = _balance(gm, BAL_JUMP_VELOCITY, FALLBACK_JUMP_VELOCITY)
	gravity = _balance(gm, BAL_GRAVITY, FALLBACK_GRAVITY)
	interact_radius = _balance(gm, BAL_INTERACT_RADIUS, FALLBACK_INTERACT_RADIUS)
	var shape_node: CollisionShape2D = _interactor.get_node_or_null(^"Shape")
	if shape_node != null and shape_node.shape is CircleShape2D:
		(shape_node.shape as CircleShape2D).radius = interact_radius


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_apply_movement()
	move_and_slide()
	_update_interaction()
	_update_light()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta


func _apply_movement() -> void:
	var direction: float = Input.get_axis("move_left", "move_right")
	var speed: float = move_speed * _speed_multiplier()
	velocity.x = direction * speed
	if not is_zero_approx(direction):
		facing = signi(direction)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity


# 能量归零时速度打折（FR-P-01 AC2）；倍率由 GameManager 统一结算。
func _speed_multiplier() -> float:
	var gm: Node = _game_manager()
	if gm == null:
		return 1.0
	return float(gm.move_speed_multiplier())


# ==== 交互（FR-P-02）：只调 SPEC-03 §5 的三个方法，不认识具体类型 ====

func _update_interaction() -> void:
	_current_target = _interactor.nearest_interactable(global_position)
	if _current_target != null and bool(_current_target.can_interact()):
		_prompt.text = _ui_string(str(_current_target.get_interact_prompt()))
		_prompt.visible = true
	else:
		_prompt.visible = false
	if Input.is_action_just_pressed("interact"):
		_try_interact()


func _try_interact() -> void:
	if _current_target == null:
		return
	if not bool(_current_target.can_interact()):
		return
	# 约束（SPEC-03 §5）：interact() 内部不许阻塞，这里只发一次调用。
	_current_target.interact(self)


# 当前选中的交互目标（可能 can_interact() == false，由调用方再判）；无则 null。
func current_interactable() -> Node:
	return _current_target


# ==== 相机与照明（FR-P-03） ====

# 由世界场景在铺好地图后调用，把可行走边界写进相机 limit（FR-P-03 AC1）。
func set_map_bounds(bounds: Rect2) -> void:
	_camera.set_map_bounds(bounds)


# 装备/卸下硫火把（FR-G-12 的道具生效会调这里）；只影响可视半径，不管贴图。
func set_torch_equipped(equipped: bool) -> void:
	_torch_equipped = equipped


func is_torch_equipped() -> bool:
	return _torch_equipped


# 当前装备中的道具 id 列表（TP-09 怪物判口罩/火把免疫用）。
# 走 ItemEffects.equipped_ids()；未注入时回退火把状态，保证矿洞不裸奔。
func get_equipped_item_ids() -> Array:
	if item_effects != null and item_effects.has_method("equipped_ids"):
		return item_effects.equipped_ids()
	if _torch_equipped:
		return ["sulfur_torch"]
	return []


# 当前可视半径（FR-P-03 AC2，数值可断言）；黑暗外不点灯但半径仍按装备报告。
func view_radius() -> float:
	if _torch_equipped:
		return _balance(_game_manager(), BAL_TORCH_VIEW_RADIUS, FALLBACK_TORCH_VIEW_RADIUS)
	return _balance(_game_manager(), BAL_DARK_VIEW_RADIUS, FALLBACK_DARK_VIEW_RADIUS)


# 夜晚或矿洞内点灯；半径变化实时反映到 texture_scale（纹理由 P4 交付）。
func _update_light() -> void:
	var gm: Node = _game_manager()
	var dark: bool = false
	if gm != null:
		dark = bool(gm.is_night()) or str(gm.current_zone()) == DARK_ZONE
	_light.enabled = dark
	if _light.texture != null:
		_light.texture_scale = view_radius() / LIGHT_TEXTURE_BASE_RADIUS


# ==== autoload 访问（缺失时用兜底默认值，不崩溃） ====

func _game_manager() -> Node:
	return get_node_or_null(^"/root/GameManager")


func _balance(gm: Node, key: String, fallback: float) -> float:
	if gm == null:
		return fallback
	return float(gm.get_balance(key, fallback))


func _ui_string(key: String) -> String:
	var gm: Node = _game_manager()
	if gm == null:
		return key
	return str(gm.get_ui_string(key))
