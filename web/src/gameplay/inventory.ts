// Inventory：8 格快捷栏 + 堆叠 99（§3.10）
import { eventBus } from '../core/event_bus';
import { gameManager } from '../core/game_manager';

export interface Slot {
  id: string;
  count: number;
}

export class Inventory {
  slots: Slot[] = [];

  get slotCount(): number {
    return Number(gameManager.getBalance('inventory.hotbar_slots', 8)) * 3; // 8 格快捷栏 ×3 行背包
  }

  get hotbarCount(): number {
    return Number(gameManager.getBalance('inventory.hotbar_slots', 8));
  }

  get stackLimit(): number {
    return Number(gameManager.getBalance('inventory.stack_limit', 99));
  }

  get usedSlots(): number {
    return this.slots.filter(s => s.count > 0 && s.id).length;
  }

  countOf(id: string): number {
    return this.slots.filter(s => s.id === id).reduce((a, s) => a + s.count, 0);
  }

  hasItem(id: string, count = 1): boolean {
    return this.countOf(id) >= count;
  }

  // 返回未装入的数量（背包满时不静默丢弃）
  addItem(id: string, count: number): number {
    let remain = count;
    // 先堆叠已有格
    for (const s of this.slots) {
      if (remain <= 0) break;
      if (s.id === id && s.count < this.stackLimit) {
        const take = Math.min(this.stackLimit - s.count, remain);
        s.count += take;
        remain -= take;
      }
    }
    // 再开新格
    while (remain > 0 && this.slots.length < this.slotCount) {
      const take = Math.min(this.stackLimit, remain);
      this.slots.push({ id, count: take });
      remain -= take;
    }
    if (remain !== count) eventBus.emit('inventory_changed', {});
    return remain;
  }

  removeItem(id: string, count: number): boolean {
    if (this.countOf(id) < count) return false;
    let remain = count;
    for (let i = this.slots.length - 1; i >= 0 && remain > 0; i--) {
      const s = this.slots[i];
      if (s.id !== id) continue;
      const take = Math.min(s.count, remain);
      s.count -= take;
      remain -= take;
      if (s.count <= 0) this.slots.splice(i, 1);
    }
    eventBus.emit('inventory_changed', {});
    return true;
  }

  removeOneFromSlot(slotIndex: number): Slot | null {
    const s = this.slots[slotIndex];
    if (!s) return null;
    s.count -= 1;
    const out = { id: s.id, count: 1 };
    if (s.count <= 0) this.slots.splice(slotIndex, 1);
    eventBus.emit('inventory_changed', {});
    return out;
  }

  clear(): Slot[] {
    const out = this.slots.map(s => ({ ...s }));
    this.slots = [];
    eventBus.emit('inventory_changed', {});
    return out;
  }

  snapshot(): Slot[] {
    return this.slots.map(s => ({ ...s }));
  }

  restore(slots: Slot[]): void {
    this.slots = slots.map(s => ({ ...s }));
    eventBus.emit('inventory_changed', {});
  }
}

export const inventory = new Inventory();
