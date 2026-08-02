// ItemEffects：八种道具效果（§3.10）。效果值按 items.json 的 effect_value_key 动态读 balance。
import { gameManager } from '../core/game_manager';
import { knowledgeTip } from '../core/knowledge_tip';
import { eventBus } from '../core/event_bus';
import type { Row } from '../core/data_loader';

export class ItemEffects {
  private items: Row[] = [];
  private equipped = new Set<string>();

  loadFrom(rows: Row[]): void {
    this.items = rows || [];
  }

  item(id: string): Row {
    return this.items.find(i => i.id === id) ?? {};
  }

  isItemId(id: string): boolean {
    return this.items.some(i => i.id === id);
  }

  effectValue(id: string): number {
    const it = this.item(id);
    const key = String(it.effect_value_key ?? '');
    if (!key) return 0;
    return Number(gameManager.getBalance(key, 0));
  }

  equip(id: string): void {
    if (String(this.item(id).type) !== 'equip') return;
    this.equipped.add(id);
    eventBus.emit('equipment_changed', { id, equipped: true });
  }

  unequip(id: string): void {
    if (this.equipped.delete(id)) {
      eventBus.emit('equipment_changed', { id, equipped: false });
    }
  }

  isEquipped(id: string): boolean {
    return this.equipped.has(id);
  }

  equippedIds(): string[] {
    return [...this.equipped];
  }

  toggleEquip(id: string): void {
    if (this.isEquipped(id)) this.unequip(id);
    else this.equip(id);
  }

  // 使用道具。返回是否实际消耗（供背包扣数量）。
  useItem(id: string): boolean {
    const it = this.item(id);
    if (!it.id) return false;
    const effect = String(it.effect ?? 'none');
    const tipId = String(it.tip_id ?? '');
    if (tipId) knowledgeTip.show(tipId);
    switch (effect) {
      case 'restore_oxygen':
        gameManager.modifyOxygen(this.effectValue(id));
        return true;
      case 'light':
        this.toggleEquip(id);
        return false; // 装备型使用不消耗
      case 'immune_co':
        this.toggleEquip(id);
        return false;
      case 'kill_co':
        eventBus.emit('use_kill_co', {});
        return true;
      case 'kill_acid':
        eventBus.emit('use_kill_acid', {});
        return true;
      case 'test_hardwater':
        eventBus.emit('use_test_hardwater', {});
        return true;
      case 'extinguish':
        eventBus.emit('use_extinguish', {});
        return true;
      default:
        return false;
    }
  }

  isConsumable(id: string): boolean {
    return this.item(id).consumable === true;
  }
}

export const itemEffects = new ItemEffects();
