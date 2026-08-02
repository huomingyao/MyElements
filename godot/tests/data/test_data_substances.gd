# UT-D01 / FR-D-01：substances.json 条数、id 唯一、HUD 计数集合 16、category 枚举、tip_id 交叉引用、icon 路径。
# 断言依据：SPEC-04 §2 校验规则 + SPEC-05 §1 内容表。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const EXPECTED_COUNT: int = 17
const EXPECTED_HUD_COUNT: int = 16
const NOT_IN_HUD_ID: String = "co2"
const CATEGORIES: Array[String] = ["单质", "化合物", "氧化物", "酸", "碱", "盐"]
const ZONES: Array[String] = ["grassland", "camp", "saltlake", "mine", "academy"]
const REQUIRED_FIELDS: Array[String] = [
	"id", "name", "formula", "category", "tip_id", "zone", "icon", "codex_line",
]
const ASSET_PREFIX: String = "res://assets/"
const ICON_EXTENSIONS: Array[String] = ["png", "svg", "webp"]

# SPEC-05 §1 表格的 id 顺序（逐条誊抄，顺序即图鉴展示顺序）。
const SPEC_IDS: Array[String] = [
	"o2", "h2", "c", "s", "co", "co2", "h2o", "h2o_clean", "caco3", "fe2o3",
	"cuso4", "hcl", "naoh", "caoh2", "fe", "crude_salt", "nacl",
]

# SPEC-05 §1 的 id -> [名称, 化学式, 类别]（文案一字不改）。
const SPEC_NAME_FORMULA_CATEGORY: Dictionary = {
	"o2": ["氧气", "O₂", "单质"],
	"h2": ["氢气", "H₂", "单质"],
	"c": ["碳", "C", "单质"],
	"s": ["硫", "S", "单质"],
	"co": ["一氧化碳", "CO", "化合物"],
	"co2": ["二氧化碳", "CO₂", "化合物"],
	"h2o": ["水", "H₂O", "化合物"],
	"h2o_clean": ["纯净水", "H₂O", "化合物"],
	"caco3": ["碳酸钙", "CaCO₃", "盐"],
	"fe2o3": ["氧化铁", "Fe₂O₃", "氧化物"],
	"cuso4": ["硫酸铜溶液", "CuSO₄", "盐"],
	"hcl": ["稀盐酸", "HCl", "酸"],
	"naoh": ["氢氧化钠", "NaOH", "碱"],
	"caoh2": ["氢氧化钙", "Ca(OH)₂", "碱"],
	"fe": ["铁", "Fe", "单质"],
	"crude_salt": ["粗盐", "NaCl（含杂质）", "盐"],
	"nacl": ["食盐", "NaCl", "盐"],
}

# SPEC-05 §6 图鉴一句话（codex_line），按 id 对应。
const SPEC_CODEX_LINES: Dictionary = {
	"o2": "生命与燃烧都离不开它，但它自己不会燃烧。",
	"h2": "最清洁的燃料，也是最\"暴脾气\"的气体——验纯！",
	"c": "充分燃烧生 CO₂，不充分生 CO——氧气多少决定产物。",
	"s": "淡黄色粉末，点燃就是一把好火把，代价是刺激性气味。",
	"co": "沉默的杀手，活性炭口罩是它的克星。",
	"co2": "灭火能手，石灰水的\"试金石\"。",
	"h2o": "最常见的溶剂，净化四步后才配进实验室。",
	"h2o_clean": "蒸馏水，纯净物——实验台上唯一合格的水。",
	"caco3": "石灰石、大理石、水垢——它们是同一种物质。",
	"fe2o3": "赤铁矿的红色，高炉里炼出铁水。",
	"cuso4": "漂亮的蓝色，有毒的蓝色。",
	"hcl": "腐蚀性很强，除锈和制 CO₂ 也很强。",
	"naoh": "烧碱，强腐蚀，中和反应的主力碱。",
	"caoh2": "熟石灰，改良酸性土壤、检验 CO₂ 都用它。",
	"fe": "会生锈的金属，生锈需要氧气和水同时存在。",
	"crude_salt": "湖边的白色结晶，混着泥沙——提纯三步后才是食盐。",
	"nacl": "由钠离子和氯离子构成的盐，百味之首，也是生理盐水的主要成分。",
}

var _rows: Array[Dictionary] = []


func before_each() -> void:
	_rows = Fixture.rows_of("substances.json")


# AC1：17 条齐全。
func test_substance_count_is_seventeen() -> void:
	assert_eq(_rows.size(), EXPECTED_COUNT, "substances.json 必须恰好 17 条")


# AC1：id 唯一，且集合与 SPEC-05 §1 完全一致。
func test_substance_ids_unique_and_match_spec() -> void:
	var ids: Array[String] = Fixture.ids_of(_rows)
	var seen: Dictionary = {}
	for id in ids:
		assert_false(seen.has(id), "重复 id：%s" % id)
		seen[id] = true
	for spec_id in SPEC_IDS:
		assert_true(seen.has(spec_id), "SPEC-05 §1 的 id 缺失：%s" % spec_id)
	assert_eq(seen.size(), SPEC_IDS.size(), "id 集合与 SPEC-05 §1 不一致")


# AC1：count_in_hud != false 的恰好 16 条，且唯一被排除的是 co2。
func test_hud_count_set_is_sixteen_excluding_co2() -> void:
	var counted: Array[String] = []
	var excluded: Array[String] = []
	for row in _rows:
		if row.get("count_in_hud", true) == false:
			excluded.append(str(row.get("id", "")))
		else:
			counted.append(str(row.get("id", "")))
	assert_eq(counted.size(), EXPECTED_HUD_COUNT, "HUD 计数集合必须恰好 16 条")
	assert_eq(excluded, [NOT_IN_HUD_ID] as Array[String], "只有 co2 允许 count_in_hud=false")


# AC1：必填字段非空。
func test_required_fields_present_and_non_empty() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		for field in REQUIRED_FIELDS:
			assert_true(row.has(field), "%s 缺字段 %s" % [id, field])
			var value: Variant = row.get(field, null)
			if typeof(value) == TYPE_STRING:
				assert_false((value as String).is_empty(), "%s 的 %s 为空" % [id, field])


# category 在枚举内，且与 SPEC-05 §1 表格一致。
func test_category_in_enum_and_matches_spec() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var category: String = str(row.get("category", ""))
		assert_true(CATEGORIES.has(category), "%s 的 category 非法：%s" % [id, category])
		var expected: Array = SPEC_NAME_FORMULA_CATEGORY.get(id, [])
		if not expected.is_empty():
			assert_eq(category, str(expected[2]), "%s 的 category 与 SPEC-05 §1 不一致" % id)


# 名称与化学式逐字符对齐 SPEC-05 §1（Unicode 下标，不许 LaTeX）。
func test_name_and_formula_match_spec_verbatim() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var expected: Array = SPEC_NAME_FORMULA_CATEGORY.get(id, [])
		if expected.is_empty():
			continue
		assert_eq(str(row.get("name", "")), str(expected[0]), "%s 的 name 与 SPEC-05 §1 不一致" % id)
		assert_eq(str(row.get("formula", "")), str(expected[1]), "%s 的 formula 与 SPEC-05 §1 不一致" % id)


# codex_line 逐字符对齐 SPEC-05 §6。
func test_codex_line_matches_spec_verbatim() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		if not SPEC_CODEX_LINES.has(id):
			continue
		assert_eq(
			str(row.get("codex_line", "")),
			str(SPEC_CODEX_LINES[id]),
			"%s 的 codex_line 与 SPEC-05 §6 不一致" % id
		)


# zone 取自五区域枚举；合成产物用 []（co2 按 SPEC-05 §1 必须是空数组）。
func test_zone_values_in_enum_and_co2_is_empty() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var zone: Variant = row.get("zone", null)
		assert_eq(typeof(zone), TYPE_ARRAY, "%s 的 zone 必须是数组" % id)
		for z in (zone as Array):
			assert_true(ZONES.has(str(z)), "%s 的 zone 非法：%s" % [id, str(z)])
	var co2: Dictionary = _row_by_id(NOT_IN_HUD_ID)
	assert_false(co2.is_empty(), "co2 条目不存在")
	var co2_zone: Variant = co2.get("zone", null)
	assert_eq(typeof(co2_zone), TYPE_ARRAY, "co2 的 zone 必须是数组")
	if typeof(co2_zone) == TYPE_ARRAY:
		assert_eq((co2_zone as Array).size(), 0, "co2 的 zone 必须是空数组")


# AC2：tip_id 在 tips.json 中存在。
func test_tip_id_exists_in_tips_table() -> void:
	var tip_ids: Dictionary = {}
	for tip in Fixture.rows_of("tips.json"):
		tip_ids[str(tip.get("id", ""))] = true
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var tip_id: String = str(row.get("tip_id", ""))
		assert_true(tip_ids.has(tip_id), "%s 的 tip_id 在 tips.json 中不存在：%s" % [id, tip_id])


# AC3：icon 指向 res://assets/ 下的合法图片路径（文件缺失由校验器输出 warning，见 validate_data.gd 顶部说明）。
func test_icon_path_is_under_assets_with_valid_extension() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var icon: String = str(row.get("icon", ""))
		assert_true(icon.begins_with(ASSET_PREFIX), "%s 的 icon 必须以 %s 开头：%s" % [id, ASSET_PREFIX, icon])
		assert_true(
			ICON_EXTENSIONS.has(icon.get_extension().to_lower()),
			"%s 的 icon 扩展名非法：%s" % [id, icon]
		)


func _row_by_id(id: String) -> Dictionary:
	for row in _rows:
		if str(row.get("id", "")) == id:
			return row
	return {}
