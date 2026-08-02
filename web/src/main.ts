// 入口：Phaser 配置（640×360 整数倍缩放、WebGL 失败回退 Canvas）+ DOM UI 启动
import Phaser from 'phaser';
import { BootScene } from './scenes/boot_scene';
import { MenuScene } from './scenes/menu_scene';
import { WorldScene } from './scenes/world_scene';
import { uiManager } from './ui/ui_manager';
import { wirePanels } from './ui/wiring';

const GAME_W = 640;
const GAME_H = 360;

function resizeShell(): void {
  const shell = document.getElementById('game-shell')!;
  const uiRoot = document.getElementById('ui-root')!;
  const scale = Math.max(1, Math.floor(Math.min(window.innerWidth / GAME_W, window.innerHeight / GAME_H)));
  shell.style.width = `${GAME_W * scale}px`;
  shell.style.height = `${GAME_H * scale}px`;
  // DOM UI 以 640×360 逻辑尺寸渲染，整体整数倍放大
  uiRoot.style.width = `${GAME_W}px`;
  uiRoot.style.height = `${GAME_H}px`;
  uiRoot.style.transform = `scale(${scale})`;
  uiRoot.style.transformOrigin = 'top left';
}
window.addEventListener('resize', resizeShell);
resizeShell();

const config: Phaser.Types.Core.GameConfig = {
  type: Phaser.AUTO, // WebGL 优先，失败自动回退 Canvas
  parent: 'game-container',
  width: GAME_W,
  height: GAME_H,
  pixelArt: true,
  roundPixels: true,
  backgroundColor: '#0d0b12',
  scale: {
    mode: Phaser.Scale.FIT,
    autoCenter: Phaser.Scale.CENTER_BOTH,
  },
  scene: [BootScene, MenuScene, WorldScene],
  banner: false,
};

const game = new Phaser.Game(config);
uiManager.init();
wirePanels(game);

// 音频：进网站即开始全局播放（浏览器拦截则由首次交互自动接管）
import { sfx } from './audio/sfx';
sfx.init();

// 调试/冒烟测试挂钩（不进任何 UI，不影响玩家）
import { gameManager } from './core/game_manager';
import { inventory } from './gameplay/inventory';
import { itemEffects } from './gameplay/item_effects';
import { discovery } from './gameplay/discovery';
import { recipeDB } from './core/recipe_db';
import { hydrogenEvent } from './gameplay/hydrogen_event';
(window as unknown as Record<string, unknown>).__ea = {
  game, gameManager, inventory, itemEffects, discovery, recipeDB, hydrogenEvent, uiManager, sfx,
};
