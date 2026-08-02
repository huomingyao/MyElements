# 实验台（FR-G-14，TP-10）：粗盐提纯三步的交互落点。
# 每次 E 交互自动推进当前应做的步骤（溶解 → 过滤 → 蒸发），顺序由状态机强制（AC1）。
# 没有粗盐且没有进行中的流程时给合成引导字幕；通用合成界面由 TP-07（craft_*）接线。
extends "res://scenes/gameplay/facility_base.gd"

# ==== 常量区 ====

const PURIFIER_SCRIPT: String = "res://scenes/gameplay/facility_salt_purifier.gd"
const INPUT_ID: String = "crude_salt"
const STEP_DISSOLVE: String = "dissolve"
const TIP_CRAFT_HINT: String = "sys_craft_hint"

# ==== 逻辑区 ====

var _purifier: RefCounted = null


func _ready() -> void:
	_purifier = (load(PURIFIER_SCRIPT) as GDScript).new()


# 状态机访问口（测试与后续 UI 用）：查询当前应做步骤、注入假状态机。
func purifier() -> RefCounted:
	return _purifier


func interact(player: Node) -> void:
	var inventory: RefCounted = _inventory_of(player)
	if _purifier == null:
		push_warning("[facility] 提纯状态机未初始化")
		return
	if _purifier.is_done():
		# 上一轮已完成：复位，准备下一轮。
		_purifier.reset()
	if _purifier.is_started():
		# 流程进行中：推进到下一步（顺序由状态机强制）。
		_purifier.advance(str(_purifier.expected_step()), inventory)
		return
	if inventory != null and bool(inventory.has_item(INPUT_ID, 1)):
		_purifier.advance(STEP_DISSOLVE, inventory)
		return
	# 空台：引导玩家使用合成（通用合成界面由 TP-07 接线）。
	_show_tip(TIP_CRAFT_HINT)
