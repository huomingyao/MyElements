# FR-G-09 AC1 接线：向导师问过氢气/爆炸/验纯相关问题后，purity_check_unlocked 置位。
# 关键词来源：qa_fallback.json 的 qa_h2_explosion 行（NFR-04：代码零中文关键词）。
extends GutTest

const CHAT_SCENE: String = "res://scenes/mentor/chat_panel.tscn"
const HYDROGEN_SCRIPT: String = "res://scripts/gameplay/hydrogen_event.gd"
const ROUTER_SCRIPT: String = "res://scripts/mentor/mentor_router.gd"
const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

var gm: Node = null
var _hydrogen: RefCounted = null
var _chat: Node = null


func before_each() -> void:
	gm = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	assert_not_null(gm, "GameManager autoload 必须存在")
	if gm == null:
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	gm.set_flag("purity_check_unlocked", false)
	_hydrogen = (load(HYDROGEN_SCRIPT) as GDScript).new()
	_chat = null


func after_each() -> void:
	if gm != null:
		gm.set_flag("purity_check_unlocked", false)


func _skip_unless_hydrogen_method() -> bool:
	if _hydrogen.has_method("question_mentions_hydrogen"):
		return false
	fail_test("HydrogenEvent 应有 question_mentions_hydrogen()（FR-G-09 AC1 接线）")
	return true


# 判定口径：qa_h2_explosion 行的每个关键词都能命中；无关问题不命中。
func test_hydrogen_question_detection_uses_data_keywords() -> void:
	if _skip_unless_hydrogen_method():
		return
	var keywords: Array = []
	for row: Dictionary in Fixture.read_array("qa_fallback.json"):
		if str(row.get("id", "")) == "qa_h2_explosion":
			keywords = row.get("keywords", [])
	assert_true(keywords.size() >= 2, "qa_h2_explosion 应有 ≥2 个关键词")
	for keyword: Variant in keywords:
		var question: String = "请问%s是怎么回事" % str(keyword)
		assert_true(_hydrogen.question_mentions_hydrogen(question), "应命中关键词：%s" % str(keyword))
	assert_false(_hydrogen.question_mentions_hydrogen("今天午饭吃什么"), "无关问题不应命中")
	assert_false(_hydrogen.question_mentions_hydrogen(""), "空串不应命中")


# 聊天接线：问过氢气问题后，合成界面可用的验纯标记被置位。
func test_chat_about_hydrogen_unlocks_purity_check() -> void:
	if not ResourceLoader.exists(CHAT_SCENE):
		fail_test("尚未实现 %s" % CHAT_SCENE)
		return
	_chat = (load(CHAT_SCENE) as PackedScene).instantiate()
	add_child_autofree(_chat)
	await wait_process_frames(1)
	if not _chat.has_method("set_hydrogen_event"):
		fail_test("chat_panel 应有 set_hydrogen_event()（FR-G-09 AC1 接线）")
		return
	_chat.set_hydrogen_event(_hydrogen)
	# 注入固定回复的路由，不发网络请求。
	var router: RefCounted = (load(ROUTER_SCRIPT) as GDScript).new()
	router.set_reply_provider(func(_mentor_id: String, _question: String) -> String: return "ok")
	_chat.set_router(router)
	_chat.typing_chars_per_second = 100000.0
	_chat.open_chat("monitor")
	assert_false(gm.get_flag("purity_check_unlocked"), "提问前未解锁")
	await _chat.send_text("为什么氢气会爆炸")
	assert_true(gm.get_flag("purity_check_unlocked"), "问过氢气爆炸后应解锁验纯")
	assert_true(_hydrogen.is_purity_check_available(), "验纯步骤应可用")


# 反向：无关问题不触发解锁。
func test_unrelated_question_does_not_unlock() -> void:
	if not ResourceLoader.exists(CHAT_SCENE):
		fail_test("尚未实现 %s" % CHAT_SCENE)
		return
	_chat = (load(CHAT_SCENE) as PackedScene).instantiate()
	add_child_autofree(_chat)
	await wait_process_frames(1)
	if not _chat.has_method("set_hydrogen_event"):
		fail_test("chat_panel 应有 set_hydrogen_event()（FR-G-09 AC1 接线）")
		return
	_chat.set_hydrogen_event(_hydrogen)
	var router: RefCounted = (load(ROUTER_SCRIPT) as GDScript).new()
	router.set_reply_provider(func(_mentor_id: String, _question: String) -> String: return "ok")
	_chat.set_router(router)
	_chat.typing_chars_per_second = 100000.0
	_chat.open_chat("monitor")
	await _chat.send_text("怎么提高记忆力")
	assert_false(gm.get_flag("purity_check_unlocked"), "无关问题不应解锁验纯")
