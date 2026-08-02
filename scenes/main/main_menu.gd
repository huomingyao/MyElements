# 主菜单（FR-C-08）：开始冒险 / 导师学院 / 图鉴 三个门 + 退出。
# 场景切换走可注入的导航回调（SPEC-06 §3 可测性）；目标场景未交付时警告不崩溃（并行开发期）。
# 托管 WorldMapPanel：主菜单内按 M 可打开世界地图页（FR-U-03 AC1 入口之一）。
extends Control

# ==== 常量区 ====

# 世界/图鉴场景路径由 SPEC-03 §8 钉死与 TP-12/TP-16 交付约定。
# D2（2026-08-02）：学院门不再进独立学院场景，而是加载世界场景 + 一次性出生点覆盖。
const WORLD_SCENE_PATH: String = "res://scenes/main/world.tscn"
const CODEX_SCENE_PATH: String = "res://scenes/ui/codex_panel.tscn"
const SPAWN_OVERRIDE_META: String = "world_spawn_override"
const SPAWN_ACADEMY_GATE: String = "academy_gate"

const UI_MENU_START: String = "menu_start"
const UI_MENU_ACADEMY: String = "menu_academy"
const UI_MENU_CODEX: String = "menu_codex"
const UI_MENU_QUIT: String = "menu_quit"

# ==== 逻辑区 ====

var _navigator: Callable = Callable()
var _quitter: Callable = Callable()

@onready var _start_button: Button = %StartButton
@onready var _academy_button: Button = %AcademyButton
@onready var _codex_button: Button = %CodexButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_apply_labels()
	_start_button.pressed.connect(start_game)
	_academy_button.pressed.connect(open_academy)
	_codex_button.pressed.connect(open_codex)
	_quit_button.pressed.connect(quit_game)


# 注入场景切换出口（测试用）；签名 func(path: String) -> void。
func set_navigator(navigator: Callable) -> void:
	_navigator = navigator


# 注入退出出口（测试用，绝不真退）；签名 func() -> void。
func set_quitter(quitter: Callable) -> void:
	_quitter = quitter


func start_game() -> void:
	_navigate(WORLD_SCENE_PATH)


# D2：学院门加载世界场景，出生点改为学院门口（world._ready 消费该元数据，一次性）。
func open_academy() -> void:
	get_tree().root.set_meta(SPAWN_OVERRIDE_META, SPAWN_ACADEMY_GATE)
	_navigate(WORLD_SCENE_PATH)


func open_codex() -> void:
	_navigate(CODEX_SCENE_PATH)


func quit_game() -> void:
	if _quitter.is_valid():
		_quitter.call()
		return
	get_tree().quit()


func _navigate(path: String) -> void:
	if _navigator.is_valid():
		_navigator.call(path)
		return
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		push_warning("[menu] 目标场景尚未交付：%s（忽略）" % path)


func _apply_labels() -> void:
	_start_button.text = _ui(UI_MENU_START)
	_academy_button.text = _ui(UI_MENU_ACADEMY)
	_codex_button.text = _ui(UI_MENU_CODEX)
	_quit_button.text = _ui(UI_MENU_QUIT)


func _ui(key: String) -> String:
	var gm: Node = get_node_or_null(^"/root/GameManager")
	if gm == null:
		return key
	return gm.get_ui_string(key)
