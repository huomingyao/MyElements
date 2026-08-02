# 采集物（FR-G-01，IT-G01，TP-06 补）：场景中漂浮发光的可拾取物。
# 节点只配置 substance_id，名称/化学式/图标/字幕 id 全部从数据表读取（AC1）：
# 先查 substances.json（经 RecipeDB），查不到再查 items.json（木棒等材料）。
# 拾取入包 + 消失 + 首次 bubble 字幕（once 去重由字幕引擎保证）；
# 背包满时留在原地不静默丢弃；未知 id 不崩溃。
# 图标缺失时用 id 散列稳定色占位（美术归 P4 替换），不留空白不崩溃。
extends Area2D

# 拾取成功信号：世界场景接到 Discovery（首次统计）与 HUD 计数。
signal collected(substance_id: String)

# ==== 常量区 ====

const PROMPT_ID: String = "prompt_interact"

# 漂浮呼吸动画（表现参数，非 SPEC-02 §4 调参项）。
const FLOAT_AMPLITUDE: float = 4.0
const FLOAT_HALF_PERIOD: float = 0.9
const GLOW_ALPHA_LOW: float = 0.45
const GLOW_RADIUS: float = 10.0

const KEY_NAME: String = "name"
const KEY_FORMULA: String = "formula"
const KEY_TIP: String = "tip_id"
const KEY_ICON: String = "icon"

# ==== 逻辑区 ====

# 编辑器摆放也可直接填；运行时由世界经 setup() 写入。
@export var substance_id: String = ""

var _record: Dictionary = {}
var _picked: bool = false
var _base_y: float = 0.0

# 视觉逻辑分离（模块化重构）：视觉部件各自独立节点（%Visuals 容器下），
# 音频进 %Audio 容器；下方方法按部件拆分，改单个部件不碰其他部件。
@onready var _visuals: Node2D = %Visuals
@onready var _glow: Polygon2D = %Glow
@onready var _icon: Sprite2D = %IconSprite
@onready var _pickup_audio: AudioStreamPlayer = %PickupPlayer


func _ready() -> void:
	_base_y = position.y
	_resolve_record()
	_apply_glow()
	_apply_icon()
	_tween_float()
	_tween_glow()


# 世界生成入口（运行时注入 id；与 @export 摆放等价）。
func setup(id_value: String) -> void:
	substance_id = id_value
	_picked = false
	if is_node_ready():
		_resolve_record()
		_apply_glow()
		_apply_icon()


# AC1 的可观测口：当前解析出的数据表记录（副本；未知 id 为空字典）。
func record() -> Dictionary:
	return _record.duplicate()


# ==== IInteractable（SPEC-03 §5） ====

func get_interact_prompt() -> String:
	return PROMPT_ID


func can_interact() -> bool:
	return not _picked and not _record.is_empty()


func interact(player: Node) -> void:
	if not can_interact():
		return
	var inventory: RefCounted = _inventory_of(player)
	if inventory == null:
		push_warning("[collect] 玩家没有可用背包，拾取被忽略：%s" % substance_id)
		return
	var leftover: int = int(inventory.add_item(substance_id, 1))
	if leftover > 0:
		# 背包满：留在原地，不静默丢弃（FR-G-02 AC2 的联动语义）。
		return
	_picked = true
	_play_pickup_sound()
	_show_tip(str(_record.get(KEY_TIP, "")))
	collected.emit(substance_id)
	_free_after_sound()


# ==== 内部 ====

# 数据表解析：先物质表（RecipeDB，SPEC-03 §1 数据表只由 autoload 读取），
# 查不到再查道具表（items.json，木棒等材料也是可采集物）。未知 id 警告不崩溃（AC4）。
func _resolve_record() -> void:
	_record = {}
	if substance_id.is_empty():
		push_warning("[collect] 采集物未配置 substance_id（不可交互）")
		return
	var db: Node = get_node_or_null(^"/root/RecipeDB")
	if db != null:
		var substance: Dictionary = db.get_substance(substance_id)
		if not substance.is_empty():
			_record = substance
			return
	var items: RefCounted = (load("res://scripts/gameplay/item_effects.gd") as GDScript).new()
	var item: Dictionary = items.get_item(substance_id)
	if not item.is_empty():
		_record = item
		return
	push_warning("[collect] 数据表中不存在的 id：%s（不可交互）" % substance_id)


# 发光部件：图标缺失时用 id 散列稳定色占位（同一物质颜色局内一致，美术到位后自然被贴图替换）。
func _apply_glow() -> void:
	if _record.is_empty():
		_visuals.visible = false
		return
	_visuals.visible = true
	var hue: float = float(substance_id.hash() % 360) / 360.0
	var color: Color = Color.from_hsv(hue, 0.65, 1.0, 0.9)
	if _glow != null:
		_glow.color = color
		_glow.polygon = _circle_polygon(GLOW_RADIUS, 12)


# 图标部件：有贴图则显示，缺失时隐藏不空白（P4 美术替换入口）。
func _apply_icon() -> void:
	var icon_path: String = str(_record.get(KEY_ICON, ""))
	if _icon == null:
		return
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		_icon.texture = load(icon_path) as Texture2D
		_icon.visible = true
	else:
		_icon.visible = false


func _circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


# 漂浮动画（Tween 驱动，不占 _process）：只动本体位置。
func _tween_float() -> void:
	var tween: Tween = create_tween().set_loops()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", _base_y - FLOAT_AMPLITUDE, FLOAT_HALF_PERIOD)
	tween.tween_property(self, "position:y", _base_y, FLOAT_HALF_PERIOD).set_delay(FLOAT_HALF_PERIOD)


# 发光呼吸（Tween 驱动）：只动发光部件的透明度，与其他部件解耦。
func _tween_glow() -> void:
	if _glow == null:
		return
	var tween: Tween = create_tween().set_loops()
	tween.set_parallel(true)
	tween.tween_property(_glow, "modulate:a", GLOW_ALPHA_LOW, FLOAT_HALF_PERIOD)
	tween.tween_property(_glow, "modulate:a", 1.0, FLOAT_HALF_PERIOD).set_delay(FLOAT_HALF_PERIOD)


func _show_tip(tip_id: String) -> void:
	if tip_id.is_empty():
		return
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip != null:
		tip.show(tip_id)


# 拾取音效（FR-G-01 AC2）：音频资源由 P5 后补，无 stream 时静默跳过（同 explosion.gd 的做法）。
func _play_pickup_sound() -> void:
	if _pickup_audio != null and _pickup_audio.stream != null:
		_pickup_audio.play()


# 销毁时机（包A-9）：有音效在播时等播放结束再 free——立即 free 会把子节点的音频一起掐断。
# 等待期间隐藏本体；交互已由 _picked 置位挡掉。
func _free_after_sound() -> void:
	if _pickup_audio != null and _pickup_audio.playing:
		visible = false
		_pickup_audio.finished.connect(queue_free, CONNECT_ONE_SHOT)
		return
	queue_free()


# 玩家背包的约定入口（同 facility_base.gd 的鸭子类型约定）。
func _inventory_of(player: Node) -> RefCounted:
	if player == null:
		return null
	var inv: Variant = player.get("inventory")
	if inv == null or not (inv is RefCounted):
		return null
	var typed: RefCounted = inv
	if not (typed.has_method("add_item") and typed.has_method("count_of")):
		return null
	return typed
