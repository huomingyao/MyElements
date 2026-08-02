# UIManager（SPEC-03 §8）：模态面板互斥裁决 + 玩家输入屏蔽。
# 默认同一时刻只允许一个模态面板；登记为同组（group 相同且非空）的面板可同屏并列
# （当前仅背包+合成台的 crafting 组，FR-G-05 AC5），跨组打开仍互斥，Esc 逐层关最上面板。
# 打开时屏蔽玩家输入，聊天框例外（FR-M-02 AC1：世界不暂停）。
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

# name -> {"node": Node, "blocks_input": bool, "group": String}
var _panels: Dictionary = {}
# 打开顺序栈，栈底先开、栈顶为最上面板；同组面板可共存于栈中。
var _open_order: Array[String] = []
var _pause_menu: Control = null
var _death_screen: Node = null
# 关闭重入保护：面板 close() 可能回发 close_requested，关闭过程中忽略二次关闭请求。
var _closing: bool = false


# 注册面板。blocks_input=false 的是聊天框这类不打断世界的面板；
# group 非空且相同的面板允许同屏并列（SPEC-03 §8，FR-G-05 AC5）。
func register_panel(panel_name: String, node: Node, blocks_input: bool = true, group: String = "") -> void:
	if node == null:
		push_warning("[ui] 注册空面板：%s（忽略）" % panel_name)
		return
	_panels[panel_name] = {"node": node, "blocks_input": blocks_input, "group": group}


# 打开指定面板：与最上面板同组则并列叠上（不关当前），否则先关全部再开（互斥）。
# 模态不叠开：暂停菜单打开时拒绝；世界地图页打开时先关掉再开。
func open(panel_name: String) -> void:
	var entry: Variant = _panels.get(panel_name, {})
	if entry.is_empty():
		push_warning("[ui] 未注册的面板：%s（忽略）" % panel_name)
		return
	if is_open(panel_name):
		return
	if _pause_visible():
		return
	_close_world_map_if_open()
	if not _open_order.is_empty() and not _coexists_with_top(panel_name):
		close_all()
	_open_order.append(panel_name)
	((entry as Dictionary)["node"] as Node).open()
	active_changed.emit(active_panel())


# 关闭最上面板；无打开时调用安全。先出栈再通知面板：
# 面板 close() 可能回发 close_requested（重入），由 _closing 挡住。
func close_active() -> void:
	if _open_order.is_empty() or _closing:
		return
	_closing = true
	_close_panel(_open_order.back())
	_closing = false
	active_changed.emit(active_panel())


# 关闭全部已开面板（跨组互斥与场景清理用）。
func close_all() -> void:
	if _open_order.is_empty() or _closing:
		return
	_closing = true
	while not _open_order.is_empty():
		_close_panel(_open_order.back())
	_closing = false
	active_changed.emit(active_panel())


# 指定面板的开关请求（Tab/X 这类触发经面板转发到这里，保证互斥不被绕过）。
func toggle(panel_name: String) -> void:
	if is_open(panel_name):
		if _closing:
			return
		_closing = true
		_close_panel(panel_name)
		_closing = false
		active_changed.emit(active_panel())
	else:
		open(panel_name)


func is_open(panel_name: String) -> bool:
	return _open_order.has(panel_name)


# 面板是否已注册（世界接线自检与测试用）。
func has_panel(panel_name: String) -> bool:
	return _panels.has(panel_name)


# 最上面板（激活面板）；全关时为空串。
func active_panel() -> String:
	if _open_order.is_empty():
		return ""
	return _open_order.back()


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
		if not _open_order.is_empty():
			close_active()
			get_viewport().set_input_as_handled()
			return
		if _close_world_map_if_open():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_WORLDMAP):
		if not _open_order.is_empty() or _pause_visible():
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


# 当前是否应屏蔽玩家输入（任一打开的是屏蔽类面板时才屏蔽）。
func input_blocked() -> bool:
	for panel_name: String in _open_order:
		var entry: Dictionary = _panels.get(panel_name, {})
		if bool(entry.get("blocks_input", true)):
			return true
	return false


# 待开面板能否与最上面板同屏并列：两者 group 相同且非空。
func _coexists_with_top(panel_name: String) -> bool:
	var top_entry: Dictionary = _panels.get(_open_order.back(), {})
	var new_entry: Dictionary = _panels.get(panel_name, {})
	var top_group: String = str(top_entry.get("group", ""))
	var new_group: String = str(new_entry.get("group", ""))
	return not top_group.is_empty() and top_group == new_group


# 出栈并关闭指定面板（调用方负责重入保护与发信号）。
func _close_panel(panel_name: String) -> void:
	_open_order.erase(panel_name)
	var entry: Dictionary = _panels.get(panel_name, {})
	if not entry.is_empty():
		(entry["node"] as Node).close()
