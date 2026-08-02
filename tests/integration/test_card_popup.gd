# IT-G06 / FR-G-06：知识卡片弹窗——标题 + 方程式 + 现象 + 现实应用 + 固定底行。
# 全部文字来自数据表（经 RecipeDB.build_card）；任意键可跳过；跳过后卡片进图鉴已解锁列表。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const POPUP_SCENE: String = "res://scenes/ui/card_popup.tscn"
const POPUP_SCRIPT: String = "res://scenes/ui/card_popup.gd"

var tip: Node = null
var recipe_db: Node = null
var _popup: Node = null


func before_each() -> void:
	var root: Window = Engine.get_main_loop().root
	tip = root.get_node_or_null(^"KnowledgeTip")
	recipe_db = root.get_node_or_null(^"RecipeDB")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	assert_not_null(recipe_db, "RecipeDB autoload 必须存在")
	if tip == null or recipe_db == null:
		return
	tip.reload()
	recipe_db.reload()
	recipe_db.reset_unlocked()
	_popup = null
	if not ResourceLoader.exists(POPUP_SCENE):
		fail_test("尚未实现 %s（FR-G-06 / TP-07 补）" % POPUP_SCENE)
		return
	_popup = (load(POPUP_SCENE) as PackedScene).instantiate()
	add_child_autofree(_popup)
	await wait_process_frames(1)


func _skip_unless_ready(method_names: Array = []) -> bool:
	if _popup == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not _popup.has_method(method_name):
			fail_test("卡片弹窗应有 %s()（FR-G-06）" % method_name)
			return true
	return false


func _node(unique_name: String) -> Node:
	var found: Node = _popup.get_node_or_null(NodePath("%%%s" % unique_name))
	if found == null:
		fail_test("卡片弹窗应有唯一名节点 %%%s" % unique_name)
	return found


# R1 配方记录与其卡片五字段（数据表真值）。
func _r1_card() -> Dictionary:
	var recipe: Dictionary = recipe_db.get_recipe("r_sulfur_torch")
	assert_false(recipe.is_empty(), "recipes.json 应有 r_sulfur_torch")
	return recipe_db.build_card(recipe)


# AC1：卡片全部文字来自 recipes.json 字段，无硬编码。
func test_card_texts_come_from_data_table() -> void:
	if _skip_unless_ready(["show_card"]):
		return
	var card: Dictionary = _r1_card()
	_popup.show_card(card)
	var recipe: Dictionary = recipe_db.get_recipe("r_sulfur_torch")
	assert_eq(str(_node("TitleLabel").text), str(recipe.get("card_title", "")), "标题来自 card_title")
	assert_eq(str(_node("EquationLabel").text), str(recipe.get("equation", "")), "方程式来自 equation")
	assert_eq(str(_node("BodyLabel").text), str(recipe.get("card_body", "")), "现象来自 card_body")
	assert_eq(str(_node("ApplicationLabel").text), str(recipe.get("card_application", "")), "应用来自 card_application")
	assert_true(_popup.visible, "展示后弹窗应可见")
	assert_true(_popup.is_open(), "展示后 is_open 应为 true")


# AC2：底部固定显示 card_footer（质量守恒定律，来自 tips.json）。
func test_footer_is_card_footer_from_tips() -> void:
	if _skip_unless_ready(["show_card"]):
		return
	_popup.show_card(_r1_card())
	var rows: Array = Fixture.read_array("tips.json")
	var footer_text: String = ""
	for row: Dictionary in rows:
		if str(row.get("id", "")) == "card_footer":
			footer_text = str(row.get("text", ""))
	assert_false(footer_text.is_empty(), "tips.json 应有 card_footer")
	assert_eq(str(_node("FooterLabel").text), footer_text, "底行必须是 card_footer 原文")


# AC3：任意键跳过；跳过后配方已在图鉴已解锁列表（成功合成时由 RecipeDB 登记）。
func test_skip_with_any_key_closes() -> void:
	if _skip_unless_ready(["show_card", "is_open"]):
		return
	# 先成功合成一次（登记解锁），再展示其卡片。
	var result: Dictionary = recipe_db.try_craft(["stick", "s"], "portable", "ignite")
	assert_true(bool(result.get("success", false)), "R1 正例应成功")
	_popup.show_card(result["card"])
	var closed_count: Array = [0]
	if _popup.has_signal("closed"):
		_popup.closed.connect(func() -> void: closed_count[0] += 1)
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	_popup._unhandled_input(key)
	assert_false(_popup.is_open(), "按任意键后卡片应关闭")
	assert_false(_popup.visible, "关闭后弹窗不可见")
	assert_eq(closed_count[0], 1, "跳过应发出 closed 信号")
	assert_true(recipe_db.unlocked_recipes().has("r_sulfur_torch"), "跳过后配方应在已解锁列表（图鉴数据源）")


# AC3 补充：鼠标点击同样可跳过。
func test_skip_with_mouse_click_closes() -> void:
	if _skip_unless_ready(["show_card"]):
		return
	_popup.show_card(_r1_card())
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	_popup._unhandled_input(click)
	assert_false(_popup.is_open(), "点击后卡片应关闭")


# 未打开时按键不应误触发（防守）。
func test_key_ignored_when_closed() -> void:
	if _skip_unless_ready(["is_open"]):
		return
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_E
	_popup._unhandled_input(key)
	assert_false(_popup.is_open(), "未打开时按键不应打开卡片")


# NFR-04：逻辑代码里不许出现中文字面量（注释与诊断日志除外）。
func test_script_has_no_hardcoded_chinese() -> void:
	if not FileAccess.file_exists(POPUP_SCRIPT):
		fail_test("尚未实现 %s（FR-G-06）" % POPUP_SCRIPT)
		return
	var text: String = FileAccess.get_file_as_string(POPUP_SCRIPT)
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
