// QaFallback：离线兜底问答（§3.6.4）。命中最多者胜，平票取先，零命中取兜底行。
import type { Row } from '../core/data_loader';

export class QaFallback {
  private rows: Row[] = [];

  loadFrom(rows: Row[]): void {
    this.rows = rows || [];
  }

  matchScore(question: string, keywords: string[]): number {
    if (!keywords || keywords.length === 0) return 0;
    let score = 0;
    for (const k of keywords) {
      if (k && question.includes(k)) score += 1;
    }
    return score;
  }

  bestRow(question: string): Row | null {
    let best: Row | null = null;
    let bestScore = 0;
    for (const row of this.rows) {
      const kw = (row.keywords as string[]) || [];
      if (kw.length === 0) continue; // 兜底行不参与包含匹配
      const score = this.matchScore(question, kw);
      if (score > bestScore) {
        bestScore = score;
        best = row; // 平票不替换，取先出现者
      }
    }
    if (best) return best;
    // 零命中 -> 兜底行
    return this.rows.find(r => Array.isArray(r.keywords) && (r.keywords as string[]).length === 0) ?? null;
  }

  answer(question: string): string {
    const row = this.bestRow(question);
    return row ? String(row.answer ?? '') : '';
  }

  mentorIdFor(row: Row | null): string {
    return row ? String(row.mentor_id ?? 'chem') : 'monitor';
  }
}

export const qaFallback = new QaFallback();
