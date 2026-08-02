# 床（FR-G-13 AC4 → FR-C-05）：夜晚交互 → 跳夜到次日清晨、生命回满、资源刷新、字幕 sys_sleep。
# 跳夜本身由 GameManager.sleep_until_morning() 结算（SPEC-03 §2.2），床只负责触发与字幕。
extends "res://scenes/gameplay/facility_base.gd"

# ==== 常量区 ====

const TIP_SLEEP: String = "sys_sleep"

# ==== 逻辑区 ====

# 睡觉是跳夜（FR-C-05 AC1「夜晚在床上交互后」）：白天不弹出提示气泡。
func can_interact() -> bool:
	var gm: Node = _game_manager()
	if gm == null:
		return false
	return bool(gm.is_night())


func interact(_player: Node) -> void:
	var gm: Node = _game_manager()
	if gm == null:
		push_warning("[facility] GameManager 不可用，睡觉未生效")
		return
	# 防御非法调用：交互系统外的误触不改变昼夜状态。
	if not bool(gm.is_night()):
		return
	gm.sleep_until_morning()
	_show_tip(TIP_SLEEP)
