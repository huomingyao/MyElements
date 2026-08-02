# IT-U04 / FR-U-04：图鉴。17 格网格（展示全部物质卡，HUD 进度按 16 计，口径见 SPEC-05 §1）；
# 已收集显示彩色图标 + 分类标签；未收集剪影不泄露名称；已解锁反应卡片可翻页；
# 主菜单与游戏内数据一致（同一 panel 场景 + 同一数据来源，两个实例喂同样状态显示一致）。
# 数据来源约束（SPEC-03 §1）：面板只调 RecipeDB/GameManager autoload 与注入的 Discovery，不自读数据表。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const PANEL_PATH: String = "res://scenes/ui/codex_panel.tscn"
const PANEL_SCRIPT_PATH: String = "res://scenes/ui/codex_panel.gd"
const CELL_SCRIPT_PATH: String = "res://scenes/ui/codex_cell.gd"
const DISCOVERY_PATH: String = "res://scripts/gameplay/discovery.gd"

const UI_KEY_LOCKED: String = "codex_locked"

# B-003：游戏会话共享 Discovery 的 SceneTree 根元数据键（D2 元数据模式同款）。
const SESSION_DISCOVERY_META: String = "session_discovery"

var db: Node = null
var gm: Node = null


func before_each() -> void:
	_clear_session_meta()
	var root: Node = Engine.get_main_loop().root
	db = root.get_node_or_null(^"RecipeDB")
	gm = root.get_node_or_null(^"GameManager")
	assert_not_null(db, "RecipeDB autoload 必须存在（物质/配方数据来源）")
	assert_not_null(gm, "GameManager autoload 必须存在（UI 短语来源）")
	if db == null or gm == null:
		return
	# autoload 单例的已解锁进度会跨测试残留，逐个测试复位保证独立性。
	if db.has_method("reset_unlocked"):
		db.reset_unlocked()


func after_each() -> void:
	_clear_session_meta()
	if db != null and db.has_method("reset_unlocked"):
		db.reset_unlocked()


# 会话共享元数据跨测试残留会让「默认全锁定」类断言假红，逐个测试清掉。
func _clear_session_meta() -> void:
	var root: Window = Engine.get_main_loop().root
	if root != null and root.has_meta(SESSION_DISCOVERY_META):
		root.remove_meta(SESSION_DISCOVERY_META)


# ---- 工具 ----

func _new_panel() -> Node:
	if not ResourceLoader.exists(PANEL_PATH):
		fail_test("尚未实现 %s（FR-U-04 / TP-16）" % PANEL_PATH)
		return null
	var panel: Node = (load(PANEL_PATH) as PackedScene).instantiate()
	add_child_autofree(panel)
	return panel


# 缺实现/缺方法时记断言失败并跳过，避免 before 崩掉后 GUT 误报通过。
func _skip_unless(panel: Node, method_names: Array) -> bool:
	if panel == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not panel.has_method(method_name):
			fail_test("CodexPanel 应有 %s()（FR-U-04）" % method_name)
			return true
	return false


func _new_discovery(ids: Array) -> RefCounted:
	var script: Resource = load(DISCOVERY_PATH)
	assert_not_null(script, "discovery.gd 应可加载（TP-06 已交付）")
	if script == null:
		return null
	var dis: RefCounted = script.new()
	for id_value in ids:
		dis.discover(str(id_value))
	return dis


func _substances() -> Array:
	return Fixture.rows_of("substances.json")


func _substance_by_id(substance_id: String) -> Dictionary:
	for row: Dictionary in _substances():
		if str(row.get("id", "")) == substance_id:
			return row
	return {}


func _locked_text() -> String:
	return gm.get_ui_string(UI_KEY_LOCKED)


# ---- AC 覆盖 ----

# IT-U04：网格 17 格齐全——一格对应一条物质记录，格数自数据表得出，不写死。
func test_grid_contains_one_cell_per_substance() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["cell_count", "cell_for"]):
		return
	var rows: Array = _substances()
	assert_eq(rows.size(), 17, "substances.json 应有 17 条（FR-D-01）")
	assert_eq(panel.cell_count(), rows.size(), "网格格数应等于物质表条数（展示全部 17 张卡）")
	for row: Dictionary in rows:
		var id: String = str(row.get("id", ""))
		assert_not_null(panel.cell_for(id), "每种物质都应有一格：%s" % id)


# AC1：已收集物质显示彩色图标与分类标签（标签取 category 字段）。
func test_collected_cell_shows_name_category_and_color() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["set_discovery", "cell_for"]):
		return
	panel.set_discovery(_new_discovery(["o2"]))
	var cell: Node = panel.cell_for("o2")
	assert_not_null(cell, "o2 应有一格")
	if cell == null:
		return
	for method_name in ["is_unlocked", "is_silhouette", "name_text", "category_text", "icon_tint"]:
		if not cell.has_method(method_name):
			fail_test("CodexCell 应有 %s()（FR-U-04）" % method_name)
			return
	var row: Dictionary = _substance_by_id("o2")
	assert_true(cell.is_unlocked(), "已收集的 o2 应为解锁状态")
	assert_false(cell.is_silhouette(), "已收集的 o2 不应是剪影")
	assert_eq(cell.name_text(), str(row.get("name", "")), "已收集应显示数据表里的名称")
	assert_eq(cell.category_text(), str(row.get("category", "")), "已收集应显示数据表里的分类标签")
	assert_ne(cell.icon_tint(), Color(0, 0, 0), "已收集图标应为彩色（非剪影黑）")


# AC2：未收集显示剪影，不泄露名称（名称位显示 ui_strings.codex_locked 的占位文案）。
func test_uncollected_cell_is_silhouette_without_name() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["set_discovery", "cell_for"]):
		return
	panel.set_discovery(_new_discovery(["o2"]))
	var cell: Node = panel.cell_for("h2")
	assert_not_null(cell, "h2 应有一格")
	if cell == null:
		return
	var row: Dictionary = _substance_by_id("h2")
	assert_false(cell.is_unlocked(), "未收集的 h2 应为锁定状态")
	assert_true(cell.is_silhouette(), "未收集的 h2 应为剪影")
	assert_eq(cell.name_text(), _locked_text(), "未收集的名称位应显示 codex_locked 占位文案")
	assert_false(
		cell.name_text().contains(str(row.get("name", ""))),
		"未收集不许泄露物质名：%s" % str(row.get("name", ""))
	)
	assert_eq(cell.category_text(), "", "未收集不显示分类标签（不泄露任何信息）")


# AC2 全量：默认（无任何发现）时 17 格全部锁定，且任何一格显示的名称都不等于数据表真名。
func test_locked_cells_never_leak_any_substance_name() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["cell_count", "cell_for"]):
		return
	for row: Dictionary in _substances():
		var id: String = str(row.get("id", ""))
		var cell: Node = panel.cell_for(id)
		assert_not_null(cell, "应有一格：%s" % id)
		if cell == null:
			continue
		assert_true(cell.is_silhouette(), "未收集应为剪影：%s" % id)
		assert_ne(
			cell.name_text(), str(row.get("name", "")),
			"未收集不许显示真名：%s" % id
		)
		assert_false(
			cell.name_text().contains(str(row.get("formula", ""))),
			"未收集不许泄露化学式：%s" % id
		)


# 图标美术未交付（FR-D-01 AC3 允许占位）：图标路径缺失时每格也必须有占位纹理，不留空白不崩溃。
func test_missing_icons_fall_back_to_placeholder() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["set_discovery", "cell_for"]):
		return
	panel.set_discovery(_new_discovery(["o2"]))
	for id_value in ["o2", "h2"]:
		var cell: Node = panel.cell_for(str(id_value))
		assert_not_null(cell, "应有一格：%s" % str(id_value))
		if cell == null:
			continue
		if not cell.has_method("icon_texture"):
			fail_test("CodexCell 应有 icon_texture()（占位断言点）")
			return
		assert_not_null(
			cell.icon_texture(),
			"图标缺失时应显示占位纹理（锁定/解锁两态都不留空白）：%s" % str(id_value)
		)


# AC3：已解锁反应卡片可翻页；卡片内容（方程式、一句话应用）来自数据表。
func test_unlocked_cards_page_through_all() -> void:
	if not (db.has_method("mark_unlocked") and db.has_method("unlocked_recipes")):
		fail_test("RecipeDB 应有 mark_unlocked/unlocked_recipes（SPEC-03 §4）")
		return
	var recipes: Array = Fixture.rows_of("recipes.json")
	assert_gt(recipes.size(), 1, "recipes.json 应有多条配方供翻页")
	var first_id: String = str((recipes[0] as Dictionary).get("id", ""))
	var second_id: String = str((recipes[1] as Dictionary).get("id", ""))
	db.mark_unlocked(first_id)
	db.mark_unlocked(second_id)

	var panel: Node = _new_panel()
	if _skip_unless(panel, ["card_count", "current_card_index", "next_card", "prev_card"]):
		return
	assert_eq(panel.card_count(), 2, "卡片页数应等于已解锁配方数")
	assert_eq(panel.current_card_index(), 0, "初始应停在第一张")
	panel.next_card()
	assert_eq(panel.current_card_index(), 1, "next 应前进一页")
	panel.next_card()
	assert_eq(panel.current_card_index(), 0, "翻到末页后再 next 应回到第一页（循环翻页）")
	panel.prev_card()
	assert_eq(panel.current_card_index(), 1, "首页 prev 应回到末页（循环翻页）")


# AC3：当前卡片显示方程式与一句话应用，且逐字来自 recipes.json，不是代码里写的。
func test_card_page_shows_equation_and_application_from_data() -> void:
	if not db.has_method("mark_unlocked"):
		fail_test("RecipeDB 应有 mark_unlocked（SPEC-03 §9 非契约辅助）")
		return
	var recipe: Dictionary = Fixture.rows_of("recipes.json")[0]
	var recipe_id: String = str(recipe.get("id", ""))
	db.mark_unlocked(recipe_id)

	var panel: Node = _new_panel()
	if _skip_unless(panel, ["current_card"]):
		return
	var card: Dictionary = panel.current_card()
	assert_false(card.is_empty(), "已解锁时应能取到当前卡片")
	assert_eq(str(card.get("title", "")), str(recipe.get("card_title", "")), "卡片标题应来自数据表")
	assert_eq(str(card.get("equation", "")), str(recipe.get("equation", "")), "卡片方程式应来自数据表")
	assert_eq(str(card.get("application", "")), str(recipe.get("card_application", "")), "一句话应用应来自数据表")
	assert_false(str(card.get("equation", "")).is_empty(), "方程式不许为空")
	assert_false(str(card.get("application", "")).is_empty(), "一句话应用不许为空")


# AC3 边界：没有已解锁配方时卡片页为空态，翻页不崩溃。
func test_no_unlocked_recipes_card_page_is_empty_safe() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["card_count", "current_card", "next_card", "prev_card"]):
		return
	assert_eq(panel.card_count(), 0, "未解锁任何配方时卡片页应为 0")
	assert_true(panel.current_card().is_empty(), "无卡时 current_card 应返回空字典")
	panel.next_card()
	panel.prev_card()
	assert_eq(panel.card_count(), 0, "空态翻页不该变出卡片")


# AC4：主菜单与游戏内均可打开且数据一致——两个独立实例喂同一 Discovery 与同一 RecipeDB，
# 每格显示状态与卡片内容逐项相同。
func test_two_panels_with_same_inputs_show_identical_data() -> void:
	if not db.has_method("mark_unlocked"):
		fail_test("RecipeDB 应有 mark_unlocked（SPEC-03 §9 非契约辅助）")
		return
	var recipe: Dictionary = Fixture.rows_of("recipes.json")[0]
	db.mark_unlocked(str(recipe.get("id", "")))
	var shared: RefCounted = _new_discovery(["o2", "c"])

	var panel_a: Node = _new_panel()
	var panel_b: Node = _new_panel()
	if _skip_unless(panel_a, ["set_discovery", "cell_for", "current_card"]):
		return
	if _skip_unless(panel_b, ["set_discovery", "cell_for", "current_card"]):
		return
	panel_a.set_discovery(shared)
	panel_b.set_discovery(shared)

	for row: Dictionary in _substances():
		var id: String = str(row.get("id", ""))
		var cell_a: Node = panel_a.cell_for(id)
		var cell_b: Node = panel_b.cell_for(id)
		assert_not_null(cell_a, "A 应有一格：%s" % id)
		assert_not_null(cell_b, "B 应有一格：%s" % id)
		if cell_a == null or cell_b == null:
			continue
		assert_eq(
			cell_a.name_text(), cell_b.name_text(),
			"两处打开显示应一致（名称位）：%s" % id
		)
		assert_eq(
			cell_a.is_silhouette(), cell_b.is_silhouette(),
			"两处打开显示应一致（剪影态）：%s" % id
		)
	assert_eq(
		panel_a.current_card(), panel_b.current_card(),
		"两处打开卡片内容应一致"
	)


# B-003 回归（FR-U-04 AC4 数据一致）：游戏内经 set_discovery 注入的收集进度，
# 必须经 SceneTree 根元数据共享给「Esc 回主菜单后再打开」的未注入面板——
# 此前主菜单图鉴门加载独立场景、_default_discovery 自建空集合，永远显示空收集。
func test_uninjected_panel_reads_session_discovery_shared_by_injection() -> void:
	var shared: RefCounted = _new_discovery(["o2", "c"])
	var panel_in_game: Node = _new_panel()
	if _skip_unless(panel_in_game, ["set_discovery"]):
		return
	# 游戏内路径：world._setup_ui 把会话 Discovery 注入图鉴。
	panel_in_game.set_discovery(shared)

	# 主菜单图鉴门路径：独立实例化同一场景，无人调用 set_discovery。
	var panel_in_menu: Node = _new_panel()
	if _skip_unless(panel_in_menu, ["cell_for"]):
		return
	for substance_id: String in ["o2", "c"]:
		var cell: Node = panel_in_menu.cell_for(substance_id)
		assert_not_null(cell, "主菜单图鉴应有一格：%s" % substance_id)
		if cell == null:
			continue
		assert_true(
			cell.is_unlocked(),
			"主菜单图鉴应读到游戏会话的收集进度（B-003 / FR-U-04 AC4）：%s" % substance_id
		)


# B-003 反向口径：会话尚无注入记录时，主菜单直接打开图鉴显示空收集属合理（AC4 不崩溃）。
func test_no_session_defaults_to_empty_collection() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["cell_for"]):
		return
	var cell: Node = panel.cell_for("o2")
	assert_not_null(cell, "o2 应有一格")
	if cell == null:
		return
	assert_true(cell.is_silhouette(), "无会话注入时主菜单直接打开应显示空收集（合理空态）")


# AC4：面板可独立打开/关闭（主菜单与游戏内都只实例化这一个场景）。
func test_open_close_toggles_visibility() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["open", "close", "is_open"]):
		return
	assert_false(panel.is_open(), "新实例默认应是关闭态（由 UI 管理层裁决何时打开）")
	panel.open()
	assert_true(panel.is_open(), "open() 后面板应为打开态")
	assert_true(panel.visible, "open() 后应可见")
	panel.close()
	assert_false(panel.is_open(), "close() 后面板应为关闭态")
	assert_false(panel.visible, "close() 后应不可见")


# 打开时按注入的最新状态重绘（收集进度变化后再打开显示新状态）。
func test_open_refreshes_with_latest_discovery_state() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["set_discovery", "cell_for", "open"]):
		return
	var dis: RefCounted = _new_discovery([])
	panel.set_discovery(dis)
	var cell: Node = panel.cell_for("o2")
	assert_not_null(cell, "o2 应有一格")
	if cell == null:
		return
	assert_true(cell.is_silhouette(), "未发现时 o2 应为剪影")
	dis.discover("o2")
	panel.open()
	assert_false(cell.is_silhouette(), "发现后重新打开应显示已收集")
	assert_eq(cell.name_text(), str(_substance_by_id("o2").get("name", "")), "发现后应显示真名")


# 包D：已收集格的 tooltip 展示图鉴一句话与获得途径（obtain 字段），内容逐字来自数据表。
func test_unlocked_cell_tooltip_shows_codex_line_and_obtain() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["set_discovery", "cell_for"]):
		return
	panel.set_discovery(_new_discovery(["o2"]))
	var cell: Node = panel.cell_for("o2")
	assert_not_null(cell, "o2 应有一格")
	if cell == null:
		return
	var row: Dictionary = _substance_by_id("o2")
	var codex_line: String = str(row.get("codex_line", ""))
	var obtain: String = str(row.get("obtain", ""))
	assert_false(codex_line.is_empty(), "o2 应有 codex_line（数据前提）")
	assert_false(obtain.is_empty(), "o2 应有 obtain 字段（包D 数据前提）")
	assert_true(
		cell.tooltip_text.contains(codex_line),
		"已收集格 tooltip 应含图鉴一句话：%s" % codex_line
	)
	assert_true(
		cell.tooltip_text.contains(obtain),
		"已收集格 tooltip 应含获得途径：%s" % obtain
	)


# 包D：未收集格的 tooltip 不泄露来源信息（与剪影同口径：不泄露任何数据表内容）。
func test_locked_cell_tooltip_does_not_leak_obtain_or_codex_line() -> void:
	var panel: Node = _new_panel()
	if _skip_unless(panel, ["set_discovery", "cell_for"]):
		return
	panel.set_discovery(_new_discovery(["o2"]))
	var cell: Node = panel.cell_for("h2")
	assert_not_null(cell, "h2 应有一格")
	if cell == null:
		return
	var row: Dictionary = _substance_by_id("h2")
	assert_true(cell.is_silhouette(), "h2 未收集应为剪影（前置）")
	assert_false(
		cell.tooltip_text.contains(str(row.get("codex_line", ""))),
		"未收集格 tooltip 不许泄露图鉴一句话"
	)
	assert_false(
		cell.tooltip_text.contains(str(row.get("obtain", ""))),
		"未收集格 tooltip 不许泄露获得途径"
	)


# NFR-04：图鉴两个脚本里不许出现中文字面量（注释除外），文案一律走数据表/get_ui_string。
func test_codex_scripts_have_no_hardcoded_chinese() -> void:
	for script_path in [PANEL_SCRIPT_PATH, CELL_SCRIPT_PATH]:
		if not FileAccess.file_exists(script_path):
			fail_test("尚未实现 %s（FR-U-04 / TP-16）" % script_path)
			continue
		var text: String = FileAccess.get_file_as_string(script_path)
		for line in text.split("\n"):
			var stripped: String = str(line).strip_edges()
			if stripped.begins_with("#"):
				continue
			assert_false(
				_has_cjk(stripped),
				"逻辑代码里不许硬编码中文（NFR-04）%s：%s" % [script_path, stripped]
			)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
