// LLMClient：DeepSeek 调用 / 超时 / 离线兜底（§3.6.3，冻结面）
// 唯一真实网络出口是私有 _generateReply()；测试注入传输层，不发真实请求。
import { eventBus } from './event_bus';
import { gameManager } from './game_manager';
import { qaFallback } from '../mentor/qa_fallback';
import { PromptSuffix } from '../mentor/prompt_suffix';
import { sanitizeInput } from '../mentor/input_sanitize';
import type { Row } from './data_loader';

export interface HistoryTurn {
  question: string;
  answer: string;
}

interface TransportResult {
  result: number; // 0 成功，其余失败（-1 网络错，-2 超时）
  code: number;
  body: string;
}

type Transport = (payload: { url: string; headers: Record<string, string>; body: string; timeoutSeconds: number }) => Promise<TransportResult>;

const ENDPOINT = 'https://api.deepseek.com/chat/completions';
const MODEL = 'deepseek-chat';
const CONFIG_KEY = 'ea_config';

// 存储抽象：localStorage 不可用时降级内存（NFR-06）
class SafeStorage {
  private mem = new Map<string, string>();
  private available: boolean | null = null;

  private check(): boolean {
    if (this.available !== null) return this.available;
    try {
      const k = '__ea_probe__';
      globalThis.localStorage?.setItem(k, '1');
      globalThis.localStorage?.removeItem(k);
      this.available = !!globalThis.localStorage;
    } catch {
      this.available = false;
    }
    return this.available;
  }

  get(key: string): string {
    if (this.check()) {
      try { return globalThis.localStorage.getItem(key) ?? ''; } catch { /* fallthrough */ }
    }
    return this.mem.get(key) ?? '';
  }

  set(key: string, value: string): void {
    if (this.check()) {
      try { globalThis.localStorage.setItem(key, value); return; } catch { /* fallthrough */ }
    }
    this.mem.set(key, value);
  }
}

export class LLMClient {
  private storage = new SafeStorage();
  private transport: Transport | null = null;
  private offlineForced = false;
  private offlineAuto = false;
  private lastAttempts = 0;
  private mentors: Row[] = [];
  private timeoutSec = 8;
  private retry = 1;

  loadMentors(rows: Row[]): void {
    this.mentors = rows || [];
  }

  setTransport(t: Transport): void {
    this.transport = t;
  }

  setQaFallback(rows: Row[]): void {
    qaFallback.loadFrom(rows);
  }

  // ---- 配置 ----
  private readConfig(): Record<string, string> {
    try {
      const raw = this.storage.get(CONFIG_KEY);
      if (!raw) return {};
      return JSON.parse(raw) as Record<string, string>;
    } catch {
      return {};
    }
  }

  private writeConfig(patch: Record<string, string>): void {
    const cfg = { ...this.readConfig(), ...patch };
    this.storage.set(CONFIG_KEY, JSON.stringify(cfg));
  }

  hasApiKey(): boolean {
    return !!this.readConfig().apiKey;
  }

  setApiKey(key: string): void {
    if (!key) return;
    this.writeConfig({ apiKey: key });
    // 有 key 后自动离线的状态清除，让下次请求重新尝试联网
    this.offlineAuto = false;
    this.emitModeIfChanged();
  }

  setProxyUrl(url: string): void {
    this.writeConfig({ proxyUrl: url });
  }

  isOffline(): boolean {
    return this.offlineForced || this.offlineAuto || !this.hasApiKey();
  }

  setOffline(value: boolean): void {
    this.offlineForced = value;
    this.writeConfig({ offline: value ? '1' : '' });
    this.emitModeIfChanged();
  }

  restoreOfflineFlag(): void {
    this.offlineForced = this.readConfig().offline === '1';
  }

  private emitModeIfChanged(): void {
    const cur = this.isOffline();
    if (cur !== this.lastMode) {
      this.lastMode = cur;
      eventBus.emit('mode_changed', { offline: cur });
    }
  }
  private lastMode: boolean | null = null;

  timeoutSeconds(): number {
    return this.timeoutSec;
  }

  retryCount(): number {
    return this.retry;
  }

  setTimeoutSeconds(v: number): void {
    this.timeoutSec = v;
  }

  setRetryCount(v: number): void {
    this.retry = v;
  }

  attemptCount(): number {
    return this.lastAttempts;
  }

  buildRequestBody(mentorId: string, question: string, history: HistoryTurn[]): Record<string, unknown> {
    const mentor = this.mentors.find(m => m.id === mentorId);
    const persona = mentor ? String(mentor.system_prompt ?? '') : '';
    const system = PromptSuffix.appendTo(persona);
    const maxHistory = Number(gameManager.getBalance('llm.history_rounds', 4));
    const messages: { role: string; content: string }[] = [{ role: 'system', content: system }];
    for (const turn of history.slice(-maxHistory)) {
      messages.push({ role: 'user', content: turn.question });
      messages.push({ role: 'assistant', content: turn.answer });
    }
    messages.push({ role: 'user', content: question });
    return {
      model: MODEL,
      messages,
      max_tokens: Number(gameManager.getBalance('llm.max_tokens', 300)),
      temperature: Number(gameManager.getBalance('llm.temperature', 0.7)),
      stream: false,
    };
  }

  private async defaultTransport(payload: { url: string; headers: Record<string, string>; body: string; timeoutSeconds: number }): Promise<TransportResult> {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), payload.timeoutSeconds * 1000);
    try {
      const resp = await fetch(payload.url, {
        method: 'POST',
        headers: payload.headers,
        body: payload.body,
        signal: ctrl.signal,
      });
      const text = await resp.text();
      return { result: 0, code: resp.status, body: text };
    } catch (e) {
      const isAbort = e instanceof DOMException && e.name === 'AbortError';
      return { result: isAbort ? -2 : -1, code: 0, body: '' };
    } finally {
      clearTimeout(timer);
    }
  }

  // 唯一发包点
  private async _generateReply(body: Record<string, unknown>): Promise<string> {
    const cfg = this.readConfig();
    const url = cfg.proxyUrl || ENDPOINT;
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (cfg.apiKey) headers['Authorization'] = `Bearer ${cfg.apiKey}`;
    const t = this.transport ?? ((p) => this.defaultTransport(p));
    const attempts = this.retry + 1;
    for (let i = 0; i < attempts; i++) {
      this.lastAttempts = i + 1;
      let res: TransportResult;
      try {
        res = await t({ url, headers, body: JSON.stringify(body), timeoutSeconds: this.timeoutSec });
      } catch {
        continue; // 传输层异常按失败处理
      }
      if (res.result !== 0) continue; // 网络错/超时
      if (res.code !== 200) continue; // 非 200
      try {
        const json = JSON.parse(res.body);
        const content = json?.choices?.[0]?.message?.content;
        if (typeof content === 'string' && content.trim()) return content.trim();
      } catch {
        // 畸形 body 按失败处理
      }
    }
    return '';
  }

  async ask(mentorId: string, question: string, history: HistoryTurn[]): Promise<string> {
    const clean = sanitizeInput(question);
    if (!clean) return '';
    this.lastAttempts = 0;
    this.timeoutSec = Number(gameManager.getBalance('llm.timeout_seconds', 8));
    this.retry = Number(gameManager.getBalance('llm.retry_count', 1));

    if (this.isOffline()) {
      const text = this._offlineReply(clean);
      eventBus.emit('reply_started', { mentorId });
      eventBus.emit('reply_finished', { mentorId, fullText: text, offline: true });
      this.emitModeIfChanged();
      return text;
    }

    eventBus.emit('reply_started', { mentorId });
    const body = this.buildRequestBody(mentorId, clean, history);
    const reply = await this._generateReply(body);
    if (reply) {
      this.offlineAuto = false;
      eventBus.emit('reply_finished', { mentorId, fullText: reply, offline: false });
      this.emitModeIfChanged();
      return reply;
    }
    // 四种失败收口：转离线兜底，不抛异常
    this.offlineAuto = true;
    const fallback = this._offlineReply(clean);
    eventBus.emit('reply_finished', { mentorId, fullText: fallback, offline: true });
    this.emitModeIfChanged();
    return fallback;
  }

  _offlineReply(question: string): string {
    const answer = qaFallback.answer(question);
    const badge = gameManager.getUiString('chat_offline_badge');
    return answer ? `${answer}${badge}` : badge;
  }
}

export const llmClient = new LLMClient();
