// 交互系统：统一 E 键 + 最近目标选择（FR-P-02）
export interface Interactable {
  map: string;
  x: number;
  y: number;
  radius: number;
  getInteractPrompt(): string;
  canInteract(): boolean;
  interact(): void;
}

export class InteractRegistry {
  private items: Interactable[] = [];

  add(it: Interactable): void {
    this.items.push(it);
  }

  remove(it: Interactable): void {
    const i = this.items.indexOf(it);
    if (i >= 0) this.items.splice(i, 1);
  }

  clear(): void {
    this.items = [];
  }

  nearest(map: string, x: number, y: number): Interactable | null {
    let best: Interactable | null = null;
    let bestD = Infinity;
    for (const it of this.items) {
      if (it.map !== map) continue;
      if (!it.canInteract()) continue;
      const d = Math.hypot(it.x - x, it.y - y);
      if (d <= it.radius && d < bestD) {
        bestD = d;
        best = it;
      }
    }
    return best;
  }
}

export const interactRegistry = new InteractRegistry();
