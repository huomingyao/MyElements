# 通用 system 后缀（SPEC-04 §6）。
# 这是**唯一**允许写在代码里的 prompt 文本——它对全部导师一致且属技术约束，
# 不是人设内容（人设一律在 mentors.json，见 FR-M-06 AC1）。改这里必须同步改 SPEC-04 §6。
# 纯逻辑 RefCounted，可直接实例化（SPEC-06 §3 可测性约束）。
extends RefCounted

# ==== 常量区 ====
const SUFFIX: String = """你是初中化学游戏《元素炼金物语》中的导师。规则：
1）只用初中化学范围回答，超纲就说"这是高中内容，先记住现象"；
2）回答不超过 120 字，口语化，像老师对初一学生说话；
3）涉及反应必须在末尾给标准化学方程式；
4）绝不透露自己是 AI 语言模型；
5）不知道就建议查图鉴或问化学老师。"""

# 人设段与后缀之间的分隔（保证拼接后人设段原样在前，SPEC-04 §6 / FR-M-06 AC3）。
const JOINER: String = "\n"


# ==== 逻辑区 ====
func text() -> String:
	return SUFFIX


# 人设段 + 后缀。人设段为空时返回空串——不许把后缀单独喂给 LLM。
func append_to(persona: String) -> String:
	if persona.strip_edges().is_empty():
		return ""
	return persona + JOINER + SUFFIX
