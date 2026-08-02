# 面板互斥裁决（SPEC-03 §8，对标优化包E）：ui_manager 统一裁决 Esc / M 热键——
# 模态面板打开时 Esc 先关最上面板，全部关闭后才轮到暂停菜单；
# 已有模态（管理面板 / 世界地图页 / 暂停菜单）打开时热键不再叠开。
# pause_menu 与 world_map_panel 不改：裁决只收口在 ui_manager 的 _input 与 open()。
extends GutTest

const UI_MANAGER_SCRIPT: String = "res://scenes/main/ui_manager.gd"
const ACTION_PAUSE: String = "pause"
const ACTION_WORLDMAP: String = "worldmap"


# 通用假面板：open/close/is_open 契约同 craft/inventory。
class FakePanel:
	extends Control
	var _open: bool = false

	func open() -> void:
		_open = true
		visible = true

	func close() -> void:
		_open = false
		visible = false

	func is_open() -> bool:
		return _open


# 暂停菜单替身：复刻 pause_menu 的 Esc 开关行为（visible 即状态，走 _unhandled_input）。
class FakePauseMenu:
	extends Control

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("pause"):
			visible = not visible
			get_viewport().set_input_as_handled()


# 死亡画面替身：复刻 death_screen 的「任意键确认复活」行为（visible/is_open 即状态）。
# confirmed 记录 Esc 是否误触了确认——裁决正确时它永远不该被置真。
class FakeDeathScreen:
	extends Control
	var _open: bool = false
	var confirmed: bool = false

	func open() -> void:
		_open = true
		visible = true

	func close() -> void:
		_open = false
		visible = false

	func is_open() -> bool:
		return _open

	func _unhandled_input(event: InputEvent) -> void:
		if not _open:
			return
		if event.is_action_pressed("pause"):
			confirmed = true
			get_viewport().set_input_as_handled()


# 世界地图页替身：复刻 world_map_panel 的 M 键开关（走 _unhandled_input + WorldMap autoload）。
class FakeMapPanel:
	extends Control

	func _unhandled_input(event: InputEvent) -> void:
		if not event.is_action_pressed("worldmap"):
			return
		var wm: Node = get_node_or_null(^"/root/WorldMap")
		if wm == null:
			return
		if bool(wm.is_open()):
			wm.close()
		else:
			wm.open()
		get_viewport().set_input_as_handled()


var _rig: Node = null
var _manager: Node = null
var _pause: Control = null
var _map_panel: Control = null
var _death: Control = null
var _panel: Control = null
var _wm: Node = null


func before_each() -> void:
	_wm = Engine.get_main_loop().root.get_node_or_null(^"WorldMap")
	assert_not_null(_wm, "WorldMap autoload 必须存在")
	if _wm != null and bool(_wm.is_open()):
		_wm.close()
	_rig = Node.new()
	add_child_autofree(_rig)
	_manager = (load(UI_MANAGER_SCRIPT) as GDScript).new()
	_rig.add_child(_manager)
	_pause = FakePauseMenu.new()
	_pause.name = "PauseMenu"
	_pause.visible = false
	_rig.add_child(_pause)
	_map_panel = FakeMapPanel.new()
	_rig.add_child(_map_panel)
	_death = FakeDeathScreen.new()
	_death.name = "DeathScreen" # ui_manager 按兄弟节点名惰性解析
	_death.visible = false
	_rig.add_child(_death)
	_panel = FakePanel.new()
	add_child_autofree(_panel)
	_manager.register_panel("inventory", _panel, true)


func after_each() -> void:
	if _wm != null and bool(_wm.is_open()):
		_wm.close()


# 走真实事件管线：_input（ui_manager 截流）→ _unhandled_input（替身面板）。
# parse_input_event 的事件在帧末统一 flush，必须等一帧后才生效。
func _send(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await wait_process_frames(1)


# Esc 裁决：有管理面板打开时，先关面板并吞掉事件，暂停菜单不叠开。
func test_esc_closes_top_panel_instead_of_opening_pause() -> void:
	_manager.open("inventory")
	assert_true((_panel as FakePanel).is_open(), "前提：背包已打开")
	await _send(ACTION_PAUSE)
	assert_false((_panel as FakePanel).is_open(), "Esc 应先关最上面板")
	assert_eq(str(_manager.active_panel()), "", "关闭后 ui_manager 应无激活面板")
	assert_false(_pause.visible, "有面板打开时 Esc 不许叠开暂停菜单")


# Esc 裁决：无任何面板打开时放行，暂停菜单照常开关。
func test_esc_passes_through_when_nothing_open() -> void:
	await _send(ACTION_PAUSE)
	assert_true(_pause.visible, "面板全部关闭后 Esc 才轮到暂停菜单")
	await _send(ACTION_PAUSE)
	assert_false(_pause.visible, "再按 Esc 暂停菜单照常关闭")


# Esc 裁决：世界地图页打开时，Esc 先关地图页而非叠开暂停菜单。
func test_esc_closes_world_map_before_pause() -> void:
	await _send(ACTION_WORLDMAP) # 无模态时 M 放行，替身地图页打开
	assert_true(bool(_wm.is_open()), "前提：地图页已打开")
	await _send(ACTION_PAUSE)
	assert_false(bool(_wm.is_open()), "Esc 应先关世界地图页")
	assert_false(_pause.visible, "地图页打开时 Esc 不许叠开暂停菜单")


# M 裁决：管理面板打开时按 M 吞掉，不叠开地图页。
func test_worldmap_key_swallowed_while_panel_open() -> void:
	_manager.open("inventory")
	await _send(ACTION_WORLDMAP)
	assert_false(bool(_wm.is_open()), "面板打开时不许叠开地图页")
	assert_true((_panel as FakePanel).is_open(), "原面板保持打开")


# M 裁决：暂停菜单打开时按 M 吞掉，不叠开地图页。
func test_worldmap_key_swallowed_while_pause_visible() -> void:
	_pause.visible = true
	await _send(ACTION_WORLDMAP)
	assert_false(bool(_wm.is_open()), "暂停菜单打开时不许叠开地图页")


# M 裁决：无任何模态打开时放行（地图页自身处理开关）。
func test_worldmap_key_passes_through_when_nothing_open() -> void:
	await _send(ACTION_WORLDMAP)
	assert_true(bool(_wm.is_open()), "无模态打开时 M 应照常打开地图页")


# 互斥：地图页打开时经 ui_manager 打开面板 → 先关地图页再开面板（不叠开）。
func test_open_panel_closes_world_map_first() -> void:
	_wm.open()
	_manager.open("inventory")
	assert_false(bool(_wm.is_open()), "打开管理面板时地图页应被关闭")
	assert_true((_panel as FakePanel).is_open(), "背包应正常打开")


# 互斥：暂停菜单打开时经 ui_manager 打开面板被拒（热键叠开路径收口）。
func test_open_panel_rejected_while_pause_visible() -> void:
	_pause.visible = true
	_manager.open("inventory")
	assert_false((_panel as FakePanel).is_open(), "暂停菜单打开时不许叠开管理面板")
	assert_eq(str(_manager.active_panel()), "", "ui_manager 应无激活面板")


# DeathScreen 裁决（收口 W1）：死亡画面打开时 Esc 被吞掉——
# 不叠开暂停菜单，也不许误触死亡画面自身的任意键确认。
func test_esc_swallowed_while_death_screen_open() -> void:
	(_death as FakeDeathScreen).open()
	await _send(ACTION_PAUSE)
	assert_true((_death as FakeDeathScreen).is_open(), "Esc 不许关闭死亡画面")
	assert_false((_death as FakeDeathScreen).confirmed, "Esc 不许误触死亡画面确认")
	assert_false(_pause.visible, "死亡画面打开时 Esc 不许叠开暂停菜单")


# 同组共存（FR-G-05 AC5，SPEC-03 §8）：同组面板打开不关当前，同屏并列；
# 最上面板为激活面板，任一屏蔽类面板打开即屏蔽输入。
func test_same_group_panels_coexist() -> void:
	var craft: FakePanel = FakePanel.new()
	add_child_autofree(craft)
	_manager.register_panel("inventory", _panel, true, "crafting")
	_manager.register_panel("craft", craft, true, "crafting")
	_manager.open("inventory")
	_manager.open("craft")
	assert_true((_panel as FakePanel).is_open(), "同组打开合成台时背包应保持打开")
	assert_true(craft.is_open(), "合成台应打开")
	assert_eq(str(_manager.active_panel()), "craft", "最上面板为合成台")
	assert_true(_manager.input_blocked(), "屏蔽类面板打开时输入被屏蔽")


# 同组共存下的 Esc（FR-G-05 AC5）：逐层关闭——先关最上的合成台，背包仍在；再按才关背包。
func test_esc_closes_group_panels_one_by_one() -> void:
	var craft: FakePanel = FakePanel.new()
	add_child_autofree(craft)
	_manager.register_panel("inventory", _panel, true, "crafting")
	_manager.register_panel("craft", craft, true, "crafting")
	_manager.open("inventory")
	_manager.open("craft")
	await _send(ACTION_PAUSE)
	assert_false(craft.is_open(), "第一次 Esc 应先关最上的合成台")
	assert_true((_panel as FakePanel).is_open(), "背包应保持打开")
	assert_eq(str(_manager.active_panel()), "inventory", "背包成为最上面板")
	await _send(ACTION_PAUSE)
	assert_false((_panel as FakePanel).is_open(), "第二次 Esc 才关背包")
	assert_false(_pause.visible, "面板未清空前 Esc 不叠开暂停菜单")


# 跨组仍互斥（SPEC-03 §8）：无组或不同组的面板打开时关闭当前全部面板。
func test_cross_group_panels_still_exclusive() -> void:
	var codex: FakePanel = FakePanel.new()
	add_child_autofree(codex)
	_manager.register_panel("inventory", _panel, true, "crafting")
	_manager.register_panel("codex", codex, true)
	_manager.open("inventory")
	_manager.open("codex")
	assert_false((_panel as FakePanel).is_open(), "跨组打开图鉴应关闭背包")
	assert_true(codex.is_open(), "图鉴应打开")
	assert_eq(str(_manager.active_panel()), "codex", "当前面板应为 codex")


# DeathScreen 裁决：死亡画面关闭后 Esc 照常放行给暂停菜单。
func test_esc_passes_through_after_death_screen_closed() -> void:
	(_death as FakeDeathScreen).open()
	(_death as FakeDeathScreen).close()
	await _send(ACTION_PAUSE)
	assert_true(_pause.visible, "死亡画面关闭后 Esc 应照常放行给暂停菜单")
