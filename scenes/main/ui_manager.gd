# UIManager（SPEC-03 §8）：模态面板互斥裁决 + 玩家输入屏蔽。
# 同一时刻只允许一个模态面板；打开时屏蔽玩家输入，聊天框例外（FR-M-02 AC1：世界不暂停）。
# 本节点不做任何显示，只做状态裁决；面板自身负责 open()/close()/is_open()。
extends Node

# 当前面板变化（空串 = 全部关闭）；世界据此同步玩家 input_blocked。
signal active_changed(active_name: String)

# ==== 常量区 ====

const ACTION_PAUSE: String = "pause"
const ACTION_WORLDMAP: String = "worldmap"
# 暂停菜单不经 register_panel（兄弟节点，显隐即状态）；裁决时按路径惰性解析。
const PAUSE_MENU_PATH: NodePath = ^"../PauseMenu"
# 死亡画面同为兄弟节点（收口 W1）：打开时 Esc 吞掉，不叠开暂停菜单、不误触确认。
const DEATH_SCREEN_PATH: NodePath = ^"../DeathScreen"

# ==== 逻辑区 ====

# name -> {"node": Node, "blocks_input": bool}
var _panels: Dictionary = {}
var _active: String = ""
var _pause_menu: Control = null
var _death_screen: Node = null


# 注册面板。blocks_input=false 的是聊天框这类不打断世界的面板。
func register_panel(panel_name: String, node: Node, blocks_input: bool = true) -> void:
	if node == null:
		push_warning("[ui] 注册空面板：%s（忽略）" % panel_name)
		return
	_panels[panel_name] = {"node": node, "blocks_input": blocks_input}


# 打开指定面板：先关当前（互斥），再开新的。
# 模态不叠开：暂停菜单打开时拒绝；世界地图页打开时先关掉再开。
func open(panel_name: String) -> void:
	var entry: Variant = _panels.get(panel_name, {})
	if entry.is_empty():
		push_warning("[ui] 未注册的面板：%s（忽略）" % panel_name)
		return
	if _active == panel_name:
		return
	if _pause_visible():
		return
	_close_world_map_if_open()
	close_active()
	_active = panel_name
	(entry as Dictionary)["node"].open()
	active_changed.emit(_active)


# 关闭当前面板；无打开时调用安全。先清 _active 再通知面板：
# 面板 close() 可能回发 close_requested，避免递归。
func close_active() -> void:
	if _active.is_empty():
		return
	var entry: Dictionary = _panels.get(_active, {})
	_active = ""
	if not entry.is_empty():
		(entry["node"] as Node).close()
	active_changed.emit(_active)


# 指定面板的开关请求（Tab 这类触发经面板转发到这里，保证互斥不被绕过）。
func toggle(panel_name: String) -> void:
	if _active == panel_name:
		close_active()
	else:
		open(panel_name)


func is_open(panel_name: String) -> bool:
	return _active == panel_name


# 面板是否已注册（世界接线自检与测试用）。
func has_panel(panel_name: String) -> bool:
	return _panels.has(panel_name)


func active_panel() -> String:
	return _active


# 统一裁决（SPEC-03 §8，包E）：Esc/M 在 _input 层截流——set_input_as_handled 之后
# 事件不再进 _unhandled_input，pause_menu / world_map_panel 各自的热键处理自然失效。
# Esc：有管理面板先关最上面板，其次关世界地图页，全部关闭后才放行给暂停菜单。
# M：已有模态（管理面板或暂停菜单）打开时吞掉，不叠开地图页；否则放行。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_PAUSE):
		# 死亡画面打开时 Esc 吞掉（收口 W1）：不叠开暂停菜单，
		# 也不放行给死亡画面的任意键确认——死亡画面只能按非 Esc 键确认复活。
		if _death_visible():
			get_viewport().set_input_as_handled()
			return
		if not _active.is_empty():
			close_active()
			get_viewport().set_input_as_handled()
			return
		if _close_world_map_if_open():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_WORLDMAP):
		if not _active.is_empty() or _pause_visible():
			get_viewport().set_input_as_handled()


# 暂停菜单可见性（惰性解析；独立实例化时无兄弟节点，返回 false 不影响既有行为）。
func _pause_visible() -> bool:
	if _pause_menu == null:
		_pause_menu = get_node_or_null(PAUSE_MENU_PATH) as Control
	return _pause_menu != null and _pause_menu.visible


# 死亡画面可见性（惰性解析兄弟节点；节点被释放后重新解析，独立实例化时返回 false）。
func _death_visible() -> bool:
	if _death_screen == null or not is_instance_valid(_death_screen):
		_death_screen = get_node_or_null(DEATH_SCREEN_PATH)
	if _death_screen == null:
		return false
	if _death_screen.has_method("is_open"):
		return bool(_death_screen.is_open())
	return bool(_death_screen.get("visible"))


# 世界地图页（autoload）若开着则关闭；返回是否发生了关闭。
func _close_world_map_if_open() -> bool:
	var wm: Node = get_node_or_null(^"/root/WorldMap")
	if wm != null and bool(wm.is_open()):
		wm.close()
		return true
	return false


# 当前是否应屏蔽玩家输入（打开的是屏蔽类面板时才屏蔽）。
func input_blocked() -> bool:
	if _active.is_empty():
		return false
	var entry: Dictionary = _panels.get(_active, {})
	return bool(entry.get("blocks_input", true))
