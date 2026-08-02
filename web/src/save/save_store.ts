// 轻量本地存档（§3.8）：三值/背包/发现集合/解锁标记/天数。localStorage 不可用降级内存。
import { gameManager } from '../core/game_manager';
import { inventory } from '../gameplay/inventory';
import { discovery } from '../gameplay/discovery';
import { recipeDB } from '../core/recipe_db';

const PREFIX = 'ea_save_v1';

class SafeStorage {
  private mem = new Map<string, string>();
  private ok: boolean | null = null;
  private check(): boolean {
    if (this.ok !== null) return this.ok;
    try {
      globalThis.localStorage?.setItem('__ea_probe__', '1');
      globalThis.localStorage?.removeItem('__ea_probe__');
      this.ok = !!globalThis.localStorage;
    } catch {
      this.ok = false;
    }
    return this.ok;
  }
  get(k: string): string {
    if (this.check()) { try { return globalThis.localStorage.getItem(k) ?? ''; } catch { /* */ } }
    return this.mem.get(k) ?? '';
  }
  set(k: string, v: string): void {
    if (this.check()) { try { globalThis.localStorage.setItem(k, v); return; } catch { /* */ } }
    this.mem.set(k, v);
  }
}

const storage = new SafeStorage();

export class SaveStore {
  save(): void {
    try {
      storage.set(`${PREFIX}.stats`, JSON.stringify({
        oxygen: gameManager.oxygen, energy: gameManager.energy, health: gameManager.health,
        dayCount: gameManager.dayCount, timeOfDay: gameManager.timeOfDay,
      }));
      storage.set(`${PREFIX}.inventory`, JSON.stringify(inventory.snapshot()));
      storage.set(`${PREFIX}.discovery`, JSON.stringify(discovery.discoveredIds()));
      storage.set(`${PREFIX}.flags`, JSON.stringify({
        explosion_happened: gameManager.getFlag('explosion_happened'),
        purity_check_unlocked: gameManager.getFlag('purity_check_unlocked'),
      }));
      storage.set(`${PREFIX}.unlocked_recipes`, JSON.stringify(recipeDB.unlockedRecipes()));
    } catch (e) {
      console.warn('SaveStore: 存档失败（降级内存）', e);
    }
  }

  load(): void {
    try {
      const statsRaw = storage.get(`${PREFIX}.stats`);
      if (statsRaw) {
        const s = JSON.parse(statsRaw);
        gameManager.oxygen = s.oxygen ?? gameManager.oxygenMax;
        gameManager.energy = s.energy ?? gameManager.energyMax;
        gameManager.health = s.health ?? gameManager.healthMax;
        gameManager.dayCount = s.dayCount ?? 1;
        gameManager.timeOfDay = s.timeOfDay ?? 0;
      }
      const invRaw = storage.get(`${PREFIX}.inventory`);
      if (invRaw) inventory.restore(JSON.parse(invRaw));
      const disRaw = storage.get(`${PREFIX}.discovery`);
      if (disRaw) discovery.restore(JSON.parse(disRaw));
      const flagsRaw = storage.get(`${PREFIX}.flags`);
      if (flagsRaw) {
        const f = JSON.parse(flagsRaw);
        if (f.explosion_happened) gameManager.setFlag('explosion_happened', true);
        if (f.purity_check_unlocked) gameManager.setFlag('purity_check_unlocked', true);
      }
      const recRaw = storage.get(`${PREFIX}.unlocked_recipes`);
      if (recRaw) recipeDB.restoreUnlocked(JSON.parse(recRaw));
    } catch (e) {
      console.warn('SaveStore: 读档失败，按新开局处理', e);
    }
  }

  clear(): void {
    for (const k of ['stats', 'inventory', 'discovery', 'flags', 'unlocked_recipes']) {
      storage.set(`${PREFIX}.${k}`, '');
    }
  }

  hasSave(): boolean {
    return !!storage.get(`${PREFIX}.stats`);
  }
}

export const saveStore = new SaveStore();
