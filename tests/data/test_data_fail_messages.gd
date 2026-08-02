# 包D / FR-G-07 数据侧：fail_messages.json 按 reason 分池扩充。
# 校验器 FAIL_REASONS 仅允许 no_match / wrong_condition 两类（SPEC-04 §12），
# 每池扩至 ≥3 条以降低重复感；语气鼓励式（「失败即求知」设计），由内容表逐条把关。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const REASONS: Array[String] = ["no_match", "wrong_condition"]
const MIN_PER_POOL: int = 3
const ID_PREFIX: String = "fail_"

var _rows: Array[Dictionary] = []


func before_each() -> void:
	_rows = Fixture.rows_of("fail_messages.json")


# 每个 reason 池 ≥3 条（包D 目标：三类失败场景文案不重复感）。
func test_each_reason_pool_has_at_least_three_messages() -> void:
	var by_reason: Dictionary = {}
	for row in _rows:
		var reason: String = str(row.get("reason", ""))
		by_reason[reason] = int(by_reason.get(reason, 0)) + 1
	for reason in REASONS:
		assert_gte(
			int(by_reason.get(reason, 0)), MIN_PER_POOL,
			"%s 池应 ≥%d 条（包D：降低重复感）" % [reason, MIN_PER_POOL]
		)


# reason 只许取校验器允许的两类（validate_data.gd 的 FAIL_REASONS 枚举）。
func test_reason_values_are_in_allowed_enum() -> void:
	for row in _rows:
		var reason: String = str(row.get("reason", ""))
		assert_true(
			REASONS.has(reason),
			"%s 的 reason「%s」不在允许枚举内（校验器会报错）" % [str(row.get("id", "")), reason]
		)


# id 唯一、fail_ 前缀、text 非空（与校验器第 2/3 类检查同口径）。
func test_rows_well_formed() -> void:
	var seen: Dictionary = {}
	for row in _rows:
		var id: String = str(row.get("id", ""))
		assert_false(id.is_empty(), "存在 id 为空的失败文案")
		assert_true(id.begins_with(ID_PREFIX), "%s 应以 fail_ 前缀命名" % id)
		assert_false(seen.has(id), "重复失败文案 id：%s" % id)
		seen[id] = true
		assert_false(str(row.get("text", "")).strip_edges().is_empty(), "%s 的 text 为空" % id)
