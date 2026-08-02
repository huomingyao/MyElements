// 面板接线：注册到 UI 裁决器，主菜单按钮 -> 场景切换
import type Phaser from 'phaser';
import { uiManager } from './ui_manager';
import { mainMenuPanel, pausePanel, deathPanel, configPanel, mentorRoomPanel } from './panels_menu';
import { inventoryPanel, craftPanel, cardPopup, codexPanel, worldMapPanel } from './panels_game';
import { chatPanel } from './chat_panel';
import { setWorldSpawnOverride } from '../scenes/world_scene';
import { SPAWN_ACADEMY_GATE, SPAWN_DEFAULT } from '../world/maps';
import { saveStore } from '../save/save_store';

export function wirePanels(game: Phaser.Game): void {
  uiManager.register('mainmenu', mainMenuPanel);
  uiManager.register('inventory', inventoryPanel);
  uiManager.register('craft', craftPanel);
  uiManager.register('card', cardPopup);
  uiManager.register('chat', chatPanel);
  uiManager.register('worldmap', worldMapPanel);
  uiManager.register('codex', codexPanel);
  uiManager.register('pause', pausePanel);
  uiManager.register('death', deathPanel);
  uiManager.register('config', configPanel);
  uiManager.register('mentorroom', mentorRoomPanel);

  mainMenuPanel.onStart = () => {
    setWorldSpawnOverride(null);
    game.scene.getScene('Menu').scene.start('World');
  };
  mainMenuPanel.onAcademy = () => {
    // D2 裁决：导师学院门 → 世界场景 + 出生点改为学院（一次性标记）
    setWorldSpawnOverride({ map: SPAWN_ACADEMY_GATE.map, x: SPAWN_ACADEMY_GATE.x });
    game.scene.getScene('Menu').scene.start('World');
  };

  // 世界场景在游戏内请求回主菜单时保存
  game.events.on('shutdown', () => saveStore.save());
}
