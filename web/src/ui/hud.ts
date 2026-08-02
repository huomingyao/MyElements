// HUD：三条数值条（事件驱动）+ 已收集计数 + 昼夜天数 + 快捷栏
import { eventBus } from '../core/event_bus';
import { gameManager } from '../core/game_manager';
import { knowledgeTip } from '../core/knowledge_tip';
import { inventory } from '../gameplay/inventory';
import { discovery } from '../gameplay/discovery';
import { itemEffects } from '../gameplay/item_effects';
import { recipeDB } from '../core/recipe_db';

export class Hud {
  private bars: Record<string, HTMLElement> = {};
  private counterEl!: HTMLElement;
  private daytimeEl!: HTMLElement;
  private hotbarEl!: HTMLElement;
  private lowOxygenWarned = false;
  private initialized = false;
  private daytimeTimer: number | null = null;

  init(root: HTMLElement): void {
    // 幂等：清理旧 DOM 与旧定时器（场景重进时）
    document.getElementById('hud')?.remove();
    document.getElementById('hotbar')?.remove();
    if (this.daytimeTimer !== null) {
      window.clearInterval(this.daytimeTimer);
      this.daytimeTimer = null;
    }
    const hud = document.createElement('div');
    hud.id = 'hud';
    hud.innerHTML = `
      <div class="hud-bar oxygen"><div class="fill"></div><div class="label">氧气</div></div>
      <div class="hud-bar energy"><div class="fill"></div><div class="label">能量</div></div>
      <div class="hud-bar health"><div class="fill"></div><div class="label">生命</div></div>
      <div id="hud-counter"></div>
      <div id="hud-daytime"></div>`;
    root.appendChild(hud);
    this.bars.oxygen = hud.querySelector('.hud-bar.oxygen')!;
    this.bars.energy = hud.querySelector('.hud-bar.energy')!;
    this.bars.health = hud.querySelector('.hud-bar.health')!;
    this.counterEl = hud.querySelector('#hud-counter')!;
    this.daytimeEl = hud.querySelector('#hud-daytime')!;

    this.hotbarEl = document.createElement('div');
    this.hotbarEl.id = 'hotbar';
    root.appendChild(this.hotbarEl);

    // 事件驱动（无 update 轮询）
    if (!this.initialized) {
      this.initialized = true;
      eventBus.on('oxygen_changed', p => this.setBar('oxygen', p.current, p.max));
      eventBus.on('energy_changed', p => this.setBar('energy', p.current, p.max));
      eventBus.on('health_changed', p => this.setBar('health', p.current, p.max));
      eventBus.on('inventory_changed', () => this.renderHotbar());
      eventBus.on('equipment_changed', () => this.renderHotbar());
      eventBus.on('substance_discovered', () => this.renderCounter());
      eventBus.on('day_started', () => this.renderDaytime());
      eventBus.on('night_started', () => this.renderDaytime());
      eventBus.on('tutorial_oxygen_hint', () => {
        knowledgeTip.showOnce('sys_oxygen_tutorial');
        this.flash('oxygen');
      });
    }

    this.setBar('oxygen', gameManager.oxygen, gameManager.oxygenMax);
    this.setBar('energy', gameManager.energy, gameManager.energyMax);
    this.setBar('health', gameManager.health, gameManager.healthMax);
    this.renderCounter();
    this.renderDaytime();
    this.renderHotbar();

    // 低频刷新时间显示（1s 一次足够，不属于数值条轮询）
    this.daytimeTimer = window.setInterval(() => this.renderDaytime(), 1000);
  }

  private setBar(kind: string, current: number, max: number): void {
    const bar = this.bars[kind];
    if (!bar) return;
    const fill = bar.querySelector('.fill') as HTMLElement;
    fill.style.width = `${Math.max(0, Math.min(100, (current / max) * 100))}%`;
    if (kind === 'oxygen') {
      const threshold = Number(gameManager.getBalance('stats.hud_low_oxygen_threshold', 30));
      if (current < threshold) {
        bar.classList.add('flash');
        if (!this.lowOxygenWarned) {
          this.lowOxygenWarned = true;
          knowledgeTip.show('sys_oxygen_low');
        }
      } else {
        bar.classList.remove('flash');
        if (current > threshold + 10) this.lowOxygenWarned = false;
      }
    }
  }

  private flash(kind: string): void {
    const bar = this.bars[kind];
    if (!bar) return;
    bar.classList.add('flash');
    window.setTimeout(() => {
      if (gameManager.oxygen >= Number(gameManager.getBalance('stats.hud_low_oxygen_threshold', 30))) {
        bar.classList.remove('flash');
      }
    }, 3600);
  }

  private renderCounter(): void {
    this.counterEl.textContent = gameManager.ui('collected_counter', discovery.countedCount);
  }

  private renderDaytime(): void {
    const key = gameManager.isNight() ? 'hud_night' : 'hud_day';
    this.daytimeEl.textContent = gameManager.ui(key, gameManager.dayCount);
  }

  private renderHotbar(): void {
    const hotbarCount = Number(gameManager.getBalance('inventory.hotbar_slots', 8));
    this.hotbarEl.innerHTML = '';
    for (let i = 0; i < hotbarCount; i++) {
      const slot = inventory.slots[i];
      const el = document.createElement('div');
      el.className = 'hotbar-slot';
      const key = document.createElement('span');
      key.className = 'key';
      key.textContent = String(i + 1);
      el.appendChild(key);
      if (slot && slot.count > 0) {
        const img = document.createElement('img');
        img.src = this.iconUrl(slot.id);
        img.alt = slot.id;
        el.appendChild(img);
        const cnt = document.createElement('span');
        cnt.className = 'cnt';
        cnt.textContent = slot.count > 1 ? String(slot.count) : '';
        el.appendChild(cnt);
        if (itemEffects.isEquipped(slot.id)) el.classList.add('equipped');
      }
      this.hotbarEl.appendChild(el);
    }
  }

  iconUrl(id: string): string {
    const sub = recipeDB.getSubstance(id);
    if (sub && sub.icon) return String(sub.icon);
    const item = itemEffects.item(id);
    if (item && item.icon) return String(item.icon);
    return 'assets/art/icons/placeholder.png';
  }
}

export const hud = new Hud();
