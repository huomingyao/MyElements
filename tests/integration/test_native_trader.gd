# IT-G15 / FR-G-15：原住民交易——E 进交易态、数字键卖出道具换 +20 能量、
# 已装备先卸下、空格/物质不卖不扣、再次交互或走远退出。
extends GutTest

const TRADER_SCENE: String = "res://scenes/gameplay/native_trader.tscn"
const TRADER_SCRIPT: String = "res://scenes/gameplay/native_trader.gd"
const INVENTORY_SCRIPT: String = "res://scripts/gameplay/inventory.gd"
const ITEM_EFFECTS_SCRIPT: String = "res://scripts/gameplay/item_effects.gd"

var gm: Node = null
var tip: Node = null
var _trader: Node = null


# 假玩家：背包 + 道具效果 + 火把状态（鸭子类型，同 test_facility_camp 约定）。
class FakePlayer:
	extends Node2D
	var inventory: RefCounted = null
	var item_effects: RefCounted = null
	var _torch: bool = false
	func set_torch_equipped(equipped: bool) -> void:
		_torch = equipped
	func is_torch_equipped() -> bool:
		return _torch


func before_each() -> void:
	var root: Window = Engine.get_main_loop().root
	gm = root.get_node_or_null(^"GameManager")
	tip = root.get_node_or_null(^"KnowledgeTip")
	assert_not_null(gm, "GameManager autoload 必须存在")
	assert_not_null(tip, "KnowledgeTip autoload 必须存在")
	if gm == null or tip == null:
		return
	gm.reload_config()
	gm.reset_clock()
	gm.reset_stats()
	tip.reload()
	_trader = null
	if not ResourceLoader.exists(TRADER_SCENE):
		fail_test("尚未实现 %s（FR-G-15）" % TRADER_SCENE)
		return
	_trader = (load(TRADER_SCENE) as PackedScene).instantiate()
	add_child_autofree(_trader)
	await wait_process_frames(1)


func _make_player() -> FakePlayer:
	var player := FakePlayer.new()
	player.inventory = (load(INVENTORY_SCRIPT) as GDScript).new()
	player.item_effects = (load(ITEM_EFFECTS_SCRIPT) as GDScript).new()
	add_child_autofree(player)
	return player


func _skip_unless_ready(method_names: Array = []) -> bool:
	if _trader == null:
		return true
	for name_value in method_names:
		var method_name: String = str(name_value)
		if not _trader.has_method(method_name):
			fail_test("原住民应有 %s()（FR-G-15）" % method_name)
			return true
	return false


# SPEC-03 §5：实现三方法约定，玩家控制器无需认识本类型。
func test_implements_interact_contract() -> void:
	if _skip_unless_ready():
		return
	assert_true(_trader.has_method("get_interact_prompt"), "缺 get_interact_prompt")
	assert_true(_trader.has_method("can_interact"), "缺 can_interact")
	assert_true(_trader.has_method("interact"), "缺 interact")


# AC1：按 E 进入交易状态并显示 sys_trade_prompt；再次按 E 退出。
func test_interact_toggles_trading_state() -> void:
	if _skip_unless_ready(["is_trading"]):
		return
	var player: FakePlayer = _make_player()
	assert_false(_trader.is_trading(), "初始非交易态")
	_trader.interact(player)
	assert_true(_trader.is_trading(), "按 E 应进入交易态")
	assert_true(tip.is_shown("sys_trade_prompt"), "进入交易态应显示 sys_trade_prompt")
	_trader.interact(player)
	assert_false(_trader.is_trading(), "再次按 E 应退出交易态")


# AC2：卖出快捷栏道具——道具消失、能量 +20（balance）、显示 sys_trade_done、交易态结束。
func test_sell_item_grants_energy() -> void:
	if _skip_unless_ready(["sell_slot"]):
		return
	var player: FakePlayer = _make_player()
	player.inventory.add_item("oxygen_tank", 1)
	gm.modify_energy(-50.0)
	_trader.interact(player)
	var expected: float = gm.energy + float(gm.get_balance("items.trade_energy_restore", 20.0))
	assert_true(_trader.sell_slot(0), "卖出应成功")
	assert_eq(player.inventory.count_of("oxygen_tank"), 0, "道具应从背包消失")
	assert_almost_eq(gm.energy, expected, 0.001, "能量应按 balance 增加")
	assert_true(tip.is_shown("sys_trade_done"), "成交应显示 sys_trade_done")
	assert_false(_trader.is_trading(), "成交后退出交易态")


# AC3：已装备的道具卖出前自动卸下（火把卸下后视野状态同步）。
func test_sell_equipped_item_unequips_first() -> void:
	if _skip_unless_ready(["sell_slot"]):
		return
	var player: FakePlayer = _make_player()
	player.inventory.add_item("sulfur_torch", 1)
	player.item_effects.use_item("sulfur_torch", player.inventory)
	player.set_torch_equipped(true)
	assert_true(player.item_effects.is_equipped("sulfur_torch"), "前提：火把已装备")
	_trader.interact(player)
	assert_true(_trader.sell_slot(0), "卖已装备道具应成功")
	assert_false(player.item_effects.is_equipped("sulfur_torch"), "卖出前应先卸下")
	assert_false(player.is_torch_equipped(), "玩家火把状态应同步回落")
	assert_eq(player.inventory.count_of("sulfur_torch"), 0, "道具已卖出")


# AC4：空格不给卖（不扣东西、显示 sys_trade_empty）。
func test_sell_empty_slot_fails_gracefully() -> void:
	if _skip_unless_ready(["sell_slot"]):
		return
	var player: FakePlayer = _make_player()
	_trader.interact(player)
	assert_false(_trader.sell_slot(0), "空格不应成交")
	assert_true(tip.is_shown("sys_trade_empty"), "空格应显示 sys_trade_empty")
	assert_true(_trader.is_trading(), "未成交时保持交易态")


# AC4：物质（非道具表条目）不卖——原住民只收人造装备。
func test_sell_substance_refused() -> void:
	if _skip_unless_ready(["sell_slot"]):
		return
	var player: FakePlayer = _make_player()
	player.inventory.add_item("o2", 1)
	_trader.interact(player)
	assert_false(_trader.sell_slot(0), "物质不应成交")
	assert_eq(player.inventory.count_of("o2"), 1, "物质不应被扣")
	assert_true(tip.is_shown("sys_trade_empty"), "拒绝时应显示 sys_trade_empty")


# AC5：走远（超出交互半径两倍）自动退出交易态。
func test_walking_away_cancels_trading() -> void:
	if _skip_unless_ready(["is_trading"]):
		return
	var player: FakePlayer = _make_player()
	_trader.global_position = Vector2(1000, 0)
	player.global_position = Vector2(1000, 0)
	_trader.interact(player)
	assert_true(_trader.is_trading(), "进入交易态")
	player.global_position = Vector2(1400, 0)
	await wait_physics_frames(3)
	assert_false(_trader.is_trading(), "走远应自动退出交易态")


# NFR-04：逻辑代码里不许出现中文字面量（注释与诊断日志除外）。
func test_script_has_no_hardcoded_chinese() -> void:
	if not FileAccess.file_exists(TRADER_SCRIPT):
		fail_test("尚未实现 %s（FR-G-15）" % TRADER_SCRIPT)
		return
	var text: String = FileAccess.get_file_as_string(TRADER_SCRIPT)
	for line in text.split("\n"):
		var stripped: String = str(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("push_warning") or stripped.contains("push_error") or stripped.contains("print("):
			continue
		assert_false(_has_cjk(stripped), "逻辑代码里不许硬编码中文（NFR-04）：%s" % stripped)


func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
