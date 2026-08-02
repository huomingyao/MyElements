// 精灵帧注册与动画创建：从 SPRITE_FRAMES（Python 切片元数据）注册到 Phaser 纹理
import Phaser from 'phaser';
import { SPRITE_FRAMES } from '../gen/frames';

export const SHEET_KEYS = ['player', 'ghost', 'slime', 'mentor_monitor', 'mentor_assistant', 'mentor_chem', 'mentor_think'] as const;

export function registerSheetFrames(scene: Phaser.Scene): void {
  for (const sheet of SHEET_KEYS) {
    const tex = scene.textures.get(sheet);
    if (!tex) continue;
    const actions = SPRITE_FRAMES[sheet] || {};
    for (const [action, rects] of Object.entries(actions)) {
      rects.forEach((r, i) => {
        const frameName = `${action}_${i}`;
        if (!tex.has(frameName)) {
          tex.add(frameName, 0, r.x, r.y, r.w, r.h);
        }
      });
    }
  }
}

export function createAnim(
  scene: Phaser.Scene,
  sheet: string,
  action: string,
  opts: { frameRate?: number; repeat?: number } = {},
): string {
  const key = `${sheet}_${action}`;
  if (scene.anims.exists(key)) return key;
  const rects = SPRITE_FRAMES[sheet]?.[action] ?? [];
  const frames = rects.map((_, i) => ({ key: sheet, frame: `${action}_${i}` }));
  if (frames.length === 0) return key;
  scene.anims.create({
    key,
    frames,
    frameRate: opts.frameRate ?? 6,
    repeat: opts.repeat ?? -1,
  });
  return key;
}

// 各实体展示尺寸（世界像素，高度锚定）
export const DISPLAY_SIZE: Record<string, { h: number }> = {
  player: { h: 64 },
  ghost: { h: 52 },
  slime: { h: 44 },
  mentor_monitor: { h: 78 },
  mentor_assistant: { h: 78 },
  mentor_chem: { h: 78 },
  mentor_think: { h: 78 },
};

export function setDisplayHeight(sprite: Phaser.GameObjects.Sprite, h: number): void {
  const scale = h / sprite.height;
  sprite.setScale(scale);
}
