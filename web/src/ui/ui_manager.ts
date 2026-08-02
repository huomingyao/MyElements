// UI 裁决器：模态面板互斥、按键路由、过场黑屏（§3.11 规则）
import { eventBus } from '../core/event_bus';

export type PanelName =
  | '' | 'mainmenu' | 'inventory' | 'craft' | 'card' | 'chat' | 'worldmap'
  | 'codex' | 'pause' | 'death' | 'config' | 'mentorroom';

type PanelHandler = {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  open: (...args: any[]) => void;
  close: () => void;
  isOpen: () => boolean;
};

export class UIManager {
  private root!: HTMLElement;
  private fadeCover!: HTMLElement;
  private panels = new Map<PanelName, PanelHandler>();
  private current: PanelName = '';
  // 基底面板：普通面板关闭后自动恢复（主菜单专用）
  basePanel: PanelName = '';
  private keyHandler: ((e: KeyboardEvent) => void) | null = null;
  onKey: ((action: string, e: KeyboardEvent) => void) | null = null;

  init(): void {
    this.root = document.getElementById('ui-root')!;
    this.fadeCover = document.createElement('div');
    this.fadeCover.id = 'fade-cover';
    this.root.appendChild(this.fadeCover);

    this.keyHandler = (e: KeyboardEvent) => this.routeKey(e);
    window.addEventListener('keydown', this.keyHandler);
  }

  register(name: PanelName, handler: PanelHandler): void {
    this.panels.set(name, handler);
  }

  // 打开模态面板（互斥；chat 不阻断世界，但也独占面板位）
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  openPanel(name: PanelName, ...args: any[]): void {
    if (this.current === name) return;
    if (this.current && this.panels.get(this.current)?.isOpen()) {
      this.panels.get(this.current)?.close();
    }
    this.current = name;
    if (name) {
      this.panels.get(name)?.open(...args);
      eventBus.emit('ui_panel_changed', { panel: name });
    }
  }

  closePanel(): void {
    if (this.current && this.panels.get(this.current)?.isOpen()) {
      this.panels.get(this.current)?.close();
    }
    this.current = '';
    eventBus.emit('ui_panel_changed', { panel: '' });
    // 有基底面板时自动恢复（如主菜单），保证入口按键不丢
    if (this.basePanel && this.panels.has(this.basePanel)) {
      this.openPanel(this.basePanel);
    }
  }

  currentPanel(): PanelName {
    return this.current;
  }

  isOpen(name: PanelName): boolean {
    return this.current === name && (this.panels.get(name)?.isOpen() ?? false);
  }

  // 玩家输入是否被屏蔽（模态面板打开时；聊天框不屏蔽世界操作之外的移动——按 FR-M-02 世界不停）
  get inputBlocked(): boolean {
    if (!this.current) return false;
    return this.current !== 'chat';
  }

  // 键盘路由：输入框聚焦时只放行 Esc/Enter；Esc 关闭面板由裁决器统一处理
  private routeKey(e: KeyboardEvent): void {
    const active = document.activeElement as HTMLElement | null;
    const typing = active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA');
    if (typing) {
      if (e.key === 'Escape') {
        (active as HTMLInputElement).blur();
        e.preventDefault();
      }
      return; // 输入时游戏按键全部失效
    }
    const action = this.mapKey(e);
    if (!action) return;
    if (['up', 'down', 'left', 'right', 'jump', 'interact', 'inventory', 'pause', 'worldmap', 'codex', 'mentorroom', 'tab'].includes(action)) {
      e.preventDefault();
    }
    // Esc 关闭当前面板：裁决器直接处理（不依赖场景，主菜单界面同样生效）
    if (action === 'pause' && this.current) {
      this.closePanel();
      return;
    }
    this.onKey?.(action, e);
  }

  private mapKey(e: KeyboardEvent): string {
    const k = e.key;
    switch (k) {
      case 'a': case 'A': case 'ArrowLeft': return 'left';
      case 'd': case 'D': case 'ArrowRight': return 'right';
      case 'w': case 'W': case 'ArrowUp': case ' ': return 'jump';
      case 's': case 'S': case 'ArrowDown': return 'down';
      case 'e': case 'E': return 'interact';
      case 'f': case 'F': return 'attack';
      case 'Tab': return 'inventory';
      case 'm': case 'M': return 'worldmap';
      case 'c': case 'C': return 'codex';
      case 'j': case 'J': return 'mentorroom';
      case 'Escape': return 'pause';
      default:
        if (/^[1-8]$/.test(k)) return `slot_${k}`;
        return '';
    }
  }

  // 过场黑屏（穿梭用）
  async fadeThrough(midAction: () => void, holdMs = 120): Promise<void> {
    this.fadeCover.style.opacity = '1';
    await this.wait(340);
    midAction();
    await this.wait(holdMs);
    this.fadeCover.style.opacity = '0';
  }

  async fadeIn(): Promise<void> {
    this.fadeCover.style.opacity = '1';
    await this.wait(340);
  }

  fadeOut(): void {
    this.fadeCover.style.opacity = '0';
  }

  private wait(ms: number): Promise<void> {
    return new Promise(r => setTimeout(r, ms));
  }

  // 主菜单（MenuScene 调用）
  showMainMenu(): void {
    this.openPanel('mainmenu');
    this.basePanel = 'mainmenu';
  }

  hideMainMenu(): void {
    this.basePanel = '';
    if (this.current === 'mainmenu') this.closePanel();
  }
}

export const uiManager = new UIManager();
