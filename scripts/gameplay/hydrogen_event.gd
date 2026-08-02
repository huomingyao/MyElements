# HydrogenEvent（FR-G-08 / FR-G-09，IT-G08 / IT-G09）：氢气验纯爆炸事件。
# 纯逻辑 RefCounted，不进场景树、可直接实例化（SPEC-06 §3 可测性约束）。
# 状态机见 SPEC-02 §4.5；表现层（爆炸动画/震屏/音效）监听本类信号，见 scenes/gameplay/explosion.gd。
# 伤害数值走 balance.json，字幕走 tips.json，标记走 GameManager——逻辑区无中文文案、无裸数值（NFR-04）。
extends RefCounted

# 爆炸表现挂载点：屏幕震动 + 火光 + 音效（scenes/gameplay/explosion.gd 的 play()）。
signal explosion_triggered()
# 验纯"噗"轻响挂载点（音效层）。
signal purity_check_performed()

# ==== 常量区 ====

# R4 氢气点燃配方（SPEC-05 §2）；器材/条件从配方记录读，不写死。
const RECIPE_ID: String = "r_hydrogen_burn"

const BAL_EXPLOSION_DAMAGE: String = "damage.hydrogen_explosion"
# 演示保险开关（FR-G-09 AC4）：不问导师强制解锁验纯步骤。
const BAL_FORCE_PURITY_UNLOCK: String = "debug.force_purity_unlock"

# 数据表缺失时的兜底默认值（SPEC-01 §10 NFR-04 判定口径允许的「数据表缺失」兜底）。
const FALLBACK_EXPLOSION_DAMAGE: float = 50.0

const TIP_EXPLOSION_WARN: String = "sys_explosion_warn"
const TIP_PURITY_OK: String = "sys_purity_ok"

const FLAG_EXPLOSION: String = "explosion_happened"
const FLAG_PURITY: String = "purity_check_unlocked"

# SPEC-03 §4 规则 3 的 fail_reason 值（契约字符串，非文案）。
const REASON_NEEDS_PURITY: String = "needs_purity_check"

# 氢气提问判定的关键词来源（qa_fallback.json 行 id；关键词本身是数据表内容）。
const QA_TABLE: String = "qa_fallback.json"
const QA_HYDROGEN_ROW_ID: String = "qa_h2_explosion"

# ==== 逻辑区 ====

# 点燃入口（FR-G-08）：材料来自合成界面。未验纯命中 R4 时触发爆炸事件；
# 返回 RecipeDB.try_craft 的契约字典，由合成台按此结算产物/卡片。
func ignite(items: Array) -> Dictionary:
	var db: Node = _recipe_db()
	if db == null:
		push_warning("[h2] RecipeDB 缺失，点燃请求被忽略")
		return {}
	var recipe: Dictionary = db.get_recipe(RECIPE_ID)
	if recipe.is_empty():
		push_warning("[h2] 配方缺失：%s（点燃请求被忽略）" % RECIPE_ID)
		return {}
	var result: Dictionary = db.try_craft(
		items, str(recipe.get("tool", "")), str(recipe.get("condition", ""))
	)
	if str(result.get("fail_reason", "")) == REASON_NEEDS_PURITY:
		_explode()
	return result


# 「验纯」步骤是否出现（FR-G-09 AC1/AC4）：导师解锁标记或演示保险开关，任一即可。
func is_purity_check_available() -> bool:
	var gm: Node = _game_manager()
	if gm == null:
		return false
	if bool(gm.get_balance(BAL_FORCE_PURITY_UNLOCK, false)):
		return true
	return bool(gm.get_flag(FLAG_PURITY))


# 执行验纯（FR-G-09 AC2）：字幕 sys_purity_ok + purity_check_performed 信号（噗声音效）。
# 验纯完成置解锁标记，之后点燃成功（AC3）；未解锁时拒绝执行。
func do_purity_check() -> bool:
	if not is_purity_check_available():
		return false
	var tip: Node = _knowledge_tip()
	if tip != null:
		tip.show(TIP_PURITY_OK)
	var gm: Node = _game_manager()
	if gm != null:
		gm.set_flag(FLAG_PURITY, true)
	purity_check_performed.emit()
	return true


# 导师模块回调入口（SPEC-02 §4.5）：问过氢气/爆炸/验纯相关问题后解锁验纯步骤。
func unlock_purity_check() -> void:
	var gm: Node = _game_manager()
	if gm == null:
		push_warning("[h2] GameManager 缺失，验纯解锁被忽略")
		return
	gm.set_flag(FLAG_PURITY, true)


# 问题是否涉及氢气爆炸（FR-G-09 AC1 的触发判定）。
# 关键词读 qa_fallback.json 的 qa_h2_explosion 行——内容归数据表，代码零中文关键词（NFR-04）。
func question_mentions_hydrogen(question: String) -> bool:
	if question.is_empty():
		return false
	for keyword: Variant in _hydrogen_keywords():
		var word: String = str(keyword)
		if not word.is_empty() and question.contains(word):
			return true
	return false


func _hydrogen_keywords() -> Array:
	var rows: Array = DataLoader.load_table(QA_TABLE, TYPE_ARRAY, [])
	for row: Variant in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str((row as Dictionary).get("id", "")) == QA_HYDROGEN_ROW_ID:
			return (row as Dictionary).get("keywords", [])
	push_warning("[h2] qa_fallback.json 缺 %s 行（氢气提问判定恒否）" % QA_HYDROGEN_ROW_ID)
	return []


# 爆炸（FR-G-08 AC2/AC3）：伤害走 balance，字幕走 tips，标记走 GameManager。
# 生命不足时由 GameManager.modify_health 归零走 FR-C-06 死亡流程（AC4），本方法不阻塞、不卡死。
func _explode() -> void:
	var gm: Node = _game_manager()
	if gm == null:
		push_warning("[h2] GameManager 缺失，爆炸结算被跳过")
		return
	var damage: float = float(gm.get_balance(BAL_EXPLOSION_DAMAGE, FALLBACK_EXPLOSION_DAMAGE))
	gm.modify_health(-damage)
	var tip: Node = _knowledge_tip()
	if tip != null:
		tip.show(TIP_EXPLOSION_WARN)
	gm.set_flag(FLAG_EXPLOSION, true)
	explosion_triggered.emit()


func _autoload(node_path: NodePath) -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(node_path)


func _game_manager() -> Node:
	return _autoload(^"/root/GameManager")


func _knowledge_tip() -> Node:
	return _autoload(^"/root/KnowledgeTip")


func _recipe_db() -> Node:
	return _autoload(^"/root/RecipeDB")
