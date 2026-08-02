// KnowledgeTip：字幕引擎，唯一文案出口（§3.3，冻结面）
import { eventBus } from './event_bus';
import type { Row } from './data_loader';

export type TipStyle = 'bubble' | 'banner' | 'warning';

interface TipRow {
  id: string;
  style: TipStyle;
  duration: number;
  once: boolean;
  text: string;
}

const STYLE_DEFAULT_DURATION: Record<TipStyle, number> = { bubble: 3, banner: 4, warning: 5 };

export class KnowledgeTip {
  private table = new Map<string, TipRow>();
  private shownOnce = new Set<string>();
  private queue: TipRow[] = [];
  private current: TipRow | null = null;
  private remain = 0;

  loadFrom(rows: Row[]): void {
    this.table.clear();
    for (const r of rows) {
      const style = (r.style as TipStyle) || 'banner';
      this.table.set(String(r.id), {
        id: String(r.id),
        style,
        duration: typeof r.duration === 'number' ? r.duration : STYLE_DEFAULT_DURATION[style],
        once: r.once === true,
        text: String(r.text ?? ''),
      });
    }
  }

  reload(rows: Row[]): void {
    this.loadFrom(rows);
  }

  show(tipId: string): void {
    const tip = this.table.get(tipId);
    if (!tip) {
      console.warn(`KnowledgeTip: 不存在的 tip_id ${tipId}`);
      return;
    }
    this.enqueue(tip);
  }

  showOnce(tipId: string): void {
    const tip = this.table.get(tipId);
    if (!tip) {
      console.warn(`KnowledgeTip: 不存在的 tip_id ${tipId}`);
      return;
    }
    if (this.shownOnce.has(tipId)) return;
    this.enqueue({ ...tip, once: true });
  }

  showCustom(text: string, style: string, duration: number): void {
    const s = (['bubble', 'banner', 'warning'].includes(style) ? style : 'banner') as TipStyle;
    this.enqueue({ id: `__custom_${this.customSeq()}`, style: s, duration: duration || STYLE_DEFAULT_DURATION[s], once: false, text });
  }

  private customSeq(): number {
    this.seq = (this.seq + 1) % 100000;
    return this.seq;
  }
  private seq = 0;

  private enqueue(tip: TipRow): void {
    // 去重：同 id 字幕正在播放或已在队列中则跳过（防止连续交互堆积导致延迟卡顿）
    if (this.current?.id === tip.id) return;
    if (this.queue.some(t => t.id === tip.id)) return;
    // warning 抢占：打断在播字幕（被打断的 once 字幕撤销记录）
    if (tip.style === 'warning' && this.current) {
      if (this.current.once) this.shownOnce.delete(this.current.id);
      eventBus.emit('tip_finished', { tipId: this.current.id });
      this.current = null;
      this.remain = 0;
    }
    this.queue.push(tip);
    this.pump();
  }

  private pump(): void {
    if (this.current) return;
    const next = this.queue.shift();
    if (!next) return;
    this.current = next;
    this.remain = next.duration;
    if (next.once) this.shownOnce.add(next.id);
    eventBus.emit('tip_shown', { tipId: next.id });
  }

  advance(delta: number): void {
    if (!this.current) return;
    this.remain -= delta;
    if (this.remain <= 0) {
      const done = this.current;
      this.current = null;
      eventBus.emit('tip_finished', { tipId: done.id });
      this.pump();
    }
  }

  isShown(tipId: string): boolean {
    return this.shownOnce.has(tipId);
  }

  clearQueue(): void {
    if (this.current?.once) this.shownOnce.delete(this.current.id);
    this.queue = [];
    this.current = null;
    this.remain = 0;
  }

  resetShown(): void {
    this.shownOnce.clear();
  }

  currentTipId(): string {
    return this.current?.id ?? '';
  }

  currentText(): string {
    return this.current?.text ?? '';
  }

  currentStyle(): string {
    return this.current?.style ?? '';
  }

  currentDurationRatio(): number {
    if (!this.current) return 0;
    return this.remain / this.current.duration;
  }

  queueSize(): number {
    return this.queue.length;
  }

  getTip(tipId: string): TipRow | undefined {
    return this.table.get(tipId);
  }
}

export const knowledgeTip = new KnowledgeTip();
