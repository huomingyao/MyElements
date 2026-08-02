// 背包 / 合成台 / 知识卡片 / 图鉴 / 世界地图 面板
import { uiManager } from './ui_manager';
import { eventBus } from '../core/event_bus';
import { gameManager } from '../core/game_manager';
import { knowledgeTip } from '../core/knowledge_tip';
import { recipeDB } from '../core/recipe_db';
import type { CraftResult } from '../core/recipe_db';
import { worldMap } from '../core/world_map';
import { inventory } from '../gameplay/inventory';
import { discovery } from '../gameplay/discovery';
import { itemEffects } from '../gameplay/item_effects';
import { hydrogenEvent } from '../gameplay/hydrogen_event';
import { saltPurifier } from '../gameplay/salt_purifier';
import type { PurifyStep } from '../gameplay/salt_purifier';
import { hud } from './hud';
import { sfx } from '../audio/sfx';
import { saveStore } from '../save/save_store';

function el(tag: string, className = '', text = ''): HTMLElement {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text) e.textContent = text;
  return e;
}

// ---------------- 背包 ----------------
export class InventoryPanel {
  private dom: HTMLElement | null = null;
  private offInv: (() => void) | null = null;

  isOpen(): boolean { return !!this.dom; }

  open(): void {
    this.close();
    const wrap = el('div', 'panel');
    wrap.id = 'inventory-panel';
    wrap.appendChild(el('div', 'panel-title', gameManager.getUiString('inventory_title')));
    const grid = el('div', 'inv-grid');
    wrap.appendChild(grid);
    const hint = el('div', 'inv-hint', '');
    wrap.appendChild(hint);
    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;

    const render = () => this.renderGrid(grid, hint);
    this.offInv = eventBus.on('inventory_changed', render);
    render();
  }

  private renderGrid(grid: HTMLElement, hint: HTMLElement): void {
    grid.innerHTML = '';
    const total = inventory.slotCount;
    for (let i = 0; i < total; i++) {
      const slot = inventory.slots[i];
      const cell = el('div', 'inv-slot');
      if (slot && slot.count > 0) {
        const img = document.createElement('img');
        img.src = hud.iconUrl(slot.id);
        cell.appendChild(img);
        const cnt = el('span', 'cnt', slot.count > 1 ? String(slot.count) : '');
        cell.appendChild(cnt);
        if (itemEffects.isEquipped(slot.id)) {
          cell.appendChild(el('span', 'tag', 'E'));
          cell.style.borderColor = 'var(--energy)';
        }
        cell.title = this.nameOf(slot.id);
        cell.onclick = () => {
          this.useSlot(slot.id, hint);
        };
      }
      grid.appendChild(cell);
    }
  }

  private nameOf(id: string): string {
    const sub = recipeDB.getSubstance(id);
    if (sub.name) return `${sub.name} ${sub.formula}`;
    const item = itemEffects.item(id);
    return String(item.name ?? id);
  }

  private useSlot(id: string, hint: HTMLElement): void {
    const item = itemEffects.item(id);
    if (item.id) {
      if (String(item.type) === 'equip') {
        itemEffects.toggleEquip(id);
        sfx.page();
        return;
      }
      if (String(item.type) === 'consume') {
        const consumed = itemEffects.useItem(id);
        if (consumed) inventory.removeItem(id, 1);
        return;
      }
      hint.textContent = `${item.name}`;
      return;
    }
    const sub = recipeDB.getSubstance(id);
    // 可食用物质：喝水 / 吃盐回复能量（energy_restore 读数据表）
    const energyRestore = Number(sub.energy_restore ?? 0);
    if (energyRestore > 0) {
      if (inventory.removeItem(id, 1)) {
        gameManager.modifyEnergy(energyRestore);
        knowledgeTip.show('sys_energy_food');
        sfx.craftSuccess();
        hint.textContent = `${sub.name}：${gameManager.ui('item_usable_energy', energyRestore)}`;
      }
      return;
    }
    if (sub.codex_line) {
      hint.textContent = `${sub.name}：${sub.codex_line}`;
      sfx.page();
    }
  }

  close(): void {
    this.offInv?.();
    this.offInv = null;
    this.dom?.remove();
    this.dom = null;
    saveStore.save();
  }
}

// ---------------- 合成台 ----------------
export class CraftPanel {
  private dom: HTMLElement | null = null;
  private slots: string[] = [];
  private tool: 'portable' | 'alcohol_lamp' | 'bench' = 'portable';
  private purifyMode = false;
  private offInv: (() => void) | null = null;
  onCrafted: (() => void) | null = null;
  getZone: () => string = () => 'camp';

  isOpen(): boolean { return !!this.dom; }

  open(): void {
    this.close();
    this.slots = [];
    this.tool = 'portable';
    this.purifyMode = false;
    saltPurifier.reset();
    this.render();
    knowledgeTip.showOnce('sys_craft_hint');
    // 背包变化时实时刷新材料行
    this.offInv = eventBus.on('inventory_changed', () => {
      if (this.dom) this.render();
    });
  }

  private render(): void {
    this.dom?.remove();
    const gm = gameManager;
    const wrap = el('div', 'panel');
    wrap.id = 'craft-panel';
    wrap.appendChild(el('div', 'panel-title', gm.getUiString('craft_title')));

    // 材料槽
    const slotRow = el('div', 'craft-row');
    for (let i = 0; i < 3; i++) {
      const s = this.slots[i];
      const cell = el('div', `craft-slot${s ? ' filled' : ''}`);
      if (s) {
        const img = document.createElement('img');
        img.src = hud.iconUrl(s);
        cell.appendChild(img);
        cell.onclick = () => {
          this.slots.splice(i, 1);
          this.render();
        };
      } else {
        cell.appendChild(el('div', 'empty-tip', gm.getUiString('craft_slot_empty')));
      }
      slotRow.appendChild(cell);
    }
    wrap.appendChild(slotRow);

    // 器材选择
    const tools = el('div', 'tool-select');
    const toolDefs: [typeof this.tool, string][] = [
      ['portable', gm.getUiString('craft_tool_portable')],
      ['alcohol_lamp', gm.getUiString('craft_tool_lamp')],
      ['bench', gm.getUiString('craft_tool_bench')],
    ];
    for (const [id, label] of toolDefs) {
      const b = el('button', `btn small tool-btn${this.tool === id ? ' active' : ''}`, label) as HTMLButtonElement;
      b.onclick = () => { this.tool = id; this.render(); };
      tools.appendChild(b);
    }
    wrap.appendChild(tools);

    // 粗盐三步提纯子流程
    if (this.purifyMode) {
      const steps = el('div', 'purity-steps');
      const stepDefs: PurifyStep[] = ['dissolve', 'filter', 'evaporate'];
      const labels = ['溶解', '过滤', '蒸发'];
      stepDefs.forEach((step, i) => {
        const done = saltPurifier.progress() > i;
        const b = el('button', `btn small${done ? ' done' : ''}`, `${done ? '✓ ' : ''}${labels[i]}`) as HTMLButtonElement;
        b.onclick = () => {
          if (saltPurifier.perform(step)) {
            knowledgeTip.show('sys_purify');
            sfx.craftSuccess();
            if (saltPurifier.isDone()) {
              this.executeCraft('three_step');
            } else {
              this.render();
            }
          } else {
            knowledgeTip.show('sys_purify');
            sfx.craftFail();
          }
        };
        steps.appendChild(b);
      });
      wrap.appendChild(steps);
    }

    // 操作按钮
    const actions = el('div', 'craft-actions');
    const reactBtn = el('button', 'btn primary', gm.getUiString('craft_react')) as HTMLButtonElement;
    reactBtn.onclick = () => this.onReact();
    const igniteBtn = el('button', 'btn danger', gm.getUiString('craft_ignite')) as HTMLButtonElement;
    igniteBtn.onclick = () => this.onIgnite();
    actions.appendChild(reactBtn);
    actions.appendChild(igniteBtn);
    if (hydrogenEvent.isPurityCheckAvailable()) {
      const purityBtn = el('button', 'btn', gm.getUiString('craft_purity')) as HTMLButtonElement;
      purityBtn.onclick = () => {
        if (hydrogenEvent.doPurityCheck()) {
          sfx.purity();
          this.render();
        }
      };
      actions.appendChild(purityBtn);
    }
    const cancelBtn = el('button', 'btn', gm.getUiString('craft_cancel')) as HTMLButtonElement;
    cancelBtn.onclick = () => uiManager.closePanel();
    actions.appendChild(cancelBtn);
    wrap.appendChild(actions);

    // 材料提示区：这个物品是什么 + 可跟什么合成 + 怎么合成
    const hintArea = el('div', 'craft-hint-area');
    hintArea.innerHTML = this.buildHints();
    wrap.appendChild(hintArea);

    // 背包材料行（点击放入）
    wrap.appendChild(el('div', 'inv-hint', ''));
    const invRow = el('div', 'craft-inv-row');
    inventory.slots.forEach((s) => {
      const cell = el('div', 'inv-slot');
      const img = document.createElement('img');
      img.src = hud.iconUrl(s.id);
      cell.appendChild(img);
      cell.appendChild(el('span', 'cnt', s.count > 1 ? String(s.count) : ''));
      cell.onclick = () => {
        if (this.slots.length >= 3 || this.slots.includes(s.id)) return;
        this.slots.push(s.id);
        sfx.page();
        this.render();
      };
      invRow.appendChild(cell);
    });
    wrap.appendChild(invRow);

    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;
  }

  private sortedSlots(): string[] {
    return [...this.slots].sort();
  }

  // 材料提示：是什么 + 可跟什么合成 + 怎么合成（全部来自数据表）
  private buildHints(): string {
    const gm = gameManager;
    const lines: string[] = [];
    const nameOf = (id: string): string => {
      const sub = recipeDB.getSubstance(id);
      if (sub.name) return `${sub.name} ${sub.formula}`;
      const item = itemEffects.item(id);
      return String(item.name ?? id);
    };
    const toolName = (tool: string): string => {
      const key = { portable: 'craft_tool_portable', alcohol_lamp: 'craft_tool_lamp', bench: 'craft_tool_bench', electrolyzer: 'craft_tool_electrolyzer', filter: 'craft_tool_filter' }[tool];
      return key ? gm.getUiString(key) : tool;
    };
    const condName = (cond: string): string => gm.getUiString(`cond_${cond}`);

    for (const id of this.slots) {
      const recipes = recipeDB.allRecipes().filter(r => (r.inputs as string[]).includes(id));
      if (recipes.length === 0) {
        lines.push(`<b>${nameOf(id)}</b>：${gm.getUiString('craft_hint_none')}`);
        continue;
      }
      for (const r of recipes.slice(0, 2)) {
        const others = (r.inputs as string[]).filter(i => i !== id).map(nameOf).join('、');
        const cond = condName(String(r.condition));
        const condPart = cond ? `【${cond}】` : '';
        const outputs = (r.outputs as string[]).map(nameOf).join('、');
        const othersPart = others ? `${gm.getUiString('craft_hint_with')} ${others}` : '';
        lines.push(`<b>${nameOf(id)}</b>：${othersPart} ${gm.getUiString('craft_hint_at')}${toolName(String(r.tool))}${condPart}${gm.getUiString('craft_hint_make')} → ${outputs}`);
      }
    }
    return lines.join('<br>');
  }

  private onReact(): void {
    // 粗盐 + 实验台 → 进入三步提纯
    if (this.tool === 'bench' && this.sortedSlots().join(',') === 'crude_salt') {
      this.purifyMode = true;
      saltPurifier.reset();
      this.render();
      return;
    }
    const condition = this.tool === 'alcohol_lamp' ? 'heat' : 'none';
    this.executeCraft(condition);
  }

  private onIgnite(): void {
    let condition = 'ignite';
    // D3 裁决：矿洞内点燃碳按 low_oxygen 匹配（R3 陷阱）
    if (this.getZone() === 'mine' && this.sortedSlots().join(',') === 'c' && this.tool === 'alcohol_lamp') {
      condition = 'low_oxygen';
    }
    this.executeCraft(condition);
  }

  private executeCraft(condition: string): void {
    if (this.slots.length === 0) return;
    const inputs = this.sortedSlots();
    const result = recipeDB.tryCraft(inputs, this.tool, condition);
    if (result.success) {
      for (const id of inputs) inventory.removeItem(id, 1);
      for (const out of result.outputs) inventory.addItem(out, 1);
      sfx.craftSuccess();
      const recipe = recipeDB.getRecipe(result.recipe_id);
      if (recipe.unlock_tip) knowledgeTip.show(String(recipe.unlock_tip));
      if (result.recipe_id === 'r_carbon_incomplete') knowledgeTip.show('warn_co');
      // 产物功能提示（文字全部来自数据表卡片字段）
      const card = result.card as { title?: string; application?: string };
      if (card.application) {
        knowledgeTip.showCustom(`「${card.title ?? ''}」${card.application}`, 'banner', 4.5);
      }
      saveStore.save();
      this.onCrafted?.();
      this.slots = [];
      this.purifyMode = false;
      this.showCard(result); // 卡片接管面板位，合成台随之关闭
      return;
    }
    if (result.fail_reason === 'needs_purity_check') {
      // 氢气未验纯点燃 → 爆炸事件
      hydrogenEvent.ignite();
      sfx.explosion();
      this.slots = [];
      this.purifyMode = false;
      if (this.dom) this.render();
      return;
    }
    // 失败：显示失败文案，不消耗材料
    const fail = recipeDB.getFailMessage(result.fail_tip_id);
    if ('text' in fail) {
      knowledgeTip.showCustom(fail.text, 'banner', 4);
    }
    sfx.craftFail();
  }

  private showCard(result: CraftResult): void {
    uiManager.openPanel('card', result.card);
  }

  close(): void {
    // 取消时材料留在背包（slots 只是引用，从未移出背包，天然不丢失）
    this.offInv?.();
    this.offInv = null;
    this.slots = [];
    this.purifyMode = false;
    this.dom?.remove();
    this.dom = null;
    saveStore.save();
  }
}

// ---------------- 知识卡片 ----------------
export class CardPopup {
  private dom: HTMLElement | null = null;
  private keyListener: ((e: KeyboardEvent) => void) | null = null;

  isOpen(): boolean { return !!this.dom; }

  open(card?: { title: string; equation: string; body: string; application: string; footer: string }): void {
    if (card) this.openWith(card);
  }

  openWith(card: { title: string; equation: string; body: string; application: string; footer: string }): void {
    this.close();
    const wrap = el('div', 'panel');
    wrap.id = 'card-popup';
    wrap.appendChild(el('div', 'card-title', card.title));
    wrap.appendChild(el('div', 'card-equation', card.equation));
    wrap.appendChild(el('div', 'card-body', card.body));
    wrap.appendChild(el('div', 'card-app', card.application));
    wrap.appendChild(el('div', 'card-footer', card.footer));
    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;
    // 任意键/点击跳过（统一走裁决器关闭，保持面板状态一致）
    window.setTimeout(() => {
      this.keyListener = () => uiManager.closePanel();
      window.addEventListener('keydown', this.keyListener, { once: true });
      wrap.onclick = () => uiManager.closePanel();
    }, 300);
  }

  close(): void {
    if (this.keyListener) window.removeEventListener('keydown', this.keyListener);
    this.keyListener = null;
    this.dom?.remove();
    this.dom = null;
  }
}

// ---------------- 图鉴 ----------------
export class CodexPanel {
  private dom: HTMLElement | null = null;
  private tab: 'substances' | 'cards' = 'substances';

  isOpen(): boolean { return !!this.dom; }

  open(): void {
    this.close();
    this.tab = 'substances';
    this.render();
  }

  private render(): void {
    this.dom?.remove();
    const gm = gameManager;
    const wrap = el('div', 'panel');
    wrap.id = 'codex-panel';
    wrap.appendChild(el('div', 'panel-title', gm.getUiString('menu_codex')));

    const tabs = el('div', 'codex-tabs');
    const t1 = el('button', `btn small${this.tab === 'substances' ? ' active' : ''}`, gm.getUiString('inventory_title')) as HTMLButtonElement;
    t1.onclick = () => { this.tab = 'substances'; this.render(); sfx.page(); };
    const t2 = el('button', `btn small${this.tab === 'cards' ? ' active' : ''}`, gm.getUiString('craft_title')) as HTMLButtonElement;
    t2.onclick = () => { this.tab = 'cards'; this.render(); sfx.page(); };
    tabs.appendChild(t1);
    tabs.appendChild(t2);
    wrap.appendChild(tabs);

    if (this.tab === 'substances') {
      const grid = el('div', 'codex-grid');
      for (const s of recipeDB.allSubstances()) {
        const id = String(s.id);
        const found = discovery.isDiscovered(id);
        const cell = el('div', `codex-cell${found ? '' : ' locked'}`);
        const img = document.createElement('img');
        img.src = hud.iconUrl(id);
        cell.appendChild(img);
        cell.appendChild(el('div', 'nm', found ? String(s.name) : gm.getUiString('codex_locked')));
        cell.appendChild(el('div', 'cat', found ? `${s.formula} · ${s.category}` : ''));
        if (found) cell.appendChild(el('div', 'line', String(s.codex_line)));
        grid.appendChild(cell);
      }
      wrap.appendChild(grid);
    } else {
      const list = el('div', 'codex-cards');
      const unlocked = recipeDB.unlockedRecipes();
      for (const rid of unlocked) {
        const r = recipeDB.getRecipe(rid);
        const card = el('div', 'codex-card');
        card.appendChild(el('div', 'eq', `${r.card_title}　${r.equation}`));
        card.appendChild(el('div', 'ap', String(r.card_application)));
        list.appendChild(card);
      }
      wrap.appendChild(list);
    }

    const close = el('button', 'btn small', gm.getUiString('chat_close')) as HTMLButtonElement;
    close.style.marginTop = '6px';
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

// ---------------- 世界地图 ----------------
export class WorldMapPanel {
  private dom: HTMLElement | null = null;

  isOpen(): boolean { return !!this.dom; }

  open(): void {
    this.close();
    worldMap.open();
    const gm = gameManager;
    const wrap = el('div', 'panel');
    wrap.id = 'worldmap-panel';
    const canvasWrap = el('div');
    canvasWrap.id = 'worldmap-canvas-wrap';
    wrap.appendChild(canvasWrap);

    const info = el('div');
    info.id = 'map-info';
    wrap.appendChild(info);

    for (const zone of worldMap.allZones()) {
      const hs = zone.hotspot as { x: number; y: number; w: number; h: number };
      const unlocked = zone.unlocked === true;
      const z = el('div', `map-zone ${unlocked ? 'unlocked' : 'locked'}`);
      z.style.left = `${(hs.x / 640) * 100}%`;
      z.style.top = `${(hs.y / 360) * 100}%`;
      z.style.width = `${(hs.w / 640) * 100}%`;
      z.style.height = `${(hs.h / 360) * 100}%`;
      if (unlocked) {
        // 已解锁：填充对应地图素材（等比 cover），不空着
        const img = document.createElement('img');
        img.src = `assets/art/maps/${zone.id}.png`;
        img.alt = String(zone.name);
        img.style.width = '100%';
        img.style.height = '100%';
        img.style.objectFit = 'cover';
        img.style.imageRendering = 'pixelated';
        z.appendChild(img);
        const label = el('span', 'zone-label', String(zone.name));
        z.appendChild(label);
      } else {
        // 未解锁：灰色剪影 + 名称 + 角标
        z.appendChild(el('span', '', String(zone.name)));
        z.appendChild(el('span', 'badge', gm.getUiString('map_locked_badge')));
      }
      z.onclick = () => {
        sfx.page();
        if (unlocked) {
          info.textContent = `${zone.name}：${zone.brief}`;
          info.style.display = 'block';
        } else {
          z.classList.remove('shake');
          void z.offsetWidth; // 重触发动画
          z.classList.add('shake');
          info.textContent = `${zone.name}：${zone.teaser}`;
          info.style.display = 'block';
        }
      };
      canvasWrap.appendChild(z);
    }

    const close = el('button', 'btn small', gm.getUiString('chat_close')) as HTMLButtonElement;
    close.style.position = 'absolute';
    close.style.right = '6px';
    close.style.top = '6px';
    close.onclick = () => uiManager.closePanel();
    wrap.appendChild(close);
    document.getElementById('ui-root')!.appendChild(wrap);
    this.dom = wrap;
  }

  close(): void {
    worldMap.close();
    this.dom?.remove();
    this.dom = null;
  }
}

export const inventoryPanel = new InventoryPanel();
export const craftPanel = new CraftPanel();
export const cardPopup = new CardPopup();
export const codexPanel = new CodexPanel();
export const worldMapPanel = new WorldMapPanel();
