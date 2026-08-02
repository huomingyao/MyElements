# 世界总装（TP-17，SPEC-03 §8）：白盒地图 + 全部接线。
# 职责：GameManager.tick 唯一驱动、区域触发、采集物生成与清晨刷新、刷怪（CO 幽灵/酸雾怪）、
# 死亡掉落包与复活回床、昼夜 CanvasModulate、睡觉渐黑、ui_manager 面板互斥与输入屏蔽、
# 合成台/卡片/背包/图鉴/聊天框接线、use_item 快捷使用、河边引导字幕。
# 文案走数据表、数值走 balance（NFR-04）；本文件只有坐标常量（白盒布局，属场景内容而非调参）。
extends Node2D

# ==== 常量区 ====

const COLLECTABLE_SCENE: String = "res://scenes/gameplay/collectable.tscn"
const CO_GHOST_SCENE: String = "res://scenes/gameplay/monster_co_ghost.tscn"
const DROP_BAG_SCRIPT: String = "res://scenes/gameplay/drop_bag.gd"
const INVENTORY_SCRIPT: String = "res://scripts/gameplay/inventory.gd"
const ITEM_EFFECTS_SCRIPT: String = "res://scripts/gameplay/item_effects.gd"
const DISCOVERY_SCRIPT: String = "res://scripts/gameplay/discovery.gd"
const HYDROGEN_SCRIPT: String = "res://scripts/gameplay/hydrogen_event.gd"

# 白盒布局锚点（配合 maps/whitebox_map.tscn；铺图定稿后由 P5 校准）。
# 2026-08-03 等宽重排：四区画布统一 1000px 宽紧凑排列，区间 60px 缝隙由隐形触发器封住。
const PLAYER_SPAWN: Vector2 = Vector2(-340, -20)
const MAP_BOUNDS: Rect2 = Rect2(-1700, -300, 4180, 400)
const CAMP_CENTER: Vector2 = Vector2(820, -20)
const GRASS_GHOST_SPAWN: Vector2 = Vector2(-340, -30)

# FR-C-10 AC1/AC2：相机按区域钳制（四区等宽 1000 ≥640 视口，屏幕恒被当前区画布铺满），
# zone_changed 即切换；两侧不露黑边、看不到相邻区域。缺省区域回退 MAP_BOUNDS。
const ZONE_CAMERA_BOUNDS: Dictionary = {
	"saltlake": Rect2(-1700, -300, 1000, 400),
	"grassland": Rect2(-640, -300, 1000, 400),
	"camp": Rect2(420, -300, 1000, 400),
	"mine": Rect2(1480, -300, 1000, 400),
}

const BAL_NIGHT_BRIGHTNESS: String = "daynight.night_brightness"
const FALLBACK_NIGHT_BRIGHTNESS: float = 0.35

const TINT_TWEEN_SECONDS: float = 0.4
const SLEEP_FADE_SECONDS: float = 0.6
const SPRAY_TARGET_RANGE: float = 96.0

const TORCH_ITEM_ID: String = "sulfur_torch"
const ACTION_CODEX: String = "codex"
const HOTKEY_PREFIX: String = "use_item_"

# 相机震动（包A-8，对标 juice 超越点）：受伤小幅、爆炸中幅，强度克制不晕。
const HURT_SHAKE_INTENSITY: float = 2.5
const HURT_SHAKE_SECONDS: float = 0.2
const EXPLOSION_SHAKE_INTENSITY: float = 4.5
const EXPLOSION_SHAKE_SECONDS: float = 0.3

# 区域联动字幕（SPEC-02 §4.1 / SPEC-05 §3）：矿洞呼吸提示与草原光合作用横幅。
const ZONE_MINE: String = "mine"
const ZONE_GRASSLAND: String = "grassland"
const TIP_MINE_BREATH: String = "sys_mine_breath"
const TIP_PHOTOSYNTHESIS: String = "zone_photosynthesis"

# ==== 逻辑区 ====

var _inventory: RefCounted = null
var _item_effects: RefCounted = null
var _discovery: RefCounted = null
var _hydrogen: RefCounted = null
var _grass_ghost: Node2D = null
var _tint_tween: Tween = null
var _last_health: float = 0.0
# FR-C-10 AC3：黑洞过场（渐黑~渐亮）期间锁输入，travel_started/traveled 成对驱动。
var _travel_lock: bool = false

@onready var _player: Node2D = $Player
@onready var _collectables: Node2D = $Collectables
@onready var _monsters: Node2D = $Monsters
@onready var _spawner: Node2D = $Monsters/MistSpawner
@onready var _tint: CanvasModulate = $CanvasModulate
@onready var _fade: ColorRect = $FadeLayer/FadeRect
@onready var _hud: Control = $UILayer/HUD
@onready var _tip_layer: Control = $UILayer/TipLayer
@onready var _craft: Control = $UILayer/CraftPanel
@onready var _card: Control = $UILayer/CardPopup
@onready var _inventory_panel: Control = $UILayer/InventoryPanel
@onready var _codex: Control = $UILayer/CodexPanel
@onready var _ui_manager: Node = $UILayer/UIManager


func _ready() -> void:
	_reset_run()
	_setup_logic_instances()
	_setup_player()
	_setup_ui()
	_spawn_all_collectables()
	_setup_monsters()
	_connect_signals()


# GameManager.tick 的唯一驱动（SPEC-03 §2.2）；同时同步死亡点参考坐标。
func _process(delta: float) -> void:
	var gm: Node = _gm()
	if gm == null:
		return
	gm.tick(delta)
	gm.set_respawn_reference_position(_player.global_position)


# ==== 初始化 ====

# 新开局复位：三值/时钟/标记/队列/配方进度/发现集合。
func _reset_run() -> void:
	var gm: Node = _gm()
	if gm != null:
		gm.reset_clock()
		gm.reset_stats()
		gm.set_flag("explosion_happened", false)
		gm.set_flag("purity_check_unlocked", false)
		gm.set_zone("grassland")
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip != null:
		tip.clear_queue()
	var db: Node = get_node_or_null(^"/root/RecipeDB")
	if db != null:
		db.reset_unlocked()
		db.reset_rotation()


func _setup_logic_instances() -> void:
	_inventory = (load(INVENTORY_SCRIPT) as GDScript).new()
	_item_effects = (load(ITEM_EFFECTS_SCRIPT) as GDScript).new()
	_discovery = (load(DISCOVERY_SCRIPT) as GDScript).new()
	_hydrogen = (load(HYDROGEN_SCRIPT) as GDScript).new()


func _setup_player() -> void:
	_player.inventory = _inventory
	_player.item_effects = _item_effects
	_player.global_position = PLAYER_SPAWN
	_player.reset_camera_smoothing() # 包A-4：出生点传送后相机立即对齐，不慢追
	_player.set_map_bounds(_zone_camera_bounds(ZONE_GRASSLAND)) # FR-C-10：出生钳到草原
	_tip_layer.set_player(_player)
	var explosion: Node = get_node_or_null(^"Explosion")
	if explosion != null:
		explosion.bind(_hydrogen)
		explosion.set_shake_target(_player.get_node_or_null(^"%Camera"))


func _setup_ui() -> void:
	_craft.bind(_inventory)
	_craft.set_hydrogen_event(_hydrogen)
	_craft.managed = true
	_craft.card_ready.connect(_on_card_ready)
	_craft.close_requested.connect(_ui_manager.close_active)
	_inventory_panel.bind(_inventory)
	_inventory_panel.managed = true
	_inventory_panel.toggle_requested.connect(_ui_manager.toggle.bind("inventory"))
	_inventory_panel.craft_requested.connect(_ui_manager.toggle.bind("craft"))
	_codex.set_discovery(_discovery)
	_ui_manager.register_panel("craft", _craft, true, "crafting")
	_ui_manager.register_panel("inventory", _inventory_panel, true, "crafting")
	_ui_manager.register_panel("codex", _codex, true)
	# 导师室（独立页）：注册为模态面板，聊天框内嵌其中，不再单列 ui_manager 面板。
	var room: Node = get_node_or_null(^"UILayer/MentorRoom")
	if room != null:
		_ui_manager.register_panel("mentor_room", room, true)
		room.close_requested.connect(_ui_manager.close_active)
		room.set_hydrogen_event(_hydrogen)
	_ui_manager.active_changed.connect(_on_ui_active_changed)


# ==== 采集物（FR-G-01 接线 / FR-C-05 AC3 刷新） ====

func _spawn_all_collectables() -> void:
	for child: Node in _collectables.get_children():
		child.queue_free()
	var markers: Node = get_node_or_null(^"Map/CollectableSpawns")
	if markers == null:
		push_warning("[world] 白盒地图缺 CollectableSpawns")
		return
	var packed: PackedScene = load(COLLECTABLE_SCENE) as PackedScene
	for marker: Node in markers.get_children():
		if not (marker is Marker2D):
			continue
		var substance_id: String = str(marker.get_meta("substance_id", ""))
		if substance_id.is_empty():
			continue
		var node: Node2D = packed.instantiate()
		# 先入 id 再进树：_ready 里的记录解析需要 substance_id 已就位。
		node.setup(substance_id)
		# 包A-3：先定位再入树——collectable._ready 会以当前 y 为漂浮基准并启动 Tween，
		# 入树后再挪位置会被 Tween 拉回错误高度（_base_y=0）。
		node.global_position = (marker as Marker2D).global_position
		_collectables.add_child(node)
		node.collected.connect(_on_collectable_collected)


func _on_collectable_collected(substance_id: String) -> void:
	if _discovery != null:
		_discovery.discover(substance_id)


func _respawn_collectables() -> void:
	_spawn_all_collectables()


# ==== 刷怪（FR-G-10 / FR-G-11 接线） ====

func _setup_monsters() -> void:
	_spawner.camp_center = CAMP_CENTER
	_spawner.target_player = _player
	for child: Node in _monsters.get_children():
		if child.has_method("drift_step"):
			child.target_player = _player


# 草原夜晚的 CO 幽灵（矿洞两只常驻，由场景自带）。
func _spawn_grass_ghost() -> void:
	if _grass_ghost != null and is_instance_valid(_grass_ghost):
		return
	var packed: PackedScene = load(CO_GHOST_SCENE) as PackedScene
	_grass_ghost = packed.instantiate()
	_grass_ghost.name = "GrassGhost"
	_monsters.add_child(_grass_ghost)
	_grass_ghost.global_position = GRASS_GHOST_SPAWN
	_grass_ghost.target_player = _player


func _clear_grass_ghost() -> void:
	if _grass_ghost != null and is_instance_valid(_grass_ghost):
		_grass_ghost.queue_free()
	_grass_ghost = null


# ==== 信号接线 ====

func _connect_signals() -> void:
	var gm: Node = _gm()
	if gm == null:
		return
	gm.resources_respawned.connect(_respawn_collectables)
	gm.player_died.connect(_on_player_died)
	gm.player_respawned.connect(_on_player_respawned)
	gm.night_started.connect(_on_night_started)
	gm.day_started.connect(_on_day_started)
	gm.zone_changed.connect(_on_zone_changed)
	gm.health_changed.connect(_on_health_changed)
	_last_health = float(gm.health)
	if _hydrogen != null and _hydrogen.has_signal("explosion_triggered"):
		_hydrogen.explosion_triggered.connect(_on_explosion_shake)
	if _discovery != null:
		_discovery.substance_discovered.connect(_on_substance_discovered)
	var bench: Node = get_node_or_null(^"Facilities/FacilityBench")
	if bench != null and bench.has_signal("craft_requested"):
		bench.craft_requested.connect(_on_craft_requested)
	# 提纯三步完成的卡片接线（FR-G-14 AC2）：复用合成卡片弹窗路径。
	if bench != null and bench.has_signal("card_ready"):
		bench.card_ready.connect(_on_card_ready)
	var bed: Node = get_node_or_null(^"Facilities/FacilityBed")
	if bed != null and bed.has_signal("slept"):
		bed.slept.connect(_on_bed_slept)
	_card.closed.connect(_on_card_closed)
	var wm: Node = get_node_or_null(^"/root/WorldMap")
	if wm != null:
		wm.map_opened.connect(_sync_input_block)
		wm.map_closed.connect(_sync_input_block)
	var pause: Node = get_node_or_null(^"UILayer/PauseMenu")
	if pause != null:
		pause.pause_toggled.connect(_on_pause_toggled)
	# FR-C-10 AC3：黑洞过场锁输入（travel_started 渐黑开始锁，traveled 渐亮结束解锁）。
	var holes: Node = get_node_or_null(^"BlackHoles")
	if holes != null:
		for hole: Node in holes.get_children():
			if hole.has_signal("travel_started"):
				hole.travel_started.connect(_on_travel_started)
			if hole.has_signal("traveled"):
				hole.traveled.connect(_on_traveled)


func _on_substance_discovered(_substance_id: String) -> void:
	_hud.set_collected(_discovery.counted_count())


# 死亡：背包快照进掉落包（死亡点）、清空背包；死亡画面自己监听 player_died 弹出。
func _on_player_died(death_position: Vector2) -> void:
	var items: Array = []
	if _inventory != null:
		items = _inventory.slots()
	var bag: Node = (load(DROP_BAG_SCRIPT) as GDScript).spawn_at(self, death_position, items)
	if bag != null:
		bag.set_inventory(_inventory)
	if _inventory != null:
		_inventory.clear()


# 复活：位置回营地床，三值已由 GameManager 回满。
func _on_player_respawned() -> void:
	var bed: Node = get_node_or_null(^"Facilities/FacilityBed")
	if bed != null:
		_player.global_position = bed.global_position
		_player.reset_camera_smoothing() # 包A-4：横跨地图传送后相机立即对齐
	_sync_input_block()


func _on_night_started(_day_count: int) -> void:
	_tween_tint(_night_brightness())
	_spawn_grass_ghost()


func _on_day_started(_day_count: int) -> void:
	_tween_tint(1.0)
	_clear_grass_ghost()


# 区域联动字幕：进矿洞且氧气净速率为负时提示通风原理（SPEC-02 §4.1）；
# 草原白天首次进入时触发光合作用横幅（SPEC-05 §3.1，夜晚不触发）。均走 show_once 去重。
# FR-C-10 AC1：切区即切换相机钳制矩形，触碰边界黑洞前看不到相邻区域。
# 同时收敛相机平滑：复活回床等跨区传送后旧钳制会把相机夹在目标区外，
# 切区时不同步 snap 的话相机会从错误夹位慢滑回玩家。
func _on_zone_changed(zone_id: String) -> void:
	_player.set_map_bounds(_zone_camera_bounds(zone_id))
	_player.reset_camera_smoothing()
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip == null:
		return
	var gm: Node = _gm()
	if zone_id == ZONE_MINE and gm != null and float(gm.oxygen_net_rate()) < 0.0:
		tip.show_once(TIP_MINE_BREATH)
	if zone_id == ZONE_GRASSLAND and gm != null and not bool(gm.is_night()):
		tip.show_once(TIP_PHOTOSYNTHESIS)


func _zone_camera_bounds(zone_id: String) -> Rect2:
	return ZONE_CAMERA_BOUNDS.get(zone_id, MAP_BOUNDS)


func _tween_tint(brightness: float) -> void:
	if _tint_tween != null and _tint_tween.is_valid():
		_tint_tween.kill()
	_tint_tween = create_tween()
	_tint_tween.tween_property(_tint, "color", Color(brightness, brightness, brightness), TINT_TWEEN_SECONDS)


func _night_brightness() -> float:
	var gm: Node = _gm()
	if gm == null:
		return FALLBACK_NIGHT_BRIGHTNESS
	return float(gm.get_balance(BAL_NIGHT_BRIGHTNESS, FALLBACK_NIGHT_BRIGHTNESS))


# ==== 面板与输入屏蔽（SPEC-03 §8） ====

func _on_craft_requested(_player_node: Node) -> void:
	# FR-G-05 AC5：合成台打开时背包同屏并列（先背包后合成台，合成台在最上）。
	_ui_manager.open("inventory")
	_ui_manager.open("craft")


func _on_card_ready(card: Dictionary) -> void:
	_card.show_card(card)
	_sync_input_block()


func _on_card_closed() -> void:
	_sync_input_block()


func _on_ui_active_changed(_active: String) -> void:
	_sync_input_block()


# 黑洞过场开始（渐黑）：锁输入，防止过场中走出落点或穿帮。
func _on_travel_started() -> void:
	_travel_lock = true
	_sync_input_block()


# 黑洞过场结束（渐亮完）：解锁。落点 ZoneTrigger 已负责切区与相机钳制。
func _on_traveled(_from_zone: String, _to_zone: String) -> void:
	_travel_lock = false
	_sync_input_block()


# 包A-1：暂停菜单真暂停——菜单开关即场景树开关（三值 tick、怪物随之停住）；
# 菜单本体 process_mode=ALWAYS（pause_menu.tscn），暂停后按钮仍可用。
func _on_pause_toggled(open: bool) -> void:
	get_tree().paused = open
	_sync_input_block()


# ==== 相机震动接线（包A-8） ====

# 受伤相机震动：只震下降沿（回血/复位不震）；缺氧持续掉血时形成持续轻震反馈。
func _on_health_changed(current: float, _max_value: float) -> void:
	if current < _last_health:
		_shake_camera(HURT_SHAKE_INTENSITY, HURT_SHAKE_SECONDS)
	_last_health = current


func _on_explosion_shake() -> void:
	_shake_camera(EXPLOSION_SHAKE_INTENSITY, EXPLOSION_SHAKE_SECONDS)


func _shake_camera(intensity: float, duration: float) -> void:
	var camera: Node = _player.get_node_or_null(^"%Camera")
	if camera != null and camera.has_method("shake"):
		camera.shake(intensity, duration)


# 屏蔽输入的合取：模态面板（ui_manager）、卡片弹窗、世界地图页、暂停菜单、死亡画面、黑洞过场。
func _sync_input_block() -> void:
	var blocked: bool = _ui_manager.input_blocked() or _card.is_open() or _travel_lock
	var wm: Node = get_node_or_null(^"/root/WorldMap")
	if wm != null and bool(wm.is_open()):
		blocked = true
	var pause: Node = get_node_or_null(^"UILayer/PauseMenu")
	if pause != null and pause.visible:
		blocked = true
	var death: Node = get_node_or_null(^"UILayer/DeathScreen")
	if death != null and death.is_open():
		blocked = true
	_player.input_blocked = blocked


# 睡觉渐黑（FR-C-05 表现段）：先压黑再淡回。
func _on_bed_slept() -> void:
	_fade.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, SLEEP_FADE_SECONDS)


# ==== 快捷栏与图鉴热键 ====

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_CODEX):
		# 图鉴 C 键例外放行（包A-2）：图鉴自身是模态面板，屏蔽后 C 键将无法关闭它。
		_codex.set_discovery(_discovery)
		_ui_manager.toggle("codex")
		get_viewport().set_input_as_handled()
		return
	# 包A-2：模态面板/卡片/地图/暂停/死亡画面打开时，快捷栏数字键不生效。
	if bool(_player.input_blocked):
		return
	for i: int in range(1, 9):
		if event.is_action_pressed("%s%d" % [HOTKEY_PREFIX, i]):
			_use_hotbar_slot(i - 1)
			get_viewport().set_input_as_handled()
			return


# 数字键使用快捷栏第 N 格（FR-G-12 接线）：交易态下路由给原住民（FR-G-15）；
# 装备型切换装备，消耗型结算效果（砸怪类自动找范围内目标）。
# 砸空反馈：use_item 返回 no_target 时播 sys_no_target（修复：返回值曾被丢弃，按键零反馈）。
const TIP_NO_TARGET: String = "sys_no_target"

func _use_hotbar_slot(index: int) -> void:
	if _inventory == null or _item_effects == null:
		return
	var trader: Node = get_node_or_null(^"Facilities/NativeTrader")
	if trader != null and bool(trader.is_trading()):
		trader.sell_slot(index)
		return
	var slots: Array = _inventory.slots()
	if index < 0 or index >= slots.size():
		return
	var item_id: String = str(slots[index].get("id", ""))
	if item_id.is_empty():
		return
	if bool(_item_effects.is_equipment(item_id)):
		if bool(_item_effects.is_equipped(item_id)):
			_item_effects.unequip(item_id)
		else:
			_item_effects.equip(item_id)
		_player.set_torch_equipped(bool(_item_effects.is_equipped(TORCH_ITEM_ID)))
		return
	var result: Dictionary = _item_effects.use_item(item_id, _inventory, _nearest_target_for(item_id))
	if not bool(result.get("success", false)) and str(result.get("reason", "")) == "no_target":
		var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
		if tip != null:
			tip.show(TIP_NO_TARGET)


# 砸怪类道具的目标：按效果找范围内最近的可消灭对象（kill_acid→酸雾怪，kill_co→CO 幽灵）。
const EFFECT_TARGET_METHODS: Dictionary = {
	"kill_acid": "hit_by_spray",
	"kill_co": "hit_by_carbon",
}


func _nearest_target_for(item_id: String) -> Node:
	var item: Dictionary = _item_effects.get_item(item_id)
	var method: String = str(EFFECT_TARGET_METHODS.get(str(item.get("effect", "")), ""))
	if method.is_empty():
		return null
	# 递归收集：酸雾怪挂在 MistSpawner 下（孙节点），只看直接子节点会永远找不到喷雾目标。
	var candidates: Array = []
	_collect_target_candidates(_monsters, method, candidates)
	var best: Node = null
	var best_dist: float = SPRAY_TARGET_RANGE
	for child: Node in candidates:
		var dist: float = (child as Node2D).global_position.distance_to(_player.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = child
	return best


func _collect_target_candidates(node: Node, method: String, out: Array) -> void:
	for child: Node in node.get_children():
		if child.has_method(method):
			out.append(child)
		_collect_target_candidates(child, method, out)


func _gm() -> Node:
	return get_node_or_null(^"/root/GameManager")
