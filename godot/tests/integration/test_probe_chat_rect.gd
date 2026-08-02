# 临时探针：数值化复现「打包后对话栏跑到顶部」——打印聊天框实际矩形。
extends GutTest

func test_probe_chat_panel_rect() -> void:
	var room: Node = (load("res://scenes/mentor/mentor_room.tscn") as PackedScene).instantiate()
	add_child_autofree(room)
	await wait_process_frames(3)
	var chat: Control = room.get_node_or_null(^"%ChatPanel") as Control
	assert_not_null(chat, "应有 %ChatPanel")
	if chat == null:
		return
	chat.open_chat("monitor")
	await wait_process_frames(3)
	var viewport_size: Vector2 = chat.get_viewport_rect().size
	print("PROBE viewport=", viewport_size)
	print("PROBE chat visible=", chat.visible)
	print("PROBE chat anchor_top=", chat.anchor_top, " anchor_bottom=", chat.anchor_bottom)
	print("PROBE chat offset_top=", chat.offset_top, " offset_bottom=", chat.offset_bottom)
	print("PROBE chat global_rect=", chat.get_global_rect())
	print("PROBE room rect=", (room as Control).get_global_rect(), " room visible=", (room as Control).visible)
	var parent: Node = chat.get_parent()
	print("PROBE chat parent=", parent.name, " type=", parent.get_class())
