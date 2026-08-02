# IT-G08 / FR-G-08、IT-G09 / FR-G-09：氢气爆炸事件与验纯解锁。
# 状态机见 SPEC-02 §4.5；契约依赖 SPEC-03 §2（GameManager 标记/三值）、
# §3（KnowledgeTip 字幕）、§4（RecipeDB try_craft 规则 3）。
# 用 load() 按路径取脚本而不是直接引用 class_name：实现缺失时是断言失败而非编译错误（SPEC-06 §2）。
extends GutTest

const EVENT_PATH: String = "res://scripts/gameplay/hydrogen_event.gd"
const RECIPE_ID: String = "r_hydrogen_burn"
const H2_O2: Array = ["h2", "o2"]

# 契约方法与信号：先断言存在，否则脚本错误会中断 before_each 让后续测试假绿。
const CONTRACT_METHODS: Array[String] = [
	"ignite", "is_purity_check_available", "do_purity_check", "unlock_purity_check",
]
const CONTRACT_SIGNALS: Array[String] = ["explosion_triggered", "purity_check_performed"]

var event: RefCounted = null
var gm: Node = null
var tip: Node = null
var db: Node = null
var _ready_ok: bool = false


func before_each() -> void:
	_ready_ok = false
	event = null
	var root: Node = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	tip = root.get_node_or_null(^"KnowledgeTip")
	db = root.get_node_or_null(^"RecipeDB")
	assert_not_null(gm, "GameManager autoload 必须存在")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	assert_not_null(db, "RecipeDB autoload 必须存在")
	if gm == null or tip == null or db == null:
		return
	if not ResourceLoader.exists(EVENT_PATH):
		fail_test("尚未实现 %s（FR-G-08/FR-G-09）" % EVENT_PATH)
		return
	var script: Resource = load(EVENT_PATH)
	assert_not_null(script, "hydrogen_event.gd 应可加载")
	if script == null:
		return
	event = script.new()
	assert_not_null(event, "HydrogenEvent 应可直接实例化（SPEC-06 §3 纯逻辑可测性）")
	if event == null:
		return
	for method_name: String in CONTRACT_METHODS:
		assert_true(event.has_method(method_name), "缺契约方法 %s" % method_name)
	for signal_name: String in CONTRACT_SIGNALS:
		assert_true(event.has_signal(signal_name), "缺契约信号 %s" % signal_name)
	# autoload 是单例，状态会跨测试残留，逐个测试复位以保证独立性。
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	gm.set_flag("explosion_happened", false)
	gm.set_flag("purity_check_unlocked", false)
	tip.reload()
	db.reload()
	db.reset_unlocked()
	_ready_ok = true


func after_each() -> void:
	# 演示保险开关的测试会直接改 _balance，必须 reload 还原，别污染其他测试文件。
	if gm != null:
		gm.reload_config()
		gm.reset_stats()
		gm.set_flag("explosion_happened", false)
		gm.set_flag("purity_check_unlocked", false)
	if tip != null:
		tip.reload()


# 爆炸伤害真值来源是 balance.json，测试里只做交叉验证。
func _explosion_damage() -> float:
	return float(gm.get_balance("damage.hydrogen_explosion", -1.0))


# ---------- IT-G08 / FR-G-08 氢气爆炸事件 ----------

# AC1（逻辑级）：获得 H₂ 后「点燃」选项有数据支撑——R4 配方存在且为 便携格/点燃。
# 合成界面的可见按钮属 TP-07 craft_* 场景，不在本任务文件白名单内。
func test_ignite_option_is_data_backed() -> void:
	if not _ready_ok:
		return
	var recipe: Dictionary = db.get_recipe(RECIPE_ID)
	assert_false(recipe.is_empty(), "recipes.json 必须有 %s（点燃选项的数据来源）" % RECIPE_ID)
	assert_eq(str(recipe.get("tool", "")), "portable", "R4 器材应为便携格")
	assert_eq(str(recipe.get("condition", "")), "ignite", "R4 条件应为点燃")
	assert_true((recipe.get("inputs", []) as Array).has("h2"), "R4 材料应含氢气")


# AC2：未验纯点燃 → 生命精确按表扣减（50），并发爆炸信号供动画/音效层挂载。
func test_unpure_ignite_damages_exactly_table_value() -> void:
	if not _ready_ok:
		return
	var damage: float = _explosion_damage()
	assert_almost_eq(damage, 50.0, 0.001, "balance 里的爆炸伤害应为 50（SPEC-02 §4.1）")
	watch_signals(event)
	var health_before: float = gm.health
	var result: Dictionary = event.ignite(H2_O2)
	assert_false(bool(result.get("success", false)), "未验纯点燃不应成功")
	assert_eq(str(result.get("fail_reason", "")), "needs_purity_check", "应报 needs_purity_check")
	assert_almost_eq(gm.health, health_before - damage, 0.001, "生命应精确按表扣减")
	assert_signal_emitted(event, "explosion_triggered", "应发爆炸信号（屏幕震动+火光+音效的挂载点）")


# AC2：爆炸显示 sys_explosion_warn 警示字幕，warning 样式，时长来自 tips.json（5 秒）。
func test_explosion_shows_warning_tip_for_table_duration() -> void:
	if not _ready_ok:
		return
	event.ignite(H2_O2)
	assert_eq(tip.current_tip_id(), "sys_explosion_warn", "应立即显示警示字幕")
	assert_eq(tip.current_style(), "warning", "警示字幕应为 warning 样式")
	tip.advance(4.9)
	assert_eq(tip.current_tip_id(), "sys_explosion_warn", "5 秒内应仍在显示")
	tip.advance(0.2)
	assert_eq(tip.current_tip_id(), "", "超过 5 秒应播完")


# AC3：爆炸后置全局标记 explosion_happened（导师提示与验纯解锁使用）。
func test_explosion_sets_global_flag() -> void:
	if not _ready_ok:
		return
	watch_signals(gm)
	event.ignite(H2_O2)
	assert_true(gm.get_flag("explosion_happened"), "爆炸后应置 explosion_happened")
	assert_signal_emitted_with_parameters(gm, "flag_changed", ["explosion_happened", true])


# AC4：生命不足 50 时爆炸致死，走 FR-C-06 死亡流程且不卡死（结果照常返回、信号照常发）。
func test_explosion_at_low_health_triggers_death_without_hang() -> void:
	if not _ready_ok:
		return
	var damage: float = _explosion_damage()
	# 把生命调到伤害值以下（40），爆炸后必归零。
	gm.modify_health(-(gm.health - (damage - 10.0)))
	assert_true(gm.health < damage, "前置条件：生命低于爆炸伤害")
	watch_signals(gm)
	watch_signals(event)
	var result: Dictionary = event.ignite(H2_O2)
	assert_almost_eq(gm.health, 0.0, 0.001, "生命应归零")
	assert_signal_emit_count(gm, "player_died", 1, "死亡信号只发一次（SPEC-03 §2.4 去重）")
	assert_signal_emitted(event, "explosion_triggered", "致死爆炸仍有爆炸表现")
	assert_true(gm.get_flag("explosion_happened"), "致死也要置标记")
	assert_eq(tip.current_tip_id(), "sys_explosion_warn", "致死也要显示警示字幕")
	assert_false(bool(result.get("success", false)), "结果仍按失败返回，流程不卡死")


# 未验纯状态下重复点燃：每次都爆炸扣血（标记去重不影响伤害结算）。
func test_repeated_unpure_ignite_explodes_again() -> void:
	if not _ready_ok:
		return
	var damage: float = _explosion_damage()
	event.ignite(H2_O2)
	var health_after_first: float = gm.health
	event.ignite(H2_O2)
	assert_almost_eq(gm.health, health_after_first - damage, 0.001, "第二次未验纯点燃应再次扣血")


# ---------- IT-G09 / FR-G-09 验纯解锁与成功点燃 ----------

# AC1：问过导师（unlock_purity_check 回调）前不出现验纯步骤，问过后出现。
func test_purity_step_unlocked_by_mentor_answer() -> void:
	if not _ready_ok:
		return
	assert_false(event.is_purity_check_available(), "未问导师前不应出现验纯步骤")
	event.unlock_purity_check()
	assert_true(gm.get_flag("purity_check_unlocked"), "回调应置 purity_check_unlocked")
	assert_true(event.is_purity_check_available(), "问过导师后应出现验纯步骤")


# AC2：验纯播放"噗"轻响（purity_check_performed 信号给音效层）并显示 sys_purity_ok。
func test_do_purity_check_shows_tip_and_emits_signal() -> void:
	if not _ready_ok:
		return
	event.unlock_purity_check()
	watch_signals(event)
	var performed: bool = event.do_purity_check()
	assert_true(performed, "解锁后验纯应执行成功")
	assert_eq(tip.current_tip_id(), "sys_purity_ok", "应显示验纯成功字幕")
	assert_signal_emitted(event, "purity_check_performed", "应发验纯信号（噗声音效的挂载点）")


# 未解锁时验纯被拒绝：不显示字幕、不发信号。
func test_do_purity_check_rejected_when_locked() -> void:
	if not _ready_ok:
		return
	watch_signals(event)
	var performed: bool = event.do_purity_check()
	assert_false(performed, "未解锁不应能验纯")
	assert_eq(tip.current_tip_id(), "", "未解锁不应显示字幕")
	assert_signal_not_emitted(event, "purity_check_performed", "未解锁不应发验纯信号")


# AC3：验纯后点燃成功——产物入包、卡片来自数据表（2H₂+O₂=点燃=2H₂O 与氢能源应用）、不再扣血。
func test_ignite_succeeds_after_purity_check() -> void:
	if not _ready_ok:
		return
	event.unlock_purity_check()
	event.do_purity_check()
	var health_before: float = gm.health
	watch_signals(event)
	var result: Dictionary = event.ignite(["o2", "h2"])
	assert_true(bool(result.get("success", false)), "验纯后点燃应成功")
	assert_eq(result.get("outputs", []), ["h2o"], "产物应为水")
	var recipe: Dictionary = db.get_recipe(RECIPE_ID)
	var card: Dictionary = result.get("card", {})
	assert_eq(str(card.get("equation", "")), str(recipe.get("equation", "")),
		"卡片方程式应来自数据表（2H₂+O₂=点燃=2H₂O）")
	assert_false(str(card.get("application", "")).is_empty(), "卡片应用（氢能源）应非空")
	assert_almost_eq(gm.health, health_before, 0.001, "验纯后点燃不再扣血")
	assert_signal_not_emitted(event, "explosion_triggered", "验纯后不应再爆炸")
	assert_true(db.unlocked_recipes().has(RECIPE_ID), "成功后应登记已解锁（图鉴用）")


# AC4：演示保险开关（balance debug.force_purity_unlock）不问导师即可强制解锁验纯；
# 开关默认关闭，不影响正常流程。
func test_debug_switch_force_unlocks_purity_step() -> void:
	if not _ready_ok:
		return
	assert_false(bool(gm.get_balance("debug.force_purity_unlock", true)), "开关默认应关闭")
	assert_false(event.is_purity_check_available(), "开关关闭时正常流程不受影响")
	# 模拟演示现场拨开关：改内存中的 balance 表（after_each 会 reload 还原）。
	(gm._balance["debug"] as Dictionary)["force_purity_unlock"] = true
	assert_true(event.is_purity_check_available(), "开关打开即强制解锁验纯步骤")
	assert_false(gm.get_flag("purity_check_unlocked"), "开关本身不改导师解锁标记")
	assert_true(event.do_purity_check(), "开关路径下可执行验纯")
	var result: Dictionary = event.ignite(H2_O2)
	assert_true(bool(result.get("success", false)), "开关路径下验纯后点燃应成功")


# 完整剧情链路（SPEC-02 §4.5）：被炸 → 问导师 → 验纯 → 点燃成功。
func test_full_story_explode_then_purity_then_success() -> void:
	if not _ready_ok:
		return
	event.ignite(H2_O2)
	assert_true(gm.get_flag("explosion_happened"), "第一幕：爆炸已发生")
	event.unlock_purity_check()
	assert_true(event.do_purity_check(), "第二幕：问导师后验纯")
	var health_before: float = gm.health
	var result: Dictionary = event.ignite(H2_O2)
	assert_true(bool(result.get("success", false)), "第三幕：验纯后点燃成功")
	assert_almost_eq(gm.health, health_before, 0.001, "第三幕不再扣血")
