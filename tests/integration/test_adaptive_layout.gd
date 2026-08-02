# IT-U06 / FR-U-06：UI 面板自适应布局。
# 固定像素尺寸居中的面板改为按视口比例铺开 + 居中，任意窗口尺寸下等比缩放。
# 视口基准 640×360（FR-C-01），缩放由 canvas_items + keep 统一处理（不改拉伸配置）。
extends GutTest

const VIEWPORT_SIZE: Vector2 = Vector2(640, 360)

# 把面板场景根包进一个 640×360 的父 Control，让全屏锚点生效，返回内部面板节点。
func _mount(scene_path: String, inner_path: String) -> Control:
	var parent: Control = Control.new()
	parent.size = VIEWPORT_SIZE
	add_child_autofree(parent)
	var root: Control = load(scene_path).instantiate()
	parent.add_child(root)
	await wait_frames(1)
	return root.get_node(inner_path) as Control


func _assert_centered_proportional(panel: Control, w_frac: float, h_frac: float) -> void:
	var r: Rect2 = panel.get_rect()
	assert_almost_eq(r.size.x, VIEWPORT_SIZE.x * w_frac, 2.0, "面板宽度应为视口 %.0f%%" % (w_frac * 100.0))
	assert_almost_eq(r.size.y, VIEWPORT_SIZE.y * h_frac, 2.0, "面板高度应为视口 %.0f%%" % (h_frac * 100.0))
	assert_almost_eq(r.position.x + r.size.x / 2.0, VIEWPORT_SIZE.x / 2.0, 2.0, "面板应水平居中")
	assert_almost_eq(r.position.y + r.size.y / 2.0, VIEWPORT_SIZE.y / 2.0, 2.0, "面板应垂直居中")


# AC1：合成面板按视口比例铺开（宽 76%、高 60%）并居中。
func test_craft_panel_is_proportional_and_centered() -> void:
	var panel: Control = await _mount("res://scenes/ui/craft_panel.tscn", "Panel")
	_assert_centered_proportional(panel, 0.76, 0.60)


# AC1：背包面板按视口比例铺开（宽 70%、高 70%）并居中。
func test_inventory_panel_is_proportional_and_centered() -> void:
	var panel: Control = await _mount("res://scenes/ui/inventory_panel.tscn", "Panel")
	_assert_centered_proportional(panel, 0.70, 0.70)


# AC1：知识卡片弹窗按视口比例铺开（宽 80%、高 70%）并居中。
func test_card_popup_is_proportional_and_centered() -> void:
	var panel: Control = await _mount("res://scenes/ui/card_popup.tscn", "Panel")
	_assert_centered_proportional(panel, 0.80, 0.70)


# AC2：主菜单按钮组相对视口居中，不依赖 640×360 固定偏移。
func test_main_menu_box_is_centered() -> void:
	var box: Control = await _mount("res://scenes/main/main_menu.tscn", "MenuBox")
	var r: Rect2 = box.get_rect()
	assert_almost_eq(r.position.x + r.size.x / 2.0, VIEWPORT_SIZE.x / 2.0, 2.0, "主菜单应水平居中")
	assert_almost_eq(r.position.y + r.size.y / 2.0, VIEWPORT_SIZE.y / 2.0, 2.0, "主菜单应垂直居中")


# AC2：暂停菜单按钮组相对视口居中。
func test_pause_menu_box_is_centered() -> void:
	var box: Control = await _mount("res://scenes/main/pause_menu.tscn", "PauseBox")
	var r: Rect2 = box.get_rect()
	assert_almost_eq(r.position.x + r.size.x / 2.0, VIEWPORT_SIZE.x / 2.0, 2.0, "暂停菜单应水平居中")
	assert_almost_eq(r.position.y + r.size.y / 2.0, VIEWPORT_SIZE.y / 2.0, 2.0, "暂停菜单应垂直居中")


# AC3：死亡画面文案垂直使用中心锚点（相对视口居中，而非固定顶部偏移）；水平保持全宽居中文本。
func test_death_screen_labels_use_center_anchor() -> void:
	var inst: Node = load("res://scenes/ui/death_screen.tscn").instantiate()
	add_child_autofree(inst)
	await wait_frames(1)
	for label_path: String in ["TitleLabel", "DayLabel", "InfoLabel", "HintLabel"]:
		var label: Control = inst.get_node(label_path) as Control
		assert_almost_eq(label.anchor_top, 0.5, 0.001, "%s 上锚点应为 0.5" % label_path)
		assert_almost_eq(label.anchor_bottom, 0.5, 0.001, "%s 下锚点应为 0.5" % label_path)
		assert_eq(int(label.grow_vertical), 2, "%s 应双向生长居中" % label_path)
