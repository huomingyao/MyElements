# UIManager（SPEC-03 §8）：模态面板互斥裁决 + 玩家输入屏蔽。
# 同一时刻只允许一个模态面板；打开时屏蔽玩家输入，聊天框例外（FR-M-02 AC1：世界不暂停）。
# 本节点不做任何显示，只做状态裁决；面板自身负责 open()/close()/is_open()。
extends Node

# 当前面板变化（空串 = 全部关闭）；世界据此同步玩家 input_blocked。
signal active_changed(active_name: String)

# ==== 逻辑区 ====

# name -> {"node": Node, "blocks_input": bool}
var _panels: Dictionary = {}
var _active: String = ""


# 注册面板。blocks_input=false 的是聊天框这类不打断世界的面板。
func register_panel(panel_name: String, node: Node, blocks_input: bool = true) -> void:
	if node == null:
		push_warning("[ui] 注册空面板：%s（忽略）" % panel_name)
		return
	_panels[panel_name] = {"node": node, "blocks_input": blocks_input}


# 打开指定面板：先关当前（互斥），再开新的。
func open(panel_name: String) -> void:
	var entry: Variant = _panels.get(panel_name, {})
	if entry.is_empty():
		push_warning("[ui] 未注册的面板：%s（忽略）" % panel_name)
		return
	if _active == panel_name:
		return
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


# 当前是否应屏蔽玩家输入（打开的是屏蔽类面板时才屏蔽）。
func input_blocked() -> bool:
	if _active.is_empty():
		return false
	var entry: Dictionary = _panels.get(_active, {})
	return bool(entry.get("blocks_input", true))
