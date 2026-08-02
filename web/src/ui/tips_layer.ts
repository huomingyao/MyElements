// 字幕渲染层：banner（底部）/ warning（中部红字）/ bubble（跟随目标头顶）
import { knowledgeTip } from '../core/knowledge_tip';

export class TipsLayer {
  private bannerEl!: HTMLElement;
  private warningEl!: HTMLElement;
  private bubbleEl!: HTMLElement;
  bubbleTarget: { x: number; y: number } | null = null; // 屏幕坐标（百分比 0..1）

  init(root: HTMLElement): void {
    // 幂等：清理旧 DOM
    document.getElementById('tip-banner')?.remove();
    document.getElementById('tip-warning')?.remove();
    document.getElementById('tip-bubble')?.remove();
    this.bannerEl = document.createElement('div');
    this.bannerEl.id = 'tip-banner';
    this.warningEl = document.createElement('div');
    this.warningEl.id = 'tip-warning';
    this.bubbleEl = document.createElement('div');
    this.bubbleEl.id = 'tip-bubble';
    root.appendChild(this.bannerEl);
    root.appendChild(this.warningEl);
    root.appendChild(this.bubbleEl);
  }

  // 每帧由 WorldScene.update 调：推进字幕时钟并渲染当前字幕
  update(deltaMs: number): void {
    knowledgeTip.advance(deltaMs / 1000);
    const style = knowledgeTip.currentStyle();
    const text = knowledgeTip.currentText();
    this.render(this.bannerEl, style === 'banner', text);
    this.render(this.warningEl, style === 'warning', text);
    this.render(this.bubbleEl, style === 'bubble', text);
    if (style === 'bubble' && this.bubbleTarget) {
      this.bubbleEl.style.left = `${this.bubbleTarget.x * 100}%`;
      this.bubbleEl.style.top = `${this.bubbleTarget.y * 100}%`;
      this.bubbleEl.style.transform = 'translate(-50%, -110%)';
    }
  }

  private render(el: HTMLElement, visible: boolean, text: string): void {
    if (visible && text) {
      if (el.style.display !== 'block' || el.textContent !== text) {
        el.textContent = text;
        el.style.display = 'block';
      }
    } else if (el.style.display !== 'none') {
      el.style.display = 'none';
    }
  }
}

export const tipsLayer = new TipsLayer();
