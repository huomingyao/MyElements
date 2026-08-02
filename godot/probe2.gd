# 临时探针 2：真实链路——主场景 → 导师室 → 点导师卡 → 打印聊天框矩形。
extends SceneTree

var _frames: int = 0
var _phase: int = 0

func _init() -> void:
	var scene: Node = (load("res://scenes/main/world.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(scene)

func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0 and _frames >= 10:
		_phase = 1
		var world: Node = root.get_node_or_null(^"World")
		print("PROBE2 world=", world)
		if world == null:
			for child in root.get_children():
				print("PROBE2 root child: ", child.name)
			quit()
			return true
		var manager: Node = world.get_node_or_null(^"UILayer/UIManager")
		print("PROBE2 ui_manager=", manager)
		if manager != null:
			manager.open("mentor_room")
	if _phase == 1 and _frames >= 20:
		_phase = 2
		var room: Node = root.find_child("MentorRoom", true, false)
		print("PROBE2 room=", room, " visible=", (room as Control).visible if room != null else "?")
		if room != null:
			var card: Node = room.get_node_or_null(^"%MentorRow/Mentor_monitor")
			print("PROBE2 card=", card)
			if card != null:
				card.pressed.emit()
	if _phase == 2 and _frames >= 30:
		_phase = 3
		var chat: Control = root.find_child("ChatPanel", true, false) as Control
		if chat != null:
			print("PROBE2 chat visible=", chat.visible, " rect=", chat.get_global_rect())
			print("PROBE2 chat anchor_top=", chat.anchor_top)
			var p: Node = chat.get_parent()
			print("PROBE2 chat parent=", p.name, " rect=", (p as Control).get_global_rect() if p is Control else "non-control")
		else:
			print("PROBE2 chat NOT FOUND")
		quit()
	return true
