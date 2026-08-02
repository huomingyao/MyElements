// MenuScene：主菜单背景（草原图 + 标题），按钮由 DOM 主菜单提供
import Phaser from 'phaser';
import { uiManager } from '../ui/ui_manager';

export class MenuScene extends Phaser.Scene {
  constructor() {
    super('Menu');
  }

  create(): void {
    uiManager.closePanel();
    // 背景：草原图铺满
    const bg = this.add.image(0, 0, 'map_grassland').setOrigin(0, 0);
    const scale = Math.max(640 / bg.width, 360 / bg.height);
    bg.setScale(scale);
    bg.setY(360 - bg.height * scale);
    // 玩家角色点缀
    const player = this.add.sprite(500, 330, 'player', 'idle_0');
    const scaleP = 120 / player.height;
    player.setScale(scaleP);
    this.tweens.add({ targets: player, y: 326, duration: 1200, yoyo: true, repeat: -1, ease: 'Sine.easeInOut' });

    uiManager.showMainMenu();
    this.events.once('shutdown', () => uiManager.hideMainMenu());
  }
}
