# DropBag（FR-C-06 AC3/AC4，IT-C06，TP-11）：死亡点掉落包。
# 内含死亡瞬间背包全部物品；带发光标记占位（美术归 P4 替换）；
# 拾取后物品原数量回到背包；不自行消失，只被下一次死亡生成的新包替换（AC4）。
# 交互走 SPEC-03 §5 三方法约定，玩家控制器无需认识本类型。
class_name DropBag
extends Area2D

signal drop_collected(items: Array)

# ==== 常量区 ====

const SCENE_PATH: String = "res://scenes/gameplay/drop_bag.tscn"
const PROMPT_KEY: String = "prompt_interact"

const KEY_ID: String = "id"
const KEY_COUNT: String = "count"

# ==== 逻辑区 ====

# 当前存活的掉落包（全图同时只有一个，AC4：下一次死亡才替换）。
static var _current_bag: DropBag = null

var _items: Array[Dictionary] = []
var _inventory: RefCounted = null
var _collected: bool = false


# 世界编排入口：死亡时在死亡点生成掉落包；上一次死亡的旧包此刻才被移除（AC4）。
static func spawn_at(parent: Node, position: Vector2, items: Array) -> DropBag:
	if is_instance_valid(_current_bag):
		_current_bag.queue_free()
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("[drop] 缺少掉落包场景：%s" % SCENE_PATH)
		return null
	var bag: DropBag = packed.instantiate()
	bag.setup(items)
	parent.add_child(bag)
	bag.global_position = position
	_current_bag = bag
	return bag


# 装入掉落内容（外部数组的深拷贝，之后改背包不影响掉落包）。
func setup(items: Array) -> void:
	_items.clear()
	for entry: Variant in items:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_items.append((entry as Dictionary).duplicate())


# 掉落内容副本（测试与界面断言用；外部改副本不影响包内物品）。
func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _items:
		out.append(entry.duplicate())
	return out


# 非契约辅助（SPEC-06 §3 可测性约束）：世界生成掉落包后注入玩家背包。
func set_inventory(inventory: RefCounted) -> void:
	_inventory = inventory


# ==== IInteractable（SPEC-03 §5） ====

func get_interact_prompt() -> String:
	return PROMPT_KEY


func can_interact() -> bool:
	return not _collected


func interact(_player: Node) -> void:
	if _collected:
		return
	if _inventory == null:
		push_warning("[drop] 未注入背包，拾取被忽略（掉落包保留）")
		return
	_collected = true
	for entry: Dictionary in _items:
		_inventory.add_item(str(entry.get(KEY_ID, "")), int(entry.get(KEY_COUNT, 0)))
	drop_collected.emit(items())
	if _current_bag == self:
		_current_bag = null
	queue_free()
