# Inventory（FR-G-02，UT-G02）：8 格快捷栏 + 堆叠上限 99。
# 纯逻辑 RefCounted，不进场景树、可直接实例化（SPEC-06 §3 可测性约束）。
# 格数与堆叠上限读自 balance.json，改表即改行为（铁律 4）。
extends RefCounted

signal inventory_changed()

# ==== 常量区 ====

const BAL_SLOTS: String = "inventory.hotbar_slots"
const BAL_STACK: String = "inventory.stack_limit"

# 数据表缺失时的兜底默认值（不属调参项，见 SPEC-01 §10 NFR-04 判定口径）。
const FALLBACK_SLOTS: int = 8
const FALLBACK_STACK: int = 99

const KEY_ID: String = "id"
const KEY_COUNT: String = "count"

# ==== 逻辑区 ====

# 只保存已占用的格子，顺序即界面显示顺序；长度 <= _slot_count。
var _slots: Array[Dictionary] = []
var _slot_count: int = FALLBACK_SLOTS
var _stack_limit: int = FALLBACK_STACK

func _init() -> void:
	_slot_count = maxi(int(_balance(BAL_SLOTS, FALLBACK_SLOTS)), 1)
	_stack_limit = maxi(int(_balance(BAL_STACK, FALLBACK_STACK)), 1)


func slot_count() -> int:
	return _slot_count


func stack_limit() -> int:
	return _stack_limit


func used_slots() -> int:
	return _slots.size()


# 已占用格子的副本（界面渲染用；外部改副本不影响背包状态）。
func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: Dictionary in _slots:
		out.append(slot.duplicate())
	return out


func count_of(item_id: String) -> int:
	var total: int = 0
	for slot: Dictionary in _slots:
		if str(slot.get(KEY_ID, "")) == item_id:
			total += int(slot.get(KEY_COUNT, 0))
	return total


func has_item(item_id: String, count: int) -> bool:
	if item_id.is_empty() or count <= 0:
		return false
	return count_of(item_id) >= count

# 装入物品，返回**未装入**的数量（AC2：背包满时不静默丢弃）。
func add_item(item_id: String, count: int) -> int:
	if count <= 0:
		return 0
	if item_id.is_empty():
		push_warning("[inv] add_item 收到空 id（整份退回 %d）" % count)
		return count
	var left: int = count
	# 先填已有同物品的格子（AC1：同物品堆叠，不占新格）。
	for slot: Dictionary in _slots:
		if left <= 0:
			break
		if str(slot.get(KEY_ID, "")) != item_id:
			continue
		var room: int = _stack_limit - int(slot.get(KEY_COUNT, 0))
		if room <= 0:
			continue
		var put: int = mini(room, left)
		slot[KEY_COUNT] = int(slot.get(KEY_COUNT, 0)) + put
		left -= put
	# 再开新格直到格数用尽（AC1：超过上限溢出新格；AC2：无格可放则退回剩余）。
	while left > 0 and _slots.size() < _slot_count:
		var put: int = mini(_stack_limit, left)
		_slots.append({KEY_ID: item_id, KEY_COUNT: put})
		left -= put
	if left != count:
		inventory_changed.emit()
	return left


# 扣减物品，数量不足返回 false 且状态完全不变（AC3：不许部分扣减）。
func remove_item(item_id: String, count: int) -> bool:
	if item_id.is_empty() or count <= 0:
		return false
	if count_of(item_id) < count:
		return false
	var left: int = count
	# 从后往前扣，扣空的格子立即释放（下标倒序遍历避免删除时错位）。
	for i: int in range(_slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var slot: Dictionary = _slots[i]
		if str(slot.get(KEY_ID, "")) != item_id:
			continue
		var have: int = int(slot.get(KEY_COUNT, 0))
		var take: int = mini(have, left)
		left -= take
		if take >= have:
			_slots.remove_at(i)
		else:
			slot[KEY_COUNT] = have - take
	inventory_changed.emit()
	return true


# FR-C-06：复活清空背包（掉落由 gameplay 处理）。
func clear() -> void:
	if _slots.is_empty():
		return
	_slots.clear()
	inventory_changed.emit()


# 数值只走 GameManager.get_balance；autoload 缺失时用兜底默认值，不崩溃。
func _balance(key: String, default_value: int) -> Variant:
	var gm: Node = _game_manager()
	if gm == null:
		push_warning("[inv] GameManager 不可用，使用兜底默认值：%s" % key)
		return default_value
	return gm.get_balance(key, default_value)


func _game_manager() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(^"GameManager")

