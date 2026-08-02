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
const PLAYER_SPAWN: Vector2 = Vector2(-400, -20)
const MAP_BOUNDS: Rect2 = Rect2(-1700, -300, 4100, 400)
const CAMP_CENTER: Vector2 = Vector2(1000, -20)
const GRASS_GHOST_SPAWN: Vector2 = Vector2(-400, -30)
# D2：主菜单学院门的出生点（学院建筑在 (-110, -40)，门口取建筑正前方）。
const ACADEMY_GATE_SPAWN: Vector2 = Vector2(-110, 40)
const SPAWN_OVERRIDE_META: String = "world_spawn_override"
const SPAWN_ACADEMY_GATE: String = "academy_gate"

const BAL_NIGHT_BRIGHTNESS: String = "daynight.night_brightness"
const FALLBACK_NIGHT_BRIGHTNESS: float = 0.35

const TINT_TWEEN_SECONDS: float = 0.4
const SLEEP_FADE_SECONDS: float = 0.6
const SPRAY_TARGET_RANGE: float = 96.0

const TORCH_ITEM_ID: String = "sulfur_torch"
const ACTION_CODEX: String = "codex"
const HOTKEY_PREFIX: String = "use_item_"

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


# D2：主菜单学院门经树根元数据传出生点覆盖（一次性，消费即删）。
func _resolve_spawn_point() -> Vector2:
	var root: Window = get_tree().root
	if root.has_meta(SPAWN_OVERRIDE_META):
		var override_value: String = str(root.get_meta(SPAWN_OVERRIDE_META))
		root.remove_meta(SPAWN_OVERRIDE_META)
		if override_value == SPAWN_ACADEMY_GATE:
			return ACADEMY_GATE_SPAWN
	return PLAYER_SPAWN


func _setup_player() -> void:
	_player.inventory = _inventory
	_player.item_effects = _item_effects
	_player.global_position = _resolve_spawn_point()
	_player.set_map_bounds(MAP_BOUNDS)
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
	_codex.set_discovery(_discovery)
	_ui_manager.register_panel("craft", _craft, true)
	_ui_manager.register_panel("inventory", _inventory_panel, true)
	_ui_manager.register_panel("codex", _codex, true)
	var chat: Node = get_node_or_null(^"AcademyBuilding/%ChatPanel")
	if chat != null:
		_ui_manager.register_panel("chat", chat, false)
		chat.set_hydrogen_event(_hydrogen)
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
		_collectables.add_child(node)
		node.global_position = (marker as Marker2D).global_position
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
	if _discovery != null:
		_discovery.substance_discovered.connect(_on_substance_discovered)
	var bench: Node = get_node_or_null(^"Facilities/FacilityBench")
	if bench != null and bench.has_signal("craft_requested"):
		bench.craft_requested.connect(_on_craft_requested)
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
	_sync_input_block()


func _on_night_started(_day_count: int) -> void:
	_tween_tint(_night_brightness())
	_spawn_grass_ghost()


func _on_day_started(_day_count: int) -> void:
	_tween_tint(1.0)
	_clear_grass_ghost()


# 区域联动字幕：进矿洞且氧气净速率为负时提示通风原理（SPEC-02 §4.1）；
# 草原白天首次进入时触发光合作用横幅（SPEC-05 §3.1，夜晚不触发）。均走 show_once 去重。
func _on_zone_changed(zone_id: String) -> void:
	var tip: Node = get_node_or_null(^"/root/KnowledgeTip")
	if tip == null:
		return
	var gm: Node = _gm()
	if zone_id == ZONE_MINE and gm != null and float(gm.oxygen_net_rate()) < 0.0:
		tip.show_once(TIP_MINE_BREATH)
	if zone_id == ZONE_GRASSLAND and gm != null and not bool(gm.is_night()):
		tip.show_once(TIP_PHOTOSYNTHESIS)


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
	_ui_manager.open("craft")


func _on_card_ready(card: Dictionary) -> void:
	_card.show_card(card)
	_sync_input_block()


func _on_card_closed() -> void:
	_sync_input_block()


func _on_ui_active_changed(_active: String) -> void:
	_sync_input_block()


func _on_pause_toggled(_open: bool) -> void:
	_sync_input_block()


# 屏蔽输入的合取：模态面板（ui_manager）、卡片弹窗、世界地图页、暂停菜单、死亡画面。
func _sync_input_block() -> void:
	var blocked: bool = _ui_manager.input_blocked() or _card.is_open()
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
		_codex.set_discovery(_discovery)
		_ui_manager.toggle("codex")
		get_viewport().set_input_as_handled()
		return
	for i: int in range(1, 9):
		if event.is_action_pressed("%s%d" % [HOTKEY_PREFIX, i]):
			_use_hotbar_slot(i - 1)
			get_viewport().set_input_as_handled()
			return


# 数字键使用快捷栏第 N 格（FR-G-12 接线）：交易态下路由给原住民（FR-G-15）；
# 装备型切换装备，消耗型结算效果（砸怪类自动找范围内目标）。
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
	_item_effects.use_item(item_id, _inventory, _nearest_target_for(item_id))


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
	var best: Node = null
	var best_dist: float = SPRAY_TARGET_RANGE
	for child: Node in _monsters.get_children():
		if not child.has_method(method):
			continue
		var dist: float = (child as Node2D).global_position.distance_to(_player.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = child
	return best


func _gm() -> Node:
	return get_node_or_null(^"/root/GameManager")
