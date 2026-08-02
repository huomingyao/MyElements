# UT-D06 / FR-D-06：worldmap.json 13 条、恰好 5 条 unlocked、解锁项 brief 非空、
# 未解锁项 teaser 非空、热区不越出 640×360。
# 断言依据：SPEC-04 §8 校验规则 + SPEC-05 §7 内容表。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const EXPECTED_COUNT: int = 13
const EXPECTED_UNLOCKED: int = 5
const VIEWPORT_WIDTH: int = 640
const VIEWPORT_HEIGHT: int = 360
const HOTSPOT_FIELDS: Array[String] = ["x", "y", "w", "h"]

# SPEC-05 §7：已解锁的 5 个 id 必须与区域 id 一致（SPEC-04 §8）。
const SPEC_UNLOCKED_IDS: Array[String] = ["grassland", "camp", "saltlake", "mine", "academy"]

# SPEC-05 §7：未解锁的 8 个 id。
const SPEC_LOCKED_IDS: Array[String] = [
	"deep_mine", "volcano", "metal_mountain", "acid_swamp",
	"crystal_cave", "air_realm", "life_plain", "electro_lab",
]

# SPEC-05 §7 表格：id -> 显示名。
const SPEC_NAMES: Dictionary = {
	"grassland": "草原",
	"camp": "营地",
	"saltlake": "盐湖",
	"mine": "矿洞一层",
	"academy": "导师学院",
	"deep_mine": "深层矿洞",
	"volcano": "火山口·熔炉高地",
	"metal_mountain": "金属矿山",
	"acid_swamp": "酸碱沼泽",
	"crystal_cave": "水晶矿洞",
	"air_realm": "气之国",
	"life_plain": "生命草原",
	"electro_lab": "电解实验室",
}

# SPEC-05 §7 已解锁区域的 brief（逐字照抄）。
const SPEC_BRIEFS: Dictionary = {
	"grassland": "出生地。空气中氮气约 78%、氧气约 21%。",
	"camp": "炼金术士的家。过滤器、电解器、合成台、篝火、床都在这儿。",
	"saltlake": "安全的收集区。湖水是硬水，湖边有粗盐结晶。",
	"mine": "氧气稀薄、光线昏暗，硫与矿石都在这里。小心 CO 幽灵。",
	"academy": "四位导师常驻的安全区。不懂就问，这里没有笨问题。",
}

# SPEC-05 §7 未解锁区域的 teaser（逐字照抄，含「（赛后解锁）」）。
const SPEC_TEASERS: Dictionary = {
	"deep_mine": "氧气趋近于零的深处，有紫色晶体在发光……（赛后解锁）",
	"volcano": "高炉轰鸣，铁水奔流——石灰三角与工业炼铁之地（赛后解锁）",
	"metal_mountain": "活动性石碑矗立山中，能置换者生，不能者败（赛后解锁）",
	"acid_swamp": "石蕊之门后，pH 是唯一的通行证（赛后解锁）",
	"crystal_cave": "沉淀与结晶的迷宫，无色溶液等你鉴别（赛后解锁）",
	"air_realm": "漂浮在氮与氧之间的国度，燃烧在这里有不同的法则（赛后解锁）",
	"life_plain": "有机物与化肥的田野，种下知识收获葡萄糖（赛后解锁）",
	"electro_lab": "高压与催化剂之地，水在这里一分为二（赛后解锁）",
}

var _rows: Array[Dictionary] = []
var _by_id: Dictionary = {}


func before_each() -> void:
	_rows = Fixture.rows_of("worldmap.json")
	_by_id = {}
	for row in _rows:
		_by_id[str(row.get("id", ""))] = row


# AC1：13 条齐全，id 唯一。
func test_zone_count_is_thirteen_with_unique_ids() -> void:
	assert_eq(_rows.size(), EXPECTED_COUNT, "worldmap.json 必须恰好 13 条")
	var seen: Dictionary = {}
	for row in _rows:
		var id: String = str(row.get("id", ""))
		assert_false(id.is_empty(), "存在 id 为空的区域")
		assert_false(seen.has(id), "重复区域 id：%s" % id)
		seen[id] = true


# AC1：5 条 unlocked: true、8 条 false，且解锁集合与五个可玩区域一致。
func test_exactly_five_unlocked_matching_playable_zones() -> void:
	var unlocked: Array[String] = []
	var locked: Array[String] = []
	for row in _rows:
		if row.get("unlocked", false) == true:
			unlocked.append(str(row.get("id", "")))
		else:
			locked.append(str(row.get("id", "")))
	assert_eq(unlocked.size(), EXPECTED_UNLOCKED, "必须恰好 5 条 unlocked=true")
	assert_eq(locked.size(), EXPECTED_COUNT - EXPECTED_UNLOCKED, "必须恰好 8 条 unlocked=false")
	for id in SPEC_UNLOCKED_IDS:
		assert_true(unlocked.has(id), "已解锁区域缺失：%s" % id)
	for id in SPEC_LOCKED_IDS:
		assert_true(locked.has(id), "未解锁区域缺失：%s" % id)


# unlocked 必须是真布尔值（SPEC-04 §8 标记为必填）。
func test_unlocked_field_is_boolean() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		assert_true(row.has("unlocked"), "%s 缺 unlocked 字段" % id)
		assert_eq(typeof(row.get("unlocked", null)), TYPE_BOOL, "%s 的 unlocked 必须是布尔值" % id)


# 显示名逐字对齐 SPEC-05 §7。
func test_zone_names_match_spec_verbatim() -> void:
	for id in SPEC_NAMES:
		var row: Dictionary = _by_id.get(id, {})
		assert_false(row.is_empty(), "区域缺失：%s" % id)
		assert_eq(str(row.get("name", "")), str(SPEC_NAMES[id]), "%s 的 name 与 SPEC-05 §7 不一致" % id)


# 解锁项 brief 非空且逐字对齐 SPEC-05 §7。
func test_unlocked_zones_have_brief_verbatim() -> void:
	for id in SPEC_BRIEFS:
		var row: Dictionary = _by_id.get(id, {})
		var brief: String = str(row.get("brief", ""))
		assert_false(brief.is_empty(), "%s 已解锁但 brief 为空" % id)
		assert_eq(brief, str(SPEC_BRIEFS[id]), "%s 的 brief 与 SPEC-05 §7 不一致" % id)


# AC2：未解锁条目均有预告语，且逐字对齐 SPEC-05 §7。
func test_locked_zones_have_teaser_verbatim() -> void:
	for id in SPEC_TEASERS:
		var row: Dictionary = _by_id.get(id, {})
		var teaser: String = str(row.get("teaser", ""))
		assert_false(teaser.is_empty(), "%s 未解锁但 teaser 为空" % id)
		assert_eq(teaser, str(SPEC_TEASERS[id]), "%s 的 teaser 与 SPEC-05 §7 不一致" % id)


# 每条都要按解锁状态填对字段：解锁项 brief 非空，未解锁项 teaser 非空。
func test_brief_and_teaser_filled_by_unlock_state() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		if row.get("unlocked", false) == true:
			assert_false(str(row.get("brief", "")).is_empty(), "%s 解锁项必须有 brief" % id)
		else:
			assert_false(str(row.get("teaser", "")).is_empty(), "%s 未解锁项必须有 teaser" % id)


# 热区结构完整、数值为整数、尺寸为正。
func test_hotspots_well_formed() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var hotspot: Variant = row.get("hotspot", null)
		assert_eq(typeof(hotspot), TYPE_DICTIONARY, "%s 的 hotspot 必须是字典" % id)
		var rect: Dictionary = hotspot as Dictionary
		for field in HOTSPOT_FIELDS:
			assert_true(rect.has(field), "%s 的 hotspot 缺 %s" % [id, field])
		assert_gt(int(rect.get("w", 0)), 0, "%s 的 hotspot 宽度必须为正" % id)
		assert_gt(int(rect.get("h", 0)), 0, "%s 的 hotspot 高度必须为正" % id)
		assert_gte(int(rect.get("x", -1)), 0, "%s 的 hotspot x 不能为负" % id)
		assert_gte(int(rect.get("y", -1)), 0, "%s 的 hotspot y 不能为负" % id)


# 校验规则：热区不越出 640×360 视口。
func test_hotspots_within_viewport() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var rect: Dictionary = row.get("hotspot", {}) as Dictionary
		var right: int = int(rect.get("x", 0)) + int(rect.get("w", 0))
		var bottom: int = int(rect.get("y", 0)) + int(rect.get("h", 0))
		assert_lte(right, VIEWPORT_WIDTH, "%s 的 hotspot 右边界越出 640：%d" % [id, right])
		assert_lte(bottom, VIEWPORT_HEIGHT, "%s 的 hotspot 下边界越出 360：%d" % [id, bottom])


# 热区互不重叠，否则地图页点击归属有歧义。
func test_hotspots_do_not_overlap() -> void:
	for i in range(_rows.size()):
		for j in range(i + 1, _rows.size()):
			var a: Rect2i = _rect_of(_rows[i])
			var b: Rect2i = _rect_of(_rows[j])
			assert_false(
				a.intersects(b),
				"热区重叠：%s 与 %s" % [str(_rows[i].get("id", "")), str(_rows[j].get("id", ""))]
			)


func _rect_of(row: Dictionary) -> Rect2i:
	var rect: Dictionary = row.get("hotspot", {}) as Dictionary
	return Rect2i(
		int(rect.get("x", 0)), int(rect.get("y", 0)),
		int(rect.get("w", 0)), int(rect.get("h", 0))
	)
