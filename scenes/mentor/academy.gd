# 导师学院场景（FR-M-01）：一座建筑四个房间，按 mentors.json 的 room 字段
# 把四位导师小人摆进对应房间（数据驱动，改表不改码——铁律 4）。
# 区域触发器把 GameManager 切到 academy（氧气净速率 0，FR-M-01 AC2）；
# 导师的 ask_requested 信号在这里接到聊天框（跨节点通信走信号，SPEC-03 §1）。
extends Node2D

# ==== 常量区 ====
const NpcScene: PackedScene = preload("res://scenes/mentor/mentor_npc.tscn")
const RegistryScript: GDScript = preload("res://scenes/mentor/mentor_registry.gd")

const ZONE_ID: String = "academy"
const ROOM_META: String = "room"
const ANCHOR_NAME: String = "Anchor"
const GAME_MANAGER_PATH: NodePath = ^"/root/GameManager"

# ==== 状态区 ====
@onready var _rooms: Node2D = %Rooms
@onready var _chat: Control = %ChatPanel
@onready var _zone: Area2D = %ZoneTrigger


# ==== 逻辑区 ====
func _ready() -> void:
	_spawn_mentors()
	_zone.body_entered.connect(_on_zone_body_entered)


# 每位导师一个 MentorNPC，挂在 room 字段匹配的房间节点下、Anchor 位置。
func _spawn_mentors() -> void:
	var registry: RefCounted = RegistryScript.new()
	for id_value in registry.mentor_ids():
		var mentor_id: String = str(id_value)
		var row: Dictionary = registry.record(mentor_id)
		var room_node: Node = _room_node_for(str(row.get("room", "")))
		if room_node == null:
			push_warning("[academy] 数据表中的房间在场景里不存在，导师未摆放：%s" % mentor_id)
			continue
		var npc: Area2D = NpcScene.instantiate()
		room_node.add_child(npc)
		var anchor: Node = room_node.get_node_or_null(ANCHOR_NAME)
		if anchor is Node2D:
			(npc as Node2D).position = (anchor as Node2D).position
		npc.setup(row)
		npc.ask_requested.connect(_on_mentor_asked)


func _room_node_for(room_name: String) -> Node:
	for child in _rooms.get_children():
		if child.has_meta(ROOM_META) and str(child.get_meta(ROOM_META)) == room_name:
			return child
	return null


func _on_zone_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D):
		return
	var gm: Node = get_node_or_null(GAME_MANAGER_PATH)
	if gm != null:
		gm.set_zone(ZONE_ID)


func _on_mentor_asked(mentor_id: String) -> void:
	_chat.open_chat(mentor_id)
