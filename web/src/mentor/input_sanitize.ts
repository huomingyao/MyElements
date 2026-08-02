// 输入清理（FR-M-03）：截断 200 字符 + 清理控制字符与换行；只作为文本渲染
import { gameManager } from '../core/game_manager';

export function sanitizeInput(raw: string, maxChars?: number): string {
  const limit = maxChars ?? Number(gameManager.getBalance('llm.input_max_chars', 200));
  let s = String(raw ?? '');
  // 去掉控制字符（\x00-\x1F，含换行），压平连续空白
  s = s.replace(/[\x00-\x1F]/g, ' ');
  s = s.replace(/\s+/g, ' ').trim();
  if (s.length > limit) s = s.slice(0, limit);
  return s;
}
