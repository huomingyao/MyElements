// 聊天框：底部弹出，世界不停。班主任统一调度（联网走 LLM，离线走本地兜底）
import { uiManager } from './ui_manager';
import { gameManager } from '../core/game_manager';
import { llmClient } from '../core/llm_client';
import type { HistoryTurn } from '../core/llm_client';
import { mentorRouter } from '../mentor/mentor_router';
import type { ChatMessage } from '../mentor/mentor_router';
import { hydrogenEvent } from '../gameplay/hydrogen_event';
import { sanitizeInput } from '../mentor/input_sanitize';
import { sfx } from '../audio/sfx';
import { saveStore } from '../save/save_store';

const DEFAULT_TYPING_SPEED = 40; // 字/秒（§3.11 锚定常量）

function el(tag: string, className = '', text = ''): HTMLElement {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text) e.textContent = text;
  return e;
}

export class ChatPanel {
  private dom: HTMLElement | null = null;
  private logEl!: HTMLElement;
  private inputEl!: HTMLInputElement;
  private portraitEl!: HTMLImageElement;
  private nameEl!: HTMLElement;
  private badgeEl!: HTMLElement;
  private currentMentor = 'monitor';
  private histories: Record<string, HistoryTurn[]> = { monitor: [], chem: [], assistant: [], think: [] };
  private busy = false;
  typingSpeed = DEFAULT_TYPING_SPEED;

  isOpen(): boolean { return !!this.dom; }

  open(mentorId = 'monitor'): void {
    if (this.dom) {
      this.setMentor(mentorId);
      return;
    }
    const gm = gameManager;
    const wrap = el('div', 'panel');
    wrap.id = 'chat-panel';

    this.portraitEl = document.createElement('img');
    this.portraitEl.id = 'chat-portrait';
    wrap.appendChild(this.portraitEl);

    const main = el('div');
    main.id = 'chat-main';
    this.nameEl = el('div', '', '');
    this.nameEl.id = 'chat-name';
    main.appendChild(this.nameEl);
    this.logEl = el('div');
    this.logEl.id = 'chat-log';
    main.appendChild(this.logEl);

    const inputRow = el('div');
    inputRow.id = 'chat-input-row';
    this.inputEl = document.createElement('input');
    this.inputEl.id = 'chat-input';
    this.inputEl.placeholder = gm.getUiString('chat_placeholder');
    this.inputEl.maxLength = 200;
    this.inputEl.onkeydown = (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') this.send();
      if (e.key === 'Escape') this.inputEl.blur();
    };
    const sendBtn = el('button', 'btn small', gm.getUiString('chat_send')) as HTMLButtonElement;
    sendBtn.onclick = () => this.send();
    inputRow.appendChild(this.inputEl);
    inputRow.appendChild(sendBtn);
    main.appendChild(inputRow);
    wrap.appendChild(main);

    const side = el('div');
    side.id = 'chat-side';
    const configBtn = el('button', 'btn small', gm.getUiString('chat_config')) as HTMLButtonElement;
    configBtn.onclick = () => uiManager.openPanel('config');
    const closeBtn = el('button', 'btn small', gm.getUiString('chat_close')) as HTMLButtonElement;
    closeBtn.onclick = () => uiManager.closePanel();
    this.badgeEl = el('div', '', '');
    this.badgeEl.id = 'chat-offline-badge';
    side.appendChild(configBtn);
    side.appendChild(closeBtn);
    side.appendChild(this.badgeEl);
    wrap.appendChild(side);

    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;
    this.setMentor(mentorId);
    this.updateBadge();
    window.setTimeout(() => this.inputEl.focus(), 50);
  }

  private setMentor(mentorId: string): void {
    const m = mentorRouter.mentorById(mentorId);
    if (!m.id) return;
    this.currentMentor = mentorId;
    this.portraitEl.src = String(m.avatar_idle);
    this.nameEl.textContent = `${m.name} · ${m.title} · ${m.room}`;
  }

  private updateBadge(): void {
    this.badgeEl.textContent = llmClient.isOffline() ? gameManager.getUiString('chat_offline_badge') : '';
  }

  private appendMsg(who: string, text: string, isPlayer = false): HTMLElement {
    const msg = el('div', `msg${isPlayer ? ' player' : ''}`);
    msg.appendChild(el('span', 'who', `${who}：`));
    const body = el('span', '', text);
    msg.appendChild(body);
    this.logEl.appendChild(msg);
    this.logEl.scrollTop = this.logEl.scrollHeight;
    return body;
  }

  // 逐字打字显示；打字期间立绘 talk 态（轻微缩放脉动）
  private async typewrite(target: HTMLElement, text: string): Promise<void> {
    this.portraitEl.style.transform = 'scale(1.04)';
    const interval = 1000 / this.typingSpeed;
    for (let i = 0; i < text.length; i++) {
      target.textContent += text[i];
      if (i % 3 === 0) {
        this.logEl.scrollTop = this.logEl.scrollHeight;
        sfx.type();
      }
      await new Promise(r => setTimeout(r, interval));
    }
    this.logEl.scrollTop = this.logEl.scrollHeight;
    this.portraitEl.style.transform = '';
  }

  private mentorName(id: string): string {
    const m = mentorRouter.mentorById(id);
    return m.name ? `${m.name}（${m.title}）` : id;
  }

  private async send(): Promise<void> {
    if (this.busy) return;
    const raw = this.inputEl.value;
    const question = sanitizeInput(raw);
    if (!question) return; // 空输入不发起请求
    this.inputEl.value = '';
    this.appendMsg('你', question, true);
    this.busy = true;
    try {
      const online = !llmClient.isOffline();
      if (online) {
        await this.onlineRound(question);
      } else {
        await this.offlineRound(question);
      }
      // 问过氢气爆炸相关问题 → 解锁验纯（FR-G-09 AC1）
      if (hydrogenEvent.questionMentionsHydrogen(question)) {
        hydrogenEvent.unlockPurityCheck();
      }
      saveStore.save();
    } catch (e) {
      console.error('ChatPanel: 问答异常', e);
    } finally {
      this.busy = false;
      this.updateBadge();
    }
  }

  // 联网：班主任首接（LLM）→ 解析 @ → 被派导师回答（LLM）
  private async onlineRound(question: string): Promise<void> {
    const monitorHistory = this.histories.monitor;
    const monitorText = await llmClient.ask('monitor', question, monitorHistory);
    if (!this.dom) return;
    this.setMentor('monitor');
    const body = this.appendMsg(this.mentorName('monitor'), '');
    await this.typewrite(body, monitorText);
    monitorHistory.push({ question, answer: monitorText });

    let targets = mentorRouter.parseMentions(monitorText).filter(id => id !== 'monitor');
    if (targets.length === 0) {
      targets = mentorRouter.routeTargets(mentorRouter.classify(question));
    }
    for (const id of targets.slice(0, 2)) {
      if (!this.dom) return;
      this.setMentor(id);
      const reply = await llmClient.ask(id, question, this.histories[id] ?? []);
      if (!this.dom) return;
      const b = this.appendMsg(this.mentorName(id), '');
      await this.typewrite(b, reply);
      (this.histories[id] ??= []).push({ question, answer: reply });
    }
  }

  // 离线：MentorRouter.handleMessage 同步序列（调度语 + 兜底答案）
  private async offlineRound(question: string): Promise<void> {
    const messages: ChatMessage[] = mentorRouter.handleMessage(question);
    for (const msg of messages) {
      if (!this.dom) return;
      this.setMentor(msg.mentor_id);
      const body = this.appendMsg(this.mentorName(msg.mentor_id), '');
      await this.typewrite(body, msg.text);
    }
  }

  close(): void {
    this.dom?.remove();
    this.dom = null;
  }
}

export const chatPanel = new ChatPanel();
