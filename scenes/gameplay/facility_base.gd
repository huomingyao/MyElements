# 设施基类（FR-G-13/G-14，TP-10）：所有营地设施共用的交互约定与 autoload 访问助手。
# 只实现 SPEC-03 §5 三方法约定；玩家控制器不认识具体设施类型（FR-P-02 AC3）。
# 文案一律走 KnowledgeTip + 数据表 id（NFR-04），数值走 GameManager.get_balance。
extends Area2D

# ==== 常量区 ====

# 交互提示走 ui_strings.prompt_interact（「按 E」），导师提问才是 prompt_ask（SPEC-05 §9）。
const PROMPT_ID: String = "prompt_interact"

# ==== 逻辑区 ====

func get_interact_prompt() -> String:
	return PROMPT_ID


# 默认总是可交互；缺材料时在 interact() 里给数据表提示字幕，而不是藏起提示气泡。
func can_interact() -> bool:
	return true


func interact(_player: Node) -> void:
	pass


# ==== autoload 访问（缺失时降级为警告日志，不崩溃） ====

func _game_manager() -> Node:
	return get_node_or_null(^"/root/GameManager")


func _knowledge_tip() -> Node:
	return get_node_or_null(^"/root/KnowledgeTip")


func _recipe_db() -> Node:
	return get_node_or_null(^"/root/RecipeDB")


func _show_tip(tip_id: String) -> void:
	var tip: Node = _knowledge_tip()
	if tip == null:
		push_warning("[facility] KnowledgeTip 不可用，字幕未显示：%s" % tip_id)
		return
	tip.show(tip_id)


# 数值只走 balance.json；autoload 缺失时用兜底默认值（不属调参项，见 NFR-04 判定口径）。
func _balance_float(key: String, fallback: float) -> float:
	var gm: Node = _game_manager()
	if gm == null:
		push_warning("[facility] GameManager 不可用，使用兜底默认值：%s" % key)
		return fallback
	return float(gm.get_balance(key, fallback))


# 玩家背包的约定入口：玩家节点暴露 `inventory` 属性（TP-06 的纯逻辑背包，duck-typing）。
# 没有背包或背包不符合约定时返回 null，设施按「缺材料」路径给提示，不崩溃。
func _inventory_of(player: Node) -> RefCounted:
	if player == null:
		return null
	var inv: Variant = player.get("inventory")
	if inv == null or not (inv is RefCounted):
		return null
	var typed: RefCounted = inv
	if not (typed.has_method("add_item") and typed.has_method("remove_item") and typed.has_method("has_item")):
		return null
	return typed
