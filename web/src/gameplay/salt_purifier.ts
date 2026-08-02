// SaltPurifier：粗盐提纯三步状态机（§3.10）。顺序强制，跳步给提示不给产物。
export type PurifyStep = 'dissolve' | 'filter' | 'evaporate';
const ORDER: PurifyStep[] = ['dissolve', 'filter', 'evaporate'];

export class SaltPurifier {
  private index = 0;

  reset(): void {
    this.index = 0;
  }

  currentStep(): PurifyStep | 'done' {
    return this.index >= ORDER.length ? 'done' : ORDER[this.index];
  }

  // 执行某步。跳步返回 false；顺序执行推进。
  perform(step: PurifyStep): boolean {
    if (this.currentStep() !== step) return false;
    this.index += 1;
    return true;
  }

  isDone(): boolean {
    return this.index >= ORDER.length;
  }

  progress(): number {
    return this.index;
  }
}

export const saltPurifier = new SaltPurifier();
