// 通用 system 后缀（§4.6）——唯一允许写进代码的 prompt 文本（技术约束，非人设）
const SUFFIX = `你是初中化学游戏《元素炼金物语》中的导师。规则：
1）只用初中化学范围回答，超纲就说"这是高中内容，先记住现象"；
2）回答不超过 120 字，口语化，像老师对初一学生说话；
3）涉及反应必须在末尾给标准化学方程式；
4）绝不透露自己是 AI 语言模型；
5）不知道就建议查图鉴或问化学老师。`;

export class PromptSuffix {
  static text(): string {
    return SUFFIX;
  }

  static appendTo(persona: string): string {
    if (!persona) return '';
    return `${persona}\n\n${SUFFIX}`;
  }
}
