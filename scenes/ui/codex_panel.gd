# CodexPanel（FR-U-04 / TP-16）：图鉴面板。
# 网格展示全部物质卡（条数自 RecipeDB.all_substances() 得出，不写死 17；HUD 计数口径归 Discovery/HUD，本面板不掺和）。
# 未收集为剪影不泄露名称；反应卡片页只列 RecipeDB.unlocked_recipes()，可循环翻页。
# 数据来源约束（SPEC-03 §1）：只调 RecipeDB/GameManager autoload 与注入的 Discovery，不自读数据表。
# 主菜单与游戏内实例化同一场景、喂同一状态即数据一致（FR-U-04 AC4）。
extends Control

# ==== 常量区 ====
const CELL_SCENE_PATH: String = "res://scenes/ui/codex_cell.tscn"
const DISCOVERY_SCRIPT_PATH: String = "res://scripts/gameplay/discovery.gd"
const GRID_COLUMNS: int = 6
const UI_KEY_LOCKED: String = "codex_locked"
const GAME_MANAGER_PATH: NodePath = ^"/root/GameManager"
const RECIPE_DB_PATH: NodePath = ^"/root/RecipeDB"
const CARD_KEYS: Array[String] = ["title", "equation", "body", "application", "footer"]

# ==== 状态区 ====
# 收集进度来源（TP-06 纯逻辑类）。测试/ gameplay 经 set_discovery 注入共享实例；
# 未注入时自建空集合（全部锁定），保证主菜单独立打开也不崩溃。
var _discovery: RefCounted = null
var _cells: Dictionary = {}
var _card_ids: Array[String] = []
var _card_index: int = 0

@onready var _grid: GridContainer = %Grid
@onready var _card_title: Label = %CardTitle
@onready var _card_equation: Label = %CardEquation
@onready var _card_body: Label = %CardBody
@onready var _card_application: Label = %CardApplication
@onready var _card_footer: Label = %CardFooter
@onready var _prev_button: Button = %PrevCardButton
@onready var _next_button: Button = %NextCardButton
@onready var _page_label: Label = %CardPageLabel


# ==== 逻辑区 ====
func _ready() -> void:
	if _discovery == null:
		_discovery = _default_discovery()
	_build_grid()
	_prev_button.pressed.connect(prev_card)
	_next_button.pressed.connect(next_card)
	refresh()


# 注入口（同 config_panel 的 set_client 模式）：注入后按最新状态重绘。
func set_discovery(discovery: RefCounted) -> void:
	_discovery = discovery
	if is_node_ready():
		refresh()


# 按当前收集进度与已解锁配方整体重绘。打开面板与进度变化后都应调用。
func refresh() -> void:
	_refresh_cells()
	_refresh_cards()


func cell_count() -> int:
	return _cells.size()


# 按物质 id 取格子；不存在返回 null（测试与调试查询用）。
func cell_for(substance_id: String) -> Node:
	return _cells.get(substance_id)


func card_count() -> int:
	return _card_ids.size()


func current_card_index() -> int:
	return _card_index


# 当前卡片的五字段（title/equation/body/application/footer，契约见 SPEC-03 §4 build_card）。
# 无已解锁配方时返回空字典。
func current_card() -> Dictionary:
	if _card_ids.is_empty():
		return {}
	var db: Node = get_node_or_null(RECIPE_DB_PATH)
	if db == null:
		return {}
	return db.build_card(db.get_recipe(_card_ids[_card_index]))


# 循环翻页：末页再 next 回首页，首页 prev 到末页；空态不动。
func next_card() -> void:
	if _card_ids.is_empty():
		return
	_card_index = (_card_index + 1) % _card_ids.size()
	_show_card()


func prev_card() -> void:
	if _card_ids.is_empty():
		return
	_card_index = (_card_index - 1 + _card_ids.size()) % _card_ids.size()
	_show_card()


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


# 未注入共享实例时自建空 Discovery（全部锁定），面板可独立打开（AC4）。
func _default_discovery() -> RefCounted:
	var script: Resource = load(DISCOVERY_SCRIPT_PATH)
	if script == null:
		push_warning("[codex] discovery script missing, grid stays locked")
		return null
	return script.new()


# 一格对应一条物质记录；格数自数据表得出（不写死 17）。
func _build_grid() -> void:
	var db: Node = get_node_or_null(RECIPE_DB_PATH)
	if db == null:
		push_warning("[codex] RecipeDB unavailable, codex grid is empty")
		return
	var cell_scene: PackedScene = load(CELL_SCENE_PATH)
	if cell_scene == null:
		push_warning("[codex] cell scene missing: %s" % CELL_SCENE_PATH)
		return
	_grid.columns = GRID_COLUMNS
	for substance: Dictionary in db.all_substances():
		var cell: Node = cell_scene.instantiate()
		_grid.add_child(cell)
		_cells[str(substance.get("id", ""))] = cell


func _refresh_cells() -> void:
	var db: Node = get_node_or_null(RECIPE_DB_PATH)
	if db == null:
		return
	var locked_text: String = _ui_string(UI_KEY_LOCKED)
	for substance_id: String in _cells.keys():
		var cell: Node = _cells[substance_id]
		var unlocked: bool = _discovery != null and _discovery.is_discovered(substance_id)
		cell.bind(db.get_substance(substance_id), unlocked, locked_text)


func _refresh_cards() -> void:
	var db: Node = get_node_or_null(RECIPE_DB_PATH)
	if db == null:
		_card_ids = []
	else:
		_card_ids = db.unlocked_recipes()
	if _card_ids.is_empty():
		_card_index = 0
	else:
		_card_index = clampi(_card_index, 0, _card_ids.size() - 1)
	_show_card()


func _show_card() -> void:
	var card: Dictionary = current_card()
	for key: String in CARD_KEYS:
		_card_label(key).text = str(card.get(key, ""))
	if _card_ids.is_empty():
		_page_label.text = "0/0"
	else:
		_page_label.text = "%d/%d" % [_card_index + 1, _card_ids.size()]


func _card_label(key: String) -> Label:
	match key:
		"title":
			return _card_title
		"equation":
			return _card_equation
		"body":
			return _card_body
		"application":
			return _card_application
	return _card_footer


func _ui_string(key: String) -> String:
	var gm: Node = get_node_or_null(GAME_MANAGER_PATH)
	if gm == null:
		return key
	return gm.get_ui_string(key)
