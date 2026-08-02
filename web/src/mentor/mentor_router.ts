// MentorRouter：班主任统一调度（§3.6.1）。纯逻辑类，不依赖 Phaser。
import type { Row } from '../core/data_loader';
import { llmClient } from '../core/llm_client';
import type { HistoryTurn } from '../core/llm_client';
import { gameManager } from '../core/game_manager';
import { qaFallback } from './qa_fallback';
import { PromptSuffix } from './prompt_suffix';
import { sanitizeInput } from './input_sanitize';

export interface ChatMessage {
  mentor_id: string;
  text: string;
  offline: boolean;
}

export type ReplyProvider = (mentorId: string, question: string) => string | { text: string; offline: boolean };

export class MentorRouter {
  private mentors: Row[] = [];
  private dispatch: Row[] = [];
  private provider: ReplyProvider | null = null;
  private dispatchCounter = 0;

  loadFrom(rows: Row[]): void {
    this.mentors = rows || [];
    const monitor = this.mentors.find(m => m.id === 'monitor');
    this.dispatch = (monitor?.dispatch as Row[]) || [];
  }

  setReplyProvider(p: ReplyProvider): void {
    this.provider = p;
  }

  classify(question: string): 'combat' | 'learning' | 'chemistry' | 'other' {
    for (const d of this.dispatch) {
      const kws = (d.keywords as string[]) || [];
      for (const k of kws) {
        if (k && question.includes(k)) return d.category as 'combat' | 'learning' | 'chemistry' | 'other';
      }
    }
    return 'other';
  }

  routeTargets(category: string): string[] {
    const d = this.dispatch.find(d => d.category === category);
    return d ? [...(d.targets as string[])] : ['assistant'];
  }

  private mentionMap(): Map<string, string> {
    // @句柄 -> 导师 id，长句柄优先
    const map = new Map<string, string>();
    for (const m of this.mentors) {
      const mention = String(m.mention ?? '');
      if (mention) map.set(mention, String(m.id));
    }
    return new Map([...map.entries()].sort((a, b) => b[0].length - a[0].length));
  }

  parseMentions(text: string): string[] {
    const map = this.mentionMap();
    const found: string[] = [];
    let rest = text;
    while (rest.includes('@')) {
      const at = rest.indexOf('@');
      const after = rest.slice(at + 1);
      let matched = false;
      for (const [handle, id] of map) {
        if (after.startsWith(handle)) {
          if (!found.includes(id)) found.push(id);
          rest = after.slice(handle.length);
          matched = true;
          break;
        }
      }
      if (!matched) rest = after;
    }
    return found;
  }

  handleMessage(question: string): ChatMessage[] {
    const clean = sanitizeInput(question);
    this.dispatchCounter = 0;
    if (!clean) return [];
    const category = this.classify(clean);
    const targets = this.routeTargets(category).slice(0, 2);

    // 第一条：班主任首接（离线调度语整句取自 dispatch.line；联网经 LLM）
    const monitorMsg = this.replyFor('monitor', clean, category);
    const messages: ChatMessage[] = [monitorMsg];
    this.dispatchCounter += 1;

    // 只解析班主任回复中的 @（硬约束）；若解析不到则用分类器 targets
    let dispatched = this.parseMentions(monitorMsg.text).filter(id => id !== 'monitor');
    if (dispatched.length === 0) dispatched = targets;
    dispatched = dispatched.slice(0, 2);

    for (const id of dispatched) {
      if (messages.length >= 3) break; // 总数硬上限 3
      messages.push(this.replyFor(id, clean, category));
    }
    return messages;
  }

  private replyFor(mentorId: string, question: string, category: string): ChatMessage {
    if (this.provider) {
      const out = this.provider(mentorId, question);
      const text = typeof out === 'string' ? out : out.text;
      const offline = typeof out === 'string' ? out === '' : out.offline;
      if (text) return { mentor_id: mentorId, text, offline };
      // 空串视为走离线兜底
      return this.offlineReply(mentorId, question, category);
    }
    // 未注入 provider：同步路径走离线（异步 LLM 由聊天面板直接调 llmClient.ask）
    return this.offlineReply(mentorId, question, category);
  }

  private offlineReply(mentorId: string, question: string, category: string): ChatMessage {
    if (mentorId === 'monitor') {
      const d = this.dispatch.find(d => d.category === category);
      const line = d ? String(d.line ?? '') : '';
      const badge = llmClient.isOffline() ? this.badge() : '';
      return { mentor_id: 'monitor', text: line + badge, offline: llmClient.isOffline() };
    }
    const answer = qaFallback.answer(question);
    const badge = this.badge();
    return { mentor_id: mentorId, text: (answer || '') + badge, offline: true };
  }

  private badge(): string {
    // 离线角标（ui_strings.chat_offline_badge）
    return gameManager.getUiString('chat_offline_badge');
  }

  dispatchCount(): number {
    return this.dispatchCounter;
  }

  systemPromptFor(mentorId: string): string {
    const m = this.mentors.find(m => m.id === mentorId);
    if (!m) return '';
    return PromptSuffix.appendTo(String(m.system_prompt ?? ''));
  }

  mentorById(id: string): Row {
    return this.mentors.find(m => m.id === id) ?? {};
  }

  allMentors(): Row[] {
    return this.mentors;
  }

  async askAsync(mentorId: string, question: string, history: HistoryTurn[]): Promise<string> {
    return llmClient.ask(mentorId, question, history);
  }
}

export const mentorRouter = new MentorRouter();
