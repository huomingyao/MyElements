# 离线兜底问答（FR-M-09 / SPEC-03 §6.3）。
# 纯逻辑类：不进场景树、可直接 new()（SPEC-06 §3 可测性约束）。
# 全部话术读自 data/qa_fallback.json——包括零命中兜底行（SPEC-04 §7 兜底行约定），
# 代码里不许出现一个字的玩家可见文案（NFR-04）。
# 「（离线模式）」角标由调用方（LLMClient）追加，不写进 answer（SPEC-04 §7 匹配规则 5）。
extends RefCounted

# ==== 常量区 ===
const TABLE_FILE: String = "qa_fallback.json"

const F_KEYWORDS: String = "keywords"
const F_ANSWER: String = "answer"
const F_MENTOR_ID: String = "mentor_id"

# ==== 状态区 ===
# 可命中行（keywords 非空）与兜底行（keywords 为空）分开存，避免每次匹配都判一遍。
var _rows: Array = []
var _fallback: Dictionary = {}

# ==== 逻辑区 ===
func _init() -> void:
	load_from(DataLoader.load_table(TABLE_FILE, TYPE_ARRAY, []) as Array)


# 数据注入口（SPEC-06 §3）：测试传改过的行，行为随之改变。
# 数组顺序即平票优先级——先出现者胜（SPEC-04 §7 匹配规则 3）。
func load_from(rows: Array) -> void:
	_rows = []
	_fallback = {}
	for row_value in rows:
		if typeof(row_value) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_value
		if _keywords_of(row).is_empty():
			if _fallback.is_empty():
				_fallback = row
			continue
		_rows.append(row)


# 命中的关键词个数。空关键词与空问题恒不命中：空串会命中一切，让匹配失去意义。
func match_score(question: String, keywords: Array) -> int:
	if question.is_empty():
		return 0
	var score: int = 0
	for keyword_value in keywords:
		var keyword: String = str(keyword_value).strip_edges()
		if not keyword.is_empty() and question.contains(keyword):
			score += 1
	return score


# 命中数最多者胜；平票取表中先出现者；零命中取兜底行。
# 表里没有兜底行时返回空字典——不凭空造话术，交调用方处置。
func best_row(question: String) -> Dictionary:
	var clean: String = question.strip_edges()
	var best: Dictionary = {}
	var best_score: int = 0
	for row_value in _rows:
		var row: Dictionary = row_value
		var score: int = match_score(clean, _keywords_of(row))
		# 严格大于：平票时不覆盖已选中的先出现者（SPEC-04 §7 规则 3）。
		if score > best_score:
			best_score = score
			best = row
	if best_score <= 0:
		return _fallback
	return best


func answer(question: String) -> String:
	return str(best_row(question).get(F_ANSWER, ""))


# 聊天框要显示是谁在说话；零命中时是班主任（SPEC-05 §5 末）。
func mentor_id_for(question: String) -> String:
	return str(best_row(question).get(F_MENTOR_ID, ""))


func _keywords_of(row: Dictionary) -> Array:
	var value: Variant = row.get(F_KEYWORDS, [])
	if typeof(value) != TYPE_ARRAY:
		return []
	return value as Array
