# 包D / 物品来源指引：items.json 与 substances.json 每条都必须有非空 obtain 字段。
# obtain 是玩家可见的「获取途径」文案，图鉴 tooltip 展示（codex_cell）。
# 内容必须与 recipes.json / 设施脚本的真实来源一致（改内容不改代码，铁律 4）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const FIELD_OBTAIN: String = "obtain"
const TABLES: Array[String] = ["items.json", "substances.json"]

# 无配方产出道具的来源裁决依据（WORKLOG D4 / SPEC-02 §5 道具表 / 白盒地图采集标记）。
# 收口 W2：nahco3 是 r_extinguisher 必需原料，原 obtain 为「暂无产出途径（来源待补）」，
# 已按 carbon_mask 同模式在营地试剂架补采集标记，obtain 必须写明真实来源。
const EXPECTED_OBTAIN: Dictionary = {
	"carbon_mask": "营地试剂架",
	"oxygen_tank": "电解器",
	"soap_water": "营地",
	"nahco3": "营地试剂架",
}


func test_every_row_has_non_empty_obtain() -> void:
	for table_name in TABLES:
		var rows: Array[Dictionary] = Fixture.rows_of(table_name)
		assert_false(rows.is_empty(), "%s 应可读取且非空" % table_name)
		for row in rows:
			var id: String = str(row.get("id", ""))
			var obtain: Variant = row.get(FIELD_OBTAIN, null)
			assert_eq(
				typeof(obtain), TYPE_STRING,
				"%s 的 %s 缺少 obtain 字段（须为字符串）" % [table_name, id]
			)
			if typeof(obtain) == TYPE_STRING:
				assert_false(
					str(obtain).strip_edges().is_empty(),
					"%s 的 %s 的 obtain 为空" % [table_name, id]
				)


# D4 裁决过的三条无配方道具，obtain 必须写明真实来源（与设施逻辑一致）。
func test_key_items_obtain_matches_real_source() -> void:
	var by_id: Dictionary = {}
	for row in Fixture.rows_of("items.json"):
		by_id[str(row.get("id", ""))] = row
	for item_id in EXPECTED_OBTAIN:
		var row: Dictionary = by_id.get(item_id, {})
		assert_false(row.is_empty(), "items.json 缺少 %s" % item_id)
		var obtain: String = str(row.get(FIELD_OBTAIN, ""))
		assert_true(
			obtain.contains(str(EXPECTED_OBTAIN[item_id])),
			"%s 的 obtain 应写明真实来源「%s」，实际：%s" % [item_id, str(EXPECTED_OBTAIN[item_id]), obtain]
		)
