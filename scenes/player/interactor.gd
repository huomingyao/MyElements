# Interactor（FR-P-02，SPEC-03 §5）：挂在玩家身上的 Area2D，
# 跟踪进入范围的可交互对象，按距离选最近的一个。
# 只认 SPEC-03 §5 的三方法约定：对象可挂在 Area2D 本身或其父节点上。
extends Area2D

var _candidates: Array[Node] = []


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


# 范围内最近的交互目标；没有则 null。can_interact 由调用方判。
func nearest_interactable(from: Vector2) -> Node:
	_prune()
	var best: Node = null
	var best_dist: float = INF
	for candidate in _candidates:
		var dist: float = (candidate as Node2D).global_position.distance_to(from)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best


func _on_area_entered(area: Area2D) -> void:
	var target: Node = _resolve(area)
	if target != null and not _candidates.has(target):
		_candidates.append(target)


func _on_area_exited(area: Area2D) -> void:
	var target: Node = _resolve(area)
	if target != null:
		_candidates.erase(target)


# 三方法在 Area2D 上就用它本身，否则看父节点（SPEC-03 §5「挂在 Area2D 或其父节点上」）。
func _resolve(area: Area2D) -> Node:
	if _implements_contract(area):
		return area
	var parent: Node = area.get_parent()
	if parent != null and _implements_contract(parent):
		return parent
	return null


func _implements_contract(node: Node) -> bool:
	return (
		node.has_method("get_interact_prompt")
		and node.has_method("can_interact")
		and node.has_method("interact")
	)


# 对象被 queue_free 后引用变野指针，每次查询前先清掉。
func _prune() -> void:
	_candidates = _candidates.filter(func(node: Node) -> bool: return is_instance_valid(node))
