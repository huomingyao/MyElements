// 主菜单 / 暂停 / 死亡 / 设置 / 导师室 面板
import { uiManager } from './ui_manager';
import { eventBus } from '../core/event_bus';
import { gameManager } from '../core/game_manager';
import { llmClient } from '../core/llm_client';
import { mentorRouter } from '../mentor/mentor_router';

function el(tag: string, className = '', text = ''): HTMLElement {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text) e.textContent = text;
  return e;
}

// ---------------- 主菜单 ----------------
export class MainMenuPanel {
  private dom: HTMLElement | null = null;
  onStart: (() => void) | null = null;
  onAcademy: (() => void) | null = null;

  isOpen(): boolean { return !!this.dom; }

  open(): void {
    this.close();
    const gm = gameManager;
    const wrap = el('div');
    wrap.id = 'main-menu';
    wrap.appendChild(el('div', 'game-title', '元素炼金物语'));
    wrap.appendChild(el('div', 'game-sub', '—— 知识不是游戏的皮肤，是游戏的物理引擎 ——'));

    const mk = (label: string, fn: () => void, primary = false) => {
      const b = el('button', `btn${primary ? ' primary' : ''}`, label) as HTMLButtonElement;
      b.onclick = fn;
      wrap.appendChild(b);
      return b;
    };
    mk(gm.getUiString('menu_start'), () => { this.onStart?.(); }, true);
    mk(gm.getUiString('menu_academy'), () => { this.onAcademy?.(); });
    mk(gm.getUiString('menu_codex') + ' · ' + gm.getUiString('inventory_title'), () => {
      uiManager.openPanel('codex');
    });
    mk(gm.getUiString('menu_map'), () => uiManager.openPanel('worldmap'));
    mk(gm.getUiString('menu_quit'), () => window.location.reload());
    wrap.appendChild(el('div', 'footer-note', 'A/D 移动 · Space 跳跃 · E 交互 · F 打怪 · Tab 背包 · J 导师室 · M 地图 · C 图鉴 · Esc 暂停'));
    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;
  }

  close(): void {
    this.dom?.remove();
    this.dom = null;
  }
}

// ---------------- 暂停 ----------------
export class PausePanel {
  private dom: HTMLElement | null = null;
  onToMenu: (() => void) | null = null;

  isOpen(): boolean { return !!this.dom; }

  open(): void {
    this.close();
    const wrap = el('div', 'panel');
    wrap.id = 'pause-menu';
    wrap.appendChild(el('div', 'panel-title', gameManager.getUiString('pause_title')));
    const b1 = el('button', 'btn', gameManager.getUiString('pause_continue')) as HTMLButtonElement;
    b1.onclick = () => uiManager.closePanel();
    const b2 = el('button', 'btn', gameManager.getUiString('pause_to_menu')) as HTMLButtonElement;
    b2.onclick = () => { this.onToMenu?.(); };
    wrap.appendChild(b1);
    wrap.appendChild(b2);
    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;
    eventBus.emit('pause_toggled', { paused: true });
  }

  close(): void {
    this.dom?.remove();
    this.dom = null;
    eventBus.emit('pause_toggled', { paused: false });
  }
}

// ---------------- 死亡画面 ----------------
export class DeathPanel {
  private dom: HTMLElement | null = null;
  onRespawn: (() => void) | null = null;
  private keyListener: ((e: KeyboardEvent) => void) | null = null;

  isOpen(): boolean { return !!this.dom; }

  open(): void {
    this.close();
    const wrap = el('div');
    wrap.id = 'death-screen';
    wrap.appendChild(el('div', 'death-title', gameManager.getUiString('death_title')));
    wrap.appendChild(el('div', 'death-info', gameManager.getUiString('death_info')));
    wrap.appendChild(el('div', 'death-day', gameManager.ui('death_day', gameManager.dayCount)));
    wrap.appendChild(el('div', 'death-hint', gameManager.getUiString('death_hint')));
    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;
    this.keyListener = () => {
      this.onRespawn?.();
    };
    window.setTimeout(() => {
      if (this.keyListener) window.addEventListener('keydown', this.keyListener, { once: true });
    }, 600);
  }

  close(): void {
    this.dom?.remove();
    this.dom = null;
    if (this.keyListener) window.removeEventListener('keydown', this.keyListener);
    this.keyListener = null;
  }
}

// ---------------- 设置面板 ----------------
export class ConfigPanel {
  private dom: HTMLElement | null = null;

  isOpen(): boolean { return !!this.dom; }

  open(): void {
    this.close();
    const wrap = el('div', 'panel');
    wrap.id = 'config-panel';
    wrap.appendChild(el('div', 'panel-title', gameManager.getUiString('chat_config')));

    const keyInput = document.createElement('input');
    keyInput.type = 'password';
    keyInput.placeholder = 'DeepSeek API Key';
    wrap.appendChild(keyInput);

    const row = el('div', 'row');
    const offlineBox = document.createElement('input');
    offlineBox.type = 'checkbox';
    offlineBox.checked = llmClient.isOffline();
    offlineBox.id = 'offline-toggle';
    const offlineLabel = document.createElement('label');
    offlineLabel.textContent = gameManager.getUiString('chat_offline_badge');
    offlineLabel.htmlFor = 'offline-toggle';
    row.appendChild(offlineBox);
    row.appendChild(offlineLabel);
    wrap.appendChild(row);

    wrap.appendChild(el('div', 'note', gameManager.getUiString('config_note')));

    const apply = el('button', 'btn primary', gameManager.getUiString('config_apply')) as HTMLButtonElement;
    apply.onclick = () => {
      const key = keyInput.value.trim();
      if (key) llmClient.setApiKey(key); // 空串视为不改动，不回显不记录
      llmClient.setOffline(offlineBox.checked);
      uiManager.closePanel();
    };
    wrap.appendChild(apply);
    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;
  }

  close(): void {
    this.dom?.remove();
    this.dom = null;
  }
}

// ---------------- 导师室 ----------------
export class MentorRoomPanel {
  private dom: HTMLElement | null = null;
  onSelect: ((mentorId: string) => void) | null = null;

  isOpen(): boolean { return !!this.dom; }

  open(): void {
    this.close();
    const wrap = el('div', 'panel');
    wrap.id = 'mentor-room-panel';
    wrap.appendChild(el('div', 'panel-title', gameManager.getUiString('menu_academy')));
    const cards = el('div', 'mentor-cards');
    for (const m of mentorRouter.allMentors()) {
      const card = el('div', 'mentor-card');
      const img = document.createElement('img');
      img.src = String(m.avatar_idle);
      img.alt = String(m.name);
      card.appendChild(img);
      card.appendChild(el('div', 'nm', `${m.name}`));
      card.appendChild(el('div', 'ti', `${m.title} · ${m.room}`));
      card.onclick = () => {
        this.onSelect?.(String(m.id));
      };
      cards.appendChild(card);
    }
    wrap.appendChild(cards);
    const close = el('button', 'btn small', gameManager.getUiString('chat_close')) as HTMLButtonElement;
    close.style.marginTop = '8px';
    close.onclick = () => uiManager.closePanel();
    wrap.appendChild(close);
    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;
  }

  close(): void {
    this.dom?.remove();
    this.dom = null;
  }
}

export const mainMenuPanel = new MainMenuPanel();
export const pausePanel = new PausePanel();
export const deathPanel = new DeathPanel();
export const configPanel = new ConfigPanel();
export const mentorRoomPanel = new MentorRoomPanel();
