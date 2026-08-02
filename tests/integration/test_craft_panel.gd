# IT-G05 / FR-G-05（并覆盖 FR-G-08 AC1、FR-G-09 AC1..AC3 的界面部分）：
# 合成界面——材料入格（取消回背包不丢失）+ 三种器材 + 反应/点燃/验纯。
# 成功产物入包 + 弹知识卡片；失败显示失败字幕且材料不消耗。
extends GutTest

const PANEL_SCENE: String = "res://scenes/ui/craft_panel.tscn"
const PANEL_SCRIPT: String = "res://scenes/ui/craft_panel.gd"
const INVENTORY_SCRIPT: String = "res://scripts/gameplay/inventory.gd"
const HYDROGEN_SCRIPT: String = "res://scripts/gameplay/hydrogen_event.gd"

var gm: Node = null
var tip: Node = null
var recipe_db: Node = null
var _panel: Node = null
var _inventory: RefCounted = null
var _hydrogen: RefCounted = null


func before_each() -> void:
	var root: Window = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	tip = root.get_node_or_null(^"KnowledgeTip")
	recipe_db = root.get_node_or_null(^"RecipeDB")
	assert_not_null(gm, "GameManager autoload 必须存在")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	assert_not_null(recipe_db, "RecipeDB autoload 必须存在")
	if gm == null or tip == null or recipe_db == null:
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	gm.set_zone("camp")
	gm.set_flag("explosion_happened", false)
	gm.set_flag("purity_check_unlocked", false)
	tip.reload()
	recipe_db.reload()
	recipe_db.reset_unlocked()
	recipe_db.reset_rotation()
	_panel = null
	_inventory = (load(INVENTORY_SCRIPT) as GDScript).new()
	_hydrogen = (load(HYDROGEN_SCRIPT) as GDScript).new()
	if not ResourceLoader.exists(PANEL_SCENE):
		fail_test("尚未实现 %s（FR-G-05 / TP-07 补）" % PANEL_SCENE)
		return
	_panel = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child_autofree(_panel)
	await wait_process_frames(1)
	if _panel.has_method("bind"):
		_panel.bind(_inventory)
	if _panel.has_method("set_hydrogen_event"):
		_panel.set_hydrogen_event(_hydrogen)


func after_each() -> void:
	if gm != null:
		gm.reset_stats()
		gm.set_flag("explosion_happened", false)
		gm.set_flag("purity_check_unlocked", false)
	if tip != null:
		tip.clear_queue()


func _skip_unless_ready(method_names: Array = []) -> bool:
	if _panel == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not _panel.has_method(method_name):
			fail_test("合成界面应有 %s()（FR-G-05）" % method_name)
			return true
	return false


# AC1：材料从背包入格；取消时全部回到背包，不丢失。
func test_add_material_and_cancel_returns_all() -> void:
	if _skip_unless_ready(["add_material", "close", "slot_ids"]):
		return
	_inventory.add_item("stick", 2)
	_inventory.add_item("s", 1)
	assert_true(_panel.add_material("stick"), "入格应成功")
	assert_true(_panel.add_material("s"), "第二格应成功")
	assert_eq(_inventory.count_of("stick"), 1, "入格后背包少一份")
	assert_eq(_inventory.count_of("s"), 0, "入格后背包少一份")
	assert_eq(_panel.slot_ids(), ["stick", "s"], "格子内容按放入顺序")
	_panel.close()
	assert_eq(_inventory.count_of("stick"), 2, "取消后材料全部回背包")
	assert_eq(_inventory.count_of("s"), 1, "取消后材料全部回背包")
	assert_eq(_panel.slot_ids(), [], "关闭后格子清空")


# AC1 边界：材料格最多 3 格，第 4 份拒收且背包不变。
func test_slots_cap_at_three() -> void:
	if _skip_unless_ready(["add_material"]):
		return
	for id_value: String in ["stick", "s", "c", "o2"]:
		_inventory.add_item(id_value, 1)
	assert_true(_panel.add_material("stick"))
	assert_true(_panel.add_material("s"))
	assert_true(_panel.add_material("c"))
	assert_false(_panel.add_material("o2"), "第 4 格应拒收")
	assert_eq(_inventory.count_of("o2"), 1, "拒收的材料仍在背包")


# AC1 边界：背包没有的材料不能入格。
func test_add_material_requires_inventory() -> void:
	if _skip_unless_ready(["add_material"]):
		return
	assert_false(_panel.add_material("stick"), "背包没有时不应入格")
	assert_eq(_panel.slot_ids(), [], "格子仍为空")


# AC2：成功（木棒 + 硫，便携格点燃）→ 产物入包 + 弹知识卡片 + 材料消耗。
func test_success_craft_consumes_and_shows_card() -> void:
	if _skip_unless_ready(["add_material", "select_tool", "ignite"]):
		return
	_inventory.add_item("stick", 1)
	_inventory.add_item("s", 1)
	var cards: Array = []
	if _panel.has_signal("card_ready"):
		_panel.card_ready.connect(func(card: Dictionary) -> void: cards.append(card))
	_panel.add_material("stick")
	_panel.add_material("s")
	_panel.select_tool("portable")
	_panel.ignite()
	assert_eq(_inventory.count_of("sulfur_torch"), 1, "成功后硫火把入包")
	assert_eq(_inventory.count_of("stick"), 0, "成功后材料被消耗")
	assert_eq(_panel.slot_ids(), [], "成功后格子清空")
	assert_eq(cards.size(), 1, "成功应发出一次 card_ready")
	if cards.size() == 1:
		var recipe: Dictionary = recipe_db.get_recipe("r_sulfur_torch")
		assert_eq(str(cards[0].get("title", "")), str(recipe.get("card_title", "")), "卡片标题来自数据表")
		assert_false(str(cards[0].get("footer", "")).is_empty(), "卡片底行非空（card_footer）")


# AC2：完全不匹配 → 失败字幕（数据表文案），材料不消耗。
func test_no_match_fail_keeps_materials_and_shows_message() -> void:
	if _skip_unless_ready(["add_material", "react"]):
		return
	_inventory.add_item("o2", 1)
	_inventory.add_item("c", 1)
	_panel.add_material("o2")
	_panel.add_material("c")
	_panel.select_tool("bench")
	_panel.react()
	assert_eq(_panel.slot_ids(), ["o2", "c"], "失败材料不消耗")
	assert_eq(_inventory.count_of("co2"), 0, "失败无产物")
	assert_true(tip.current_text() != "" or tip.queue_size() > 0, "失败应显示失败字幕")


# AC2：材料对但器材不对 → wrong_condition 失败文案，材料不消耗。
func test_wrong_tool_fail_message_from_correct_pool() -> void:
	if _skip_unless_ready(["add_material", "ignite"]):
		return
	_inventory.add_item("stick", 1)
	_inventory.add_item("s", 1)
	_panel.add_material("stick")
	_panel.add_material("s")
	_panel.select_tool("bench") # R1 要求 portable
	_panel.ignite()
	assert_eq(_panel.slot_ids(), ["stick", "s"], "条件失败材料不消耗")
	# 失败文案必须来自 wrong_condition 池（FR-G-07 判定口径：池间不混用）。
	var wrong_pool: Array = []
	for row: Dictionary in recipe_db.all_fail_messages():
		if str(row.get("reason", "")) == "wrong_condition":
			wrong_pool.append(str(row.get("text", "")))
	var shown: String = tip.current_text()
	if shown.is_empty():
		# 可能还在排队；本条为 show_custom 立即上台，取不到才算失败。
		fail_test("失败字幕应立即显示")
	else:
		assert_true(wrong_pool.has(shown), "器材错误必须显示 wrong_condition 池文案：%s" % shown)


# AC3：器材选项恰好为 portable / alcohol_lamp / bench 三种。
func test_tool_options_are_three() -> void:
	if _skip_unless_ready(["tool_options"]):
		return
	assert_eq(_panel.tool_options(), ["portable", "alcohol_lamp", "bench"], "器材三选项")


# FR-G-08 AC1（包B-A6）：仅当背包或合成槽内有 H₂ 时「点燃」选项才可见（此前恒可见）。
func test_ignite_button_available_with_hydrogen() -> void:
	if _skip_unless_ready([]):
		return
	var button: Node = _panel.get_node_or_null(^"%IgniteButton")
	assert_not_null(button, "应有 %IgniteButton")
	if button == null:
		return
	_panel.open()
	assert_false(button.visible, "没有 H₂ 时点燃按钮应隐藏（FR-G-08 AC1）")
	_inventory.add_item("h2", 1)
	_panel._refresh()
	assert_true(button.visible, "背包获得 H₂ 后应出现「点燃」选项")
	assert_false(button.disabled, "点燃按钮不应禁用")
	# H₂ 入合成槽后背包扣出，按钮仍应可见（槽内也算持有）。
	_panel.add_material("h2")
	assert_eq(_inventory.count_of("h2"), 0, "入格后背包应扣出 H₂（前置）")
	assert_true(button.visible, "合成槽内有 H₂ 时点燃按钮仍应可见")
	# 取回材料并消耗掉 H₂：按钮重新隐藏。
	_panel.remove_material_at(0)
	_inventory.remove_item("h2", 1)
	_panel._refresh()
	assert_false(button.visible, "H₂ 用掉后点燃按钮应重新隐藏")


# FR-G-08 AC2/AC3 界面段：未验纯点燃 H₂+O₂ → 生命精确 -50 + 置标记，材料不消耗。
func test_unpure_ignite_explodes_and_keeps_materials() -> void:
	if _skip_unless_ready(["add_material", "ignite"]):
		return
	_inventory.add_item("h2", 1)
	_inventory.add_item("o2", 1)
	_panel.add_material("h2")
	_panel.add_material("o2")
	_panel.select_tool("portable")
	var before: float = gm.health
	_panel.ignite()
	var damage: float = float(gm.get_balance("damage.hydrogen_explosion", 50.0))
	assert_almost_eq(gm.health, before - damage, 0.001, "未验纯点燃应精确扣血")
	assert_true(gm.get_flag("explosion_happened"), "爆炸后应置 explosion_happened")
	assert_eq(_panel.slot_ids(), ["h2", "o2"], "爆炸路径材料不消耗")


# FR-G-09 AC1/AC2：解锁后出现验纯步骤；验纯触发 sys_purity_ok。
func test_purity_check_flow() -> void:
	if _skip_unless_ready(["add_material", "can_purity_check", "purity_check"]):
		return
	_inventory.add_item("h2", 1)
	_inventory.add_item("o2", 1)
	_panel.add_material("h2")
	_panel.add_material("o2")
	assert_false(_panel.can_purity_check(), "未解锁时不出现验纯步骤")
	gm.set_flag("purity_check_unlocked", true)
	assert_true(_panel.can_purity_check(), "解锁后出现验纯步骤")
	assert_true(_panel.purity_check(), "验纯应执行成功")
	assert_true(tip.is_shown("sys_purity_ok"), "验纯应触发 sys_purity_ok")


# FR-G-09 AC3：验纯后点燃成功——产物入包、不再扣血、卡片弹出。
func test_ignite_after_purity_succeeds_without_damage() -> void:
	if _skip_unless_ready(["add_material", "ignite"]):
		return
	gm.set_flag("purity_check_unlocked", true)
	_inventory.add_item("h2", 1)
	_inventory.add_item("o2", 1)
	var cards: Array = []
	if _panel.has_signal("card_ready"):
		_panel.card_ready.connect(func(card: Dictionary) -> void: cards.append(card))
	_panel.add_material("h2")
	_panel.add_material("o2")
	_panel.select_tool("portable")
	var before: float = gm.health
	_panel.ignite()
	assert_almost_eq(gm.health, before, 0.001, "验纯后点燃不扣血")
	assert_eq(_inventory.count_of("h2o"), 1, "点燃成功后水入包")
	assert_eq(cards.size(), 1, "成功后弹出知识卡片")


# FR-U-05 联动：从背包拖材料到合成台即入格（面板任意处可落）。
func test_drop_from_inventory_adds_material() -> void:
	if _skip_unless_ready(["open"]):
		return
	_inventory.add_item("stick", 1)
	_panel.open()
	var data: Dictionary = {"id": "stick"}
	assert_true(_panel._can_drop_data(Vector2.ZERO, data), "应接受背包拖来的材料")
	_panel._drop_data(Vector2.ZERO, data)
	assert_eq(_panel.slot_ids(), ["stick"], "拖入后材料进格")
	assert_eq(_inventory.count_of("stick"), 0, "拖入后背包扣出")
	_inventory.add_item("s", 1)
	_inventory.add_item("c", 1)
	_inventory.add_item("o2", 1)
	_panel._drop_data(Vector2.ZERO, {"id": "s"})
	_panel._drop_data(Vector2.ZERO, {"id": "c"})
	assert_false(_panel._can_drop_data(Vector2.ZERO, {"id": "o2"}), "满 3 格后拒绝拖入")


# R12（D6 裁决）：碳 + 酒精灯 +「反应」按 heat 匹配 → 活性炭（物理活化）。
func test_carbon_activation_with_alcohol_lamp() -> void:
	if _skip_unless_ready(["add_material", "react"]):
		return
	_inventory.add_item("c", 1)
	_panel.add_material("c")
	_panel.select_tool("alcohol_lamp")
	_panel.react()
	assert_eq(_inventory.count_of("activated_carbon"), 1, "碳活化应产出活性炭")
	assert_eq(_panel.slot_ids(), [], "成功后格子清空")


# A3（D3 裁决，SPEC-02 §4.4）：矿洞内点燃碳按 low_oxygen 匹配 R3 → 产 CO + warn_co 警示。
func test_ignite_carbon_in_mine_produces_co_and_warns() -> void:
	if _skip_unless_ready(["add_material", "select_tool", "ignite"]):
		return
	gm.set_zone("mine")
	_inventory.add_item("c", 1)
	_panel.add_material("c")
	_panel.select_tool("alcohol_lamp")
	_panel.ignite()
	assert_eq(_inventory.count_of("co"), 1, "矿洞内点燃碳应产 CO（R3 不充分燃烧）")
	assert_eq(_inventory.count_of("co2"), 0, "矿洞内不应走充分燃烧 R2")
	assert_eq(_panel.slot_ids(), [], "成功后格子清空")
	assert_true(tip.is_shown("warn_co"), "产出 CO 应触发 warn_co 警示")


# A3：矿洞外维持 ignite 匹配 R2 → 产 CO2，不触发 warn_co。
func test_ignite_carbon_outside_mine_produces_co2() -> void:
	if _skip_unless_ready(["add_material", "select_tool", "ignite"]):
		return
	_inventory.add_item("c", 1)
	_panel.add_material("c")
	_panel.select_tool("alcohol_lamp")
	_panel.ignite()
	assert_eq(_inventory.count_of("co2"), 1, "矿洞外点燃碳应产 CO2（R2 充分燃烧）")
	assert_eq(_inventory.count_of("co"), 0, "矿洞外不应产 CO")
	assert_false(tip.is_shown("warn_co"), "矿洞外充分燃烧不触发 warn_co")


# B3（SPEC-04 §3 unlock_tip）：合成成功消费配方 unlock_tip——R1 成功弹 tip_mass_conservation。
func test_success_shows_recipe_unlock_tip() -> void:
	if _skip_unless_ready(["add_material", "select_tool", "ignite"]):
		return
	_inventory.add_item("stick", 1)
	_inventory.add_item("s", 1)
	_panel.add_material("stick")
	_panel.add_material("s")
	_panel.select_tool("portable")
	_panel.ignite()
	assert_eq(_inventory.count_of("sulfur_torch"), 1, "R1 应合成成功")
	assert_true(tip.is_shown("tip_mass_conservation"), "成功应弹配方 unlock_tip")


# B3：unlock_tip 为空的配方（r_carbon_activate）成功时不弹任何解锁字幕。
func test_empty_unlock_tip_shows_nothing() -> void:
	if _skip_unless_ready(["add_material", "select_tool", "react"]):
		return
	_inventory.add_item("c", 1)
	_panel.add_material("c")
	_panel.select_tool("alcohol_lamp")
	_panel.react()
	assert_eq(_inventory.count_of("activated_carbon"), 1, "碳活化应成功")
	assert_eq(tip.current_tip_id(), "", "空 unlock_tip 不应弹字幕")
	assert_eq(tip.queue_size(), 0, "空 unlock_tip 不应排队字幕")


# open/close 基本态（ui_manager 互斥的前提）。
func test_open_close_state() -> void:
	if _skip_unless_ready(["open", "close", "is_open"]):
		return
	assert_false(_panel.is_open(), "初始关闭")
	_panel.open()
	assert_true(_panel.is_open(), "open 后应打开")
	assert_true(_panel.visible, "打开时可见")
	_panel.close()
	assert_false(_panel.is_open(), "close 后应关闭")


# NFR-04：逻辑代码里不许出现中文字面量（注释与诊断日志除外）。
func test_script_has_no_hardcoded_chinese() -> void:
	if not FileAccess.file_exists(PANEL_SCRIPT):
		fail_test("尚未实现 %s（FR-G-05）" % PANEL_SCRIPT)
		return
	var text: String = FileAccess.get_file_as_string(PANEL_SCRIPT)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("push_warning") or stripped.contains("push_error") or stripped.contains("print("):
			continue
		assert_false(_has_cjk(stripped), "逻辑代码里不许硬编码中文（NFR-04）：%s" % stripped)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
