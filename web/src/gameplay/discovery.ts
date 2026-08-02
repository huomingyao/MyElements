// Discovery：已发现物质集合（§3.10）。计数集合由 substances 表 count_in_hud 得出，不写死 16。
import { eventBus } from '../core/event_bus';
import { recipeDB } from '../core/recipe_db';

export class Discovery {
  private discovered = new Set<string>();

  discover(id: string): boolean {
    if (this.discovered.has(id)) return false;
    this.discovered.add(id);
    eventBus.emit('substance_discovered', { substanceId: id });
    return true;
  }

  isDiscovered(id: string): boolean {
    return this.discovered.has(id);
  }

  get discoveredCount(): number {
    // HUD 计数口径：只数 count_in_hud != false 的物质
    let n = 0;
    for (const id of this.discovered) {
      const s = recipeDB.getSubstance(id);
      if (s && s.count_in_hud !== false) n += 1;
    }
    return n;
  }

  discoveredIds(): string[] {
    return [...this.discovered];
  }

  get countTotal(): number {
    return recipeDB.allSubstances().filter(s => s.count_in_hud !== false).length;
  }

  get countedCount(): number {
    return this.discoveredCount;
  }

  reset(): void {
    this.discovered.clear();
  }

  restore(ids: string[]): void {
    this.discovered = new Set(ids);
  }
}

export const discovery = new Discovery();
