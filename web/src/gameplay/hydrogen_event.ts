// HydrogenEvent：氢气验纯爆炸事件（§3.10）。全场核心记忆点。
import { gameManager } from '../core/game_manager';
import { knowledgeTip } from '../core/knowledge_tip';
import { eventBus } from '../core/event_bus';
import { qaFallback } from '../mentor/qa_fallback';
import type { Row } from '../core/data_loader';

export class HydrogenEvent {
  private qaRows: Row[] = [];

  loadQaKeywords(rows: Row[]): void {
    this.qaRows = rows || [];
  }

  isPurityCheckAvailable(): boolean {
    return gameManager.getFlag('purity_check_unlocked') || gameManager.bool('debug.force_purity_unlock');
  }

  unlockPurityCheck(): void {
    gameManager.setFlag('purity_check_unlocked', true);
  }

  // 玩家提问是否涉及氢气/爆炸/验纯（关键词读 qa_fallback.json 的 qa_h2_explosion 行，代码零中文关键词）
  questionMentionsHydrogen(question: string): boolean {
    const row = this.qaRows.find(r => r.id === 'qa_h2_explosion');
    if (!row) return false;
    const kws = (row.keywords as string[]) || [];
    return kws.some(k => k && question.includes(k));
  }

  // 未验纯直接点燃：爆炸动画由表现层监听 explosion_triggered；这里结算伤害与标记。
  ignite(): { exploded: boolean; damage: number } {
    const damage = Number(gameManager.getBalance('damage.hydrogen_explosion', 50));
    gameManager.modifyHealth(-damage);
    gameManager.setFlag('explosion_happened', true);
    eventBus.emit('explosion_triggered', {});
    knowledgeTip.show('sys_explosion_warn');
    return { exploded: true, damage };
  }

  doPurityCheck(): boolean {
    if (!this.isPurityCheckAvailable()) return false;
    eventBus.emit('purity_check_performed', {});
    knowledgeTip.show('sys_purity_ok');
    return true;
  }
}

export const hydrogenEvent = new HydrogenEvent();
