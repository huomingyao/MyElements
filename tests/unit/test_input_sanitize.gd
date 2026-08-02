# UT-M03 / FR-M-03：玩家输入清理。>200 字符被截断；控制字符与换行被清理；
# 空输入不发起请求；输入只当文本，不进任何代码执行路径（AC3）。
# 清理入口在 LLMClient.sanitize_input（SPEC-03 §6.2），进 prompt 的文本必须先过它。
extends GutTest

# AC3 的可自动断言部分：这些目录里不许出现表达式求值调用。
const SCANNED_DIRS: Array[String] = ["res://scripts/mentor", "res://scripts/autoload"]
const FORBIDDEN_EVAL_CALLS: Array[String] = ["Expression.new(", ".eval(", "Expression("]

var llm: Node = null


func before_each() -> void:
	llm = Engine.get_main_loop().root.get_node_or_null(^"LLMClient")
	assert_not_null(llm, "LLMClient autoload 必须存在")
	if llm == null:
		return
	assert_true(llm.has_method("sanitize_input"), "LLMClient 应有 sanitize_input（FR-M-03）")


func _max_chars() -> int:
	var gm: Node = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	if gm == null:
		return -1
	return int(gm.get_balance("llm.input_max_chars", -1))


# AC1：超过上限被截断。上限读自 balance.json，不写死在实现里。
func test_over_limit_input_is_truncated() -> void:
	if llm == null:
		return
	var limit: int = _max_chars()
	assert_gt(limit, 0, "balance.json 应有 llm.input_max_chars")
	var clean: String = llm.sanitize_input("氢".repeat(limit + 50))
	assert_eq(clean.length(), limit, "超长输入应截断到 llm.input_max_chars")


func test_input_at_limit_is_kept_whole() -> void:
	if llm == null:
		return
	var limit: int = _max_chars()
	assert_eq(llm.sanitize_input("氧".repeat(limit)).length(), limit, "刚好等于上限不该被截")


# AC2：换行、制表、回车与其它 C0 控制符被清理，不残留进 prompt。
func test_control_characters_and_newlines_are_removed() -> void:
	if llm == null:
		return
	var clean: String = llm.sanitize_input("氢气\n怎么\t合成\r水")
	assert_false(clean.contains("\n"), "换行应被清理：%s" % clean)
	assert_false(clean.contains("\t"), "制表符应被清理：%s" % clean)
	assert_false(clean.contains("\r"), "回车应被清理：%s" % clean)
	assert_true(clean.contains("氢气"), "正文应保留：%s" % clean)
	assert_true(clean.contains("水"), "正文应保留：%s" % clean)


# 控制符换成空格后不许留下连续空白（否则 prompt 里出现无意义空洞）。
func test_whitespace_is_collapsed_and_trimmed() -> void:
	if llm == null:
		return
	assert_eq(llm.sanitize_input("  氢气\n\n\n怎么用  "), "氢气 怎么用", "首尾去空白 + 连续空白折叠")


# AC2：空输入 / 纯空白 / 纯控制符都算空，不发起请求。
func test_blank_input_yields_empty_string() -> void:
	if llm == null:
		return
	assert_eq(llm.sanitize_input(""), "", "空串仍为空")
	assert_eq(llm.sanitize_input("   "), "", "纯空格视为空")
	assert_eq(llm.sanitize_input("\n\t\r"), "", "纯控制符视为空")


# AC2：ask() 遇到空输入直接返回空串，不进网络也不进兜底。
func test_ask_with_blank_input_returns_empty_without_request() -> void:
	if llm == null:
		return
	assert_true(llm.has_method("ask"), "LLMClient 应有 ask")
	var reply: String = await llm.ask("chem", "   \n  ", [])
	assert_eq(reply, "", "空输入不该发起请求（FR-M-03 AC2）")


# AC3：清理后的文本只是数据。这里断言可自动化的部分——代码里没有表达式求值。
func test_no_expression_evaluation_in_mentor_or_autoload_code() -> void:
	for dir_path in SCANNED_DIRS:
		for file_path in _gd_files(dir_path):
			var text: String = FileAccess.get_file_as_string(file_path)
			for forbidden in FORBIDDEN_EVAL_CALLS:
				assert_false(
					text.contains(forbidden),
					"%s 不该出现表达式求值「%s」（FR-M-03 AC3）" % [file_path, forbidden]
				)


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
	return out

