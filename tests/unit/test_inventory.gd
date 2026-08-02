# UT-G02 / FR-G-02：8 格快捷栏 + 堆叠上限 99。堆叠到 99 后溢出新格；
# 背包满时 add_item 返回未装入数量（不静默丢弃）；remove_item 数量不足返回 false 且状态不变。
# 用 load() 按路径取脚本而不是直接引用 class_name：实现缺失时是断言失败而非编译错误（SPEC-06 §2）。
extends GutTest

const INVENTORY_PATH: String = "res://scripts/gameplay/inventory.gd"

# 期望值来自 data/balance.json 的 inventory 段，测试里只做交叉验证不作为真值来源。
const EXPECTED_SLOTS: int = 8
const EXPECTED_STACK: int = 99

var inv: RefCounted = null
var gm: Node = null


func before_each() -> void:
	gm = Engine.get_main_loop().root.get_node_or_null(^"GameManager")
	assert_not_null(gm, "GameManager autoload 必须存在")
	if not ResourceLoader.exists(INVENTORY_PATH):
		fail_test("尚未实现 %s（FR-G-02）" % INVENTORY_PATH)
		return
	var script: Resource = load(INVENTORY_PATH)
	assert_not_null(script, "inventory.gd 应可加载")
	if script == null:
		return
	inv = script.new()
	assert_not_null(inv, "Inventory 应可直接实例化（SPEC-06 §3 纯逻辑可测性）")


# 背包容量：格数与堆叠上限都读自 balance.json，改表即改行为。
func test_capacity_comes_from_balance() -> void:
	if inv == null:
		return
	assert_eq(int(gm.get_balance("inventory.hotbar_slots", -1)), EXPECTED_SLOTS, "balance 里的格数")
	assert_eq(int(gm.get_balance("inventory.stack_limit", -1)), EXPECTED_STACK, "balance 里的堆叠上限")
	assert_eq(inv.slot_count(), EXPECTED_SLOTS, "Inventory 格数应取自 balance")
	assert_eq(inv.stack_limit(), EXPECTED_STACK, "Inventory 堆叠上限应取自 balance")


# 新背包是空的：格子全空、总量为 0。
func test_new_inventory_is_empty() -> void:
	if inv == null:
		return
	assert_eq(inv.count_of("s"), 0, "空背包里任何物品数量应为 0")
	assert_eq(inv.used_slots(), 0, "空背包已用格数应为 0")
	assert_false(inv.has_item("s", 1), "空背包不应有物品")


# AC1：同一物品累加进同一格，不占新格。
func test_add_item_stacks_in_one_slot() -> void:
	if inv == null:
		return
	assert_eq(inv.add_item("s", 10), 0, "有空间时应全部装入，返回未装入 0")
	assert_eq(inv.add_item("s", 5), 0, "继续堆叠应全部装入")
	assert_eq(inv.count_of("s"), 15, "同物品应累加")
	assert_eq(inv.used_slots(), 1, "同物品应只占一格")


# AC1：堆叠到 99 后溢出到新格，总量不丢。
func test_stack_overflows_into_new_slot() -> void:
	if inv == null:
		return
	assert_eq(inv.add_item("s", EXPECTED_STACK + 1), 0, "101 应装得下（两格）")
	assert_eq(inv.count_of("s"), EXPECTED_STACK + 1, "总量应完整保留")
	assert_eq(inv.used_slots(), 2, "超过堆叠上限应占两格")
	var slots: Array = inv.slots()
	assert_eq(int(slots[0].get("count", 0)), EXPECTED_STACK, "第一格应填满到上限")
	assert_eq(int(slots[1].get("count", 0)), 1, "溢出量进第二格")


# AC1：正好等于上限时不额外开格（边界）。
func test_exactly_stack_limit_uses_one_slot() -> void:
	if inv == null:
		return
	assert_eq(inv.add_item("s", EXPECTED_STACK), 0, "正好 99 应装得下")
	assert_eq(inv.used_slots(), 1, "正好 99 应只占一格")


# AC2：背包满时返回未装入的数量，不静默丢弃（8 格 × 99 = 792 为容量上限）。
func test_full_inventory_returns_leftover() -> void:
	if inv == null:
		return
	var capacity: int = EXPECTED_SLOTS * EXPECTED_STACK
	assert_eq(inv.add_item("s", capacity), 0, "刚好装满应无剩余")
	assert_eq(inv.used_slots(), EXPECTED_SLOTS, "应占满 8 格")
	assert_eq(inv.add_item("s", 7), 7, "背包满时应返回未装入的 7")
	assert_eq(inv.count_of("s"), capacity, "满包后总量不应增加")


# AC2：部分装入时返回差额，装入的部分真的进去了。
func test_partial_add_returns_only_leftover() -> void:
	if inv == null:
		return
	var capacity: int = EXPECTED_SLOTS * EXPECTED_STACK
	inv.add_item("s", capacity - 3)
	assert_eq(inv.add_item("s", 10), 7, "只装得下 3 个，应返回 7")
	assert_eq(inv.count_of("s"), capacity, "剩余空间应被填满")


# AC2：8 格快捷栏边界——不同物品各占一格，第 9 种装不进去。
func test_slot_count_boundary_with_distinct_items() -> void:
	if inv == null:
		return
	var ids: Array[String] = ["o2", "h2", "c", "s", "co", "h2o", "caco3", "fe"]
	for id: String in ids:
		assert_eq(inv.add_item(id, 1), 0, "前 8 种物品应各占一格：%s" % id)
	assert_eq(inv.used_slots(), EXPECTED_SLOTS, "应正好占满 8 格")
	assert_eq(inv.add_item("nacl", 1), 1, "第 9 种物品无格可放，应整份退回")
	assert_eq(inv.count_of("nacl"), 0, "退回的物品不应进背包")


# 满格但同物品仍有堆叠空间时可以继续放（占格判断按物品而非格数）。
func test_full_slots_still_accept_same_item() -> void:
	if inv == null:
		return
	var ids: Array[String] = ["o2", "h2", "c", "s", "co", "h2o", "caco3", "fe"]
	for id: String in ids:
		inv.add_item(id, 1)
	assert_eq(inv.add_item("fe", 5), 0, "已在包内的物品仍可堆叠")
	assert_eq(inv.count_of("fe"), 6, "堆叠应生效")


# can_add（2026-08-03，背包满拾取反馈的判定口）：堆叠感知容量查询——
# 同种物品堆叠还有空间或有空格即不算满；数量需整份装得下才返回 true。
func test_can_add_on_empty_inventory() -> void:
	if inv == null:
		return
	assert_true(inv.has_method("can_add"), "Inventory 应有 can_add(item_id, count)（背包满判定口）")
	if not inv.has_method("can_add"):
		return
	assert_true(bool(inv.can_add("s", 1)), "空背包应可装入")
	assert_true(bool(inv.can_add("s", EXPECTED_SLOTS * EXPECTED_STACK)), "刚好装满整包应可装入")
	assert_false(bool(inv.can_add("s", EXPECTED_SLOTS * EXPECTED_STACK + 1)), "超过整包容量应不可装入")


# 满格但同物品堆叠仍有空间：can_add 必须按堆叠判定，不能只看格数。
func test_can_add_stack_aware_when_slots_full() -> void:
	if inv == null or not inv.has_method("can_add"):
		fail_test("Inventory 应有 can_add(item_id, count)")
		return
	var ids: Array[String] = ["o2", "h2", "c", "s", "co", "h2o", "caco3", "fe"]
	for id: String in ids:
		inv.add_item(id, 1)
	assert_eq(inv.used_slots(), EXPECTED_SLOTS, "前提：8 格占满")
	assert_true(bool(inv.can_add("fe", 1)), "满格但 fe 堆叠有空间，应可装入")
	assert_true(bool(inv.can_add("fe", EXPECTED_STACK - 1)), "fe 堆叠余量内应可装入")
	assert_false(bool(inv.can_add("fe", EXPECTED_STACK)), "超过 fe 堆叠余量应不可装入")
	assert_false(bool(inv.can_add("nacl", 1)), "满格且包内没有的新物品应不可装入")


# 全部塞到堆叠上限后，同物品也放不进去了。
func test_can_add_false_when_truly_full() -> void:
	if inv == null or not inv.has_method("can_add"):
		fail_test("Inventory 应有 can_add(item_id, count)")
		return
	var capacity: int = EXPECTED_SLOTS * EXPECTED_STACK
	inv.add_item("s", capacity)
	assert_false(bool(inv.can_add("s", 1)), "整包塞满后同物品也应不可装入")
	assert_false(bool(inv.can_add("fe", 1)), "整包塞满后新物品应不可装入")


# 防御性输入：空 id / 非正数量永远不可装入，且不改变状态。
func test_can_add_rejects_invalid_input() -> void:
	if inv == null or not inv.has_method("can_add"):
		fail_test("Inventory 应有 can_add(item_id, count)")
		return
	assert_false(bool(inv.can_add("", 1)), "空 id 应不可装入")
	assert_false(bool(inv.can_add("s", 0)), "0 个应不可装入")
	assert_false(bool(inv.can_add("s", -2)), "负数应不可装入")
	assert_eq(inv.used_slots(), 0, "查询不应改变背包状态")


# AC3：remove_item 数量足够时返回 true 并扣减。
func test_remove_item_succeeds_when_enough() -> void:
	if inv == null:
		return
	inv.add_item("s", 10)
	assert_true(inv.remove_item("s", 4), "数量足够应返回 true")
	assert_eq(inv.count_of("s"), 6, "应扣减 4")


# AC3：数量不足时返回 false 且状态完全不变（不许部分扣减）。
func test_remove_item_fails_without_changing_state() -> void:
	if inv == null:
		return
	inv.add_item("s", 3)
	assert_false(inv.remove_item("s", 5), "数量不足应返回 false")
	assert_eq(inv.count_of("s"), 3, "失败后数量不应改变")
	assert_false(inv.remove_item("nacl", 1), "不存在的物品应返回 false")
	assert_eq(inv.used_slots(), 1, "失败后占格数不应改变")


# AC3：跨格扣减（99+1 两格）也要正确，扣空的格子要释放。
func test_remove_spans_slots_and_frees_empty_ones() -> void:
	if inv == null:
		return
	inv.add_item("s", EXPECTED_STACK + 1)
	assert_eq(inv.used_slots(), 2, "前提：占两格")
	assert_true(inv.remove_item("s", 2), "跨格扣减应成功")
	assert_eq(inv.count_of("s"), EXPECTED_STACK - 1, "总量应正确")
	assert_eq(inv.used_slots(), 1, "扣空的格子应释放")


# 全部扣空后背包回到空状态。
func test_remove_all_empties_inventory() -> void:
	if inv == null:
		return
	inv.add_item("s", 7)
	assert_true(inv.remove_item("s", 7), "扣完应成功")
	assert_eq(inv.used_slots(), 0, "扣完后应无占格")
	assert_false(inv.has_item("s", 1), "扣完后不应还有物品")


# 防御性输入：数量 ≤ 0 或空 id 不改变状态，也不崩溃。
func test_non_positive_and_empty_input_is_ignored() -> void:
	if inv == null:
		return
	inv.add_item("s", 5)
	assert_eq(inv.add_item("s", 0), 0, "加 0 个应无事发生")
	assert_eq(inv.add_item("s", -3), 0, "加负数应无事发生")
	assert_eq(inv.add_item("", 5), 5, "空 id 应整份退回")
	assert_false(inv.remove_item("s", 0), "扣 0 个应返回 false")
	assert_false(inv.remove_item("s", -1), "扣负数应返回 false")
	assert_eq(inv.count_of("s"), 5, "非法输入后数量不应改变")
	assert_eq(inv.used_slots(), 1, "非法输入后占格数不应改变")


# FR-C-06：复活清空背包（掉落由 gameplay 处理），clear() 要真的清干净。
func test_clear_empties_all_slots() -> void:
	if inv == null:
		return
	inv.add_item("s", 10)
	inv.add_item("fe", 20)
	inv.clear()
	assert_eq(inv.used_slots(), 0, "clear 后应无占格")
	assert_eq(inv.count_of("s"), 0, "clear 后数量应为 0")
	assert_eq(inv.count_of("fe"), 0, "clear 后数量应为 0")


# has_item 按数量判定，供合成台校验材料是否够用。
func test_has_item_checks_count() -> void:
	if inv == null:
		return
	inv.add_item("s", 3)
	assert_true(inv.has_item("s", 3), "刚好够应为 true")
	assert_false(inv.has_item("s", 4), "不够应为 false")
	assert_true(inv.has_item("s", 1), "少于持有量应为 true")


# 变更要发信号供 HUD/背包界面刷新（SPEC-03 §1：不横向直连）。
func test_changes_emit_signal() -> void:
	if inv == null:
		return
	assert_true(inv.has_signal("inventory_changed"), "Inventory 应有 inventory_changed 信号")
	if not inv.has_signal("inventory_changed"):
		return
	watch_signals(inv)
	inv.add_item("s", 1)
	assert_signal_emit_count(inv, "inventory_changed", 1, "成功装入应发一次信号")
	inv.add_item("s", 0)
	assert_signal_emit_count(inv, "inventory_changed", 1, "无变化不应发信号")
	inv.remove_item("s", 1)
	assert_signal_emit_count(inv, "inventory_changed", 2, "扣减成功应发信号")
	inv.remove_item("s", 1)
	assert_signal_emit_count(inv, "inventory_changed", 2, "扣减失败不应发信号")


# 逻辑代码不许出现中文文案（NFR-04；push_warning/push_error/print 诊断日志除外）。
func test_source_has_no_chinese_literals() -> void:
	var file: FileAccess = FileAccess.open(INVENTORY_PATH, FileAccess.READ)
	assert_not_null(file, "inventory.gd 应可读")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("#"):
			continue
		if line.contains("push_warning(") or line.contains("push_error(") or line.contains("print("):
			continue
		var code: String = line
		var comment_at: int = code.find("#")
		if comment_at >= 0:
			code = code.substr(0, comment_at)
		for i: int in code.length():
			var c: int = code.unicode_at(i)
			assert_false(c >= 0x4E00 and c <= 0x9FFF, "逻辑代码出现中文字面量：%s" % line)

