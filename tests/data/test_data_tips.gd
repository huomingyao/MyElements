# UT-D03 / FR-D-03：tips.json id 唯一、style 枚举、文案非空、SPEC-05 §3 列出的每个 id 都存在。
# 断言依据：SPEC-04 §4 校验规则 + SPEC-05 §3 内容表（51 条）。
extends GutTest

const Fixture: GDScript = preload("res://tests/data/json_fixture.gd")

const EXPECTED_COUNT: int = 51
const STYLES: Array[String] = ["bubble", "banner", "warning"]
const STYLE_DURATIONS: Dictionary = {"bubble": 3.0, "banner": 4.0, "warning": 5.0}

# SPEC-05 §3.1 区域横幅（style: banner, once: true）
const SPEC_ZONE_TIPS: Dictionary = {
	"zone_grass": "空气的成分：氮气约 78%，氧气约 21%",
	"zone_salt": "盐湖的湖水又苦又涩——这是硬水，含较多钙、镁离子",
	"zone_mine": "矿洞氧气稀薄——氧气只占空气的 21%，注意你的氧气值",
	"zone_river": "天然水含杂质，需净化后才能用于实验",
	"zone_camp": "营地：合成、进食、睡觉——炼金术士的家",
	"zone_academy": "导师学院：不懂就问，这里没有笨问题",
	"zone_photosynthesis": "植物的光合作用：吸收 CO₂，释放 O₂",
}

# SPEC-05 §3.2 机制提示（style: banner）
const SPEC_SYS_TIPS: Dictionary = {
	"sys_oxygen_low": "氧气不足！回到开阔地带，或制取氧气",
	"sys_oxygen_tutorial": "氧气在消耗——回到开阔地带，或制取氧气",
	"sys_mine_breath": "氧气不足时呼吸加快——这就是矿洞要通风的原因",
	"sys_energy_food": "六大营养素：糖类、蛋白质、油脂、维生素、无机盐、水",
	"sys_torch_off_water": "水下点不着火把——燃烧需要氧气（燃烧三条件之一）",
	"sys_wet_wood": "湿木头点不着——温度要达到着火点（燃烧三条件之二）",
	"sys_no_fuel": "没有燃料一切免谈——燃烧三条件之三：可燃物",
	"sys_filter": "净水四步：沉淀 → 过滤 → 吸附 → 蒸馏",
	"sys_electrolysis": "电解水：正氧负氢，体积比 1:2",
	"sys_purity_ok": "\"噗\"的一声轻响——氢气纯净，可以安全点燃了",
	"sys_carbon": "活性炭疏松多孔，把 CO 牢牢吸附——吸附是物理变化",
	"sys_spray": "中和喷雾：酸+碱→盐+水——酸碱中和反应",
	"sys_sleep": "睡一觉，生命回满——新的一天，矿脉也刷新了",
	"sys_hardwater": "硬水遇肥皂水不起沫——用肥皂水可以区分硬水和软水",
	"sys_purify": "粗盐提纯三步：溶解 → 过滤 → 蒸发，泥沙留在滤纸上",
	"sys_craft_hint": "把材料放进来，试试化学反应",
	"sys_trade_prompt": "原住民：把不用的装备卖给我吧——按数字键选一件",
	"sys_trade_done": "原住民收下了装备，塞给你一份干粮——能量 +20",
	"sys_trade_empty": "原住民摆摆手：这件我不要——他只收人造的装备",
	"tip_mass_conservation": "反应前后原子种类和数目不变——质量守恒定律",
}

# SPEC-05 §3.3 警示（style: warning，5 秒）
const SPEC_WARN_TIPS: Dictionary = {
	"sys_explosion_warn": "氢气不纯点燃会发生爆炸！点燃前必须验纯——去导师学院问问为什么",
	"sys_death": "你倒下了……化学不等人。回营地床铺醒来吧",
	"warn_co": "一氧化碳 CO——无色无味的剧毒气体，煤气中毒的元凶！",
	"warn_acid": "酸雾来袭！酸性物质有腐蚀性——快用中和喷雾",
	"warn_night": "天黑了。硫火把是你最好的朋友",
	"warn_cuso4": "蓝色溶液：硫酸铜，重金属盐有毒——别泡在里面",
}

# SPEC-05 §3.4 合成卡片固定行
const SPEC_CARD_TIPS: Dictionary = {
	"card_footer": "反应前后原子种类和数目不变——质量守恒定律",
}

# SPEC-05 §3.5 物质首次拾取字幕（style: bubble, once: true），文案取 §1 表格最后一列
const SPEC_PICKUP_TIPS: Dictionary = {
	"tip_o2": "氧气 O₂——空气中的氧气约占 21%，动植物呼吸都需要它",
	"tip_h2": "氢气 H₂——最轻的气体，最清洁的燃料，但点燃前必须验纯！",
	"tip_c": "碳 C——木头燃烧剩下的木炭，主要成分就是碳",
	"tip_s": "硫 S——淡黄色粉末，易燃，燃烧时有刺激性气味",
	"tip_co": "一氧化碳 CO——无色无味的剧毒气体，煤气中毒的元凶！",
	"tip_co2": "二氧化碳 CO₂——不燃烧也不支持燃烧，能使澄清石灰水变浑浊",
	"tip_h2o": "天然水含杂质——需净化后才能用于实验",
	"tip_h2o_clean": "蒸馏水是纯净物——沉淀→过滤→吸附→蒸馏，净化四步",
	"tip_caco3": "碳酸钙 CaCO₃——石灰石、大理石的主要成分",
	"tip_fe2o3": "氧化铁 Fe₂O₃——赤铁矿的主要成分，炼铁的原料",
	"tip_cuso4": "硫酸铜 CuSO₄——蓝色溶液，重金属盐有毒，别碰！",
	"tip_hcl": "盐酸 HCl——有腐蚀性，但也是除锈和制 CO₂ 的好帮手",
	"tip_naoh": "氢氧化钠 NaOH——俗称烧碱、火碱、苛性钠，强腐蚀性",
	"tip_caoh2": "氢氧化钙 Ca(OH)₂——熟石灰，其水溶液就是澄清石灰水",
	"tip_fe": "铁 Fe——最常见的金属，生锈需要氧气和水同时存在",
	"tip_crude_salt": "粗盐——主要成分是氯化钠，但混有泥沙等杂质，需提纯后才能用",
	"tip_nacl": "氯化钠 NaCl——由钠离子和氯离子构成，厨房里的食盐就是它",
}

var _rows: Array[Dictionary] = []
var _by_id: Dictionary = {}


func before_each() -> void:
	_rows = Fixture.rows_of("tips.json")
	_by_id = {}
	for row in _rows:
		_by_id[str(row.get("id", ""))] = row


# SPEC-05 §3 结语：7（区域）+ 20（机制，含 sys_oxygen_tutorial）+ 6（警示）+ 1（卡片底行）+ 17（物质）= 51 条。
func test_tip_count_is_fifty_one() -> void:
	assert_eq(_rows.size(), EXPECTED_COUNT, "tips.json 必须恰好 51 条（SPEC-05 §3 合计）")


# SPEC-05 §3.2 补记：sys_oxygen_tutorial 为 once 横幅（FR-U-02 AC2，氧气 70 首次教程）。
func test_sys_oxygen_tutorial_is_once_banner() -> void:
	assert_true(_by_id.has("sys_oxygen_tutorial"), "SPEC-05 §3.2 的字幕缺失：sys_oxygen_tutorial")
	var row: Dictionary = _by_id.get("sys_oxygen_tutorial", {})
	assert_eq(str(row.get("style", "")), "banner", "sys_oxygen_tutorial 的 style 应为 banner")
	assert_eq(row.get("once", false), true, "sys_oxygen_tutorial 的 once 应为 true")


# AC1：id 唯一。
func test_tip_ids_unique() -> void:
	var seen: Dictionary = {}
	for row in _rows:
		var id: String = str(row.get("id", ""))
		assert_false(id.is_empty(), "存在 id 为空的字幕条目")
		assert_false(seen.has(id), "重复 tip id：%s" % id)
		seen[id] = true


# AC1：style 仅取 bubble/banner/warning。
func test_tip_styles_in_enum() -> void:
	for row in _rows:
		var style: String = str(row.get("style", ""))
		assert_true(STYLES.has(style), "%s 的 style 非法：%s" % [str(row.get("id", "")), style])


# AC3：无空文案。
func test_tip_texts_non_empty() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		assert_true(row.has("text"), "%s 缺 text 字段" % id)
		assert_false(str(row.get("text", "")).is_empty(), "%s 的 text 为空" % id)


# AC2：SPEC-05 §3.1 区域横幅 7 条存在，文案逐字一致，且 style=banner、once=true。
func test_zone_banners_present_verbatim_and_once() -> void:
	for id in SPEC_ZONE_TIPS:
		assert_true(_by_id.has(id), "SPEC-05 §3.1 的字幕缺失：%s" % id)
		var row: Dictionary = _by_id.get(id, {})
		assert_eq(str(row.get("text", "")), str(SPEC_ZONE_TIPS[id]), "%s 文案与 SPEC-05 §3.1 不一致" % id)
		assert_eq(str(row.get("style", "")), "banner", "%s 的 style 应为 banner" % id)
		assert_eq(row.get("once", false), true, "%s 的 once 应为 true" % id)


# AC2：SPEC-05 §3.2 机制提示 16 条存在，文案逐字一致，style=banner。
func test_system_banners_present_verbatim() -> void:
	for id in SPEC_SYS_TIPS:
		assert_true(_by_id.has(id), "SPEC-05 §3.2 的字幕缺失：%s" % id)
		var row: Dictionary = _by_id.get(id, {})
		assert_eq(str(row.get("text", "")), str(SPEC_SYS_TIPS[id]), "%s 文案与 SPEC-05 §3.2 不一致" % id)
		assert_eq(str(row.get("style", "")), "banner", "%s 的 style 应为 banner" % id)


# AC2：SPEC-05 §3.3 警示 6 条存在，style=warning、duration=5。
func test_warnings_present_verbatim_with_five_second_duration() -> void:
	for id in SPEC_WARN_TIPS:
		assert_true(_by_id.has(id), "SPEC-05 §3.3 的字幕缺失：%s" % id)
		var row: Dictionary = _by_id.get(id, {})
		assert_eq(str(row.get("text", "")), str(SPEC_WARN_TIPS[id]), "%s 文案与 SPEC-05 §3.3 不一致" % id)
		assert_eq(str(row.get("style", "")), "warning", "%s 的 style 应为 warning" % id)
		assert_almost_eq(
			float(row.get("duration", 0.0)), float(STYLE_DURATIONS["warning"]), 0.001,
			"%s 的 duration 应为 5 秒" % id
		)


# AC2：SPEC-05 §3.4 卡片底行存在。
func test_card_footer_present_verbatim() -> void:
	for id in SPEC_CARD_TIPS:
		assert_true(_by_id.has(id), "SPEC-05 §3.4 的字幕缺失：%s" % id)
		assert_eq(
			str(_by_id.get(id, {}).get("text", "")), str(SPEC_CARD_TIPS[id]),
			"%s 文案与 SPEC-05 §3.4 不一致" % id
		)


# AC2：SPEC-05 §3.5 物质首次拾取 17 条存在，文案取自 §1 表格末列，style=bubble、once=true。
func test_pickup_bubbles_present_verbatim_and_once() -> void:
	assert_eq(SPEC_PICKUP_TIPS.size(), 17, "SPEC-05 §3.5 应覆盖 17 种物质")
	for id in SPEC_PICKUP_TIPS:
		assert_true(_by_id.has(id), "SPEC-05 §3.5 的字幕缺失：%s" % id)
		var row: Dictionary = _by_id.get(id, {})
		assert_eq(str(row.get("text", "")), str(SPEC_PICKUP_TIPS[id]), "%s 文案与 SPEC-05 §1 末列不一致" % id)
		assert_eq(str(row.get("style", "")), "bubble", "%s 的 style 应为 bubble" % id)
		assert_eq(row.get("once", false), true, "%s 的 once 应为 true" % id)


# duration 若填写必须与 style 默认时长一致（3/4/5），避免调参时出现意外值。
func test_durations_match_style_defaults() -> void:
	for row in _rows:
		if not row.has("duration"):
			continue
		var style: String = str(row.get("style", ""))
		if not STYLE_DURATIONS.has(style):
			continue
		assert_almost_eq(
			float(row.get("duration", 0.0)), float(STYLE_DURATIONS[style]), 0.001,
			"%s 的 duration 与 style %s 的默认时长不符" % [str(row.get("id", "")), style]
		)


# 文案里的化学式用 Unicode 下标，不许 LaTeX。
func test_texts_use_unicode_subscripts_not_latex() -> void:
	for row in _rows:
		var id: String = str(row.get("id", ""))
		var text: String = str(row.get("text", ""))
		assert_false(text.contains("\\"), "%s 的 text 含 LaTeX 反斜杠" % id)
		assert_false(text.contains("$"), "%s 的 text 含 LaTeX 数学符号" % id)
