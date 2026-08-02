// BootScene：加载数据表与素材、初始化全部 core 单例、解锁音频
import Phaser from 'phaser';
import { DataLoader } from '../core/data_loader';
import { gameManager } from '../core/game_manager';
import { knowledgeTip } from '../core/knowledge_tip';
import { recipeDB } from '../core/recipe_db';
import { worldMap } from '../core/world_map';
import { llmClient } from '../core/llm_client';
import { mentorRouter } from '../mentor/mentor_router';
import { qaFallback } from '../mentor/qa_fallback';
import { itemEffects } from '../gameplay/item_effects';
import { hydrogenEvent } from '../gameplay/hydrogen_event';
import { saveStore } from '../save/save_store';
import { registerSheetFrames } from '../world/sprite_factory';

export class BootScene extends Phaser.Scene {
  constructor() {
    super('Boot');
  }

  preload(): void {
    // 地图背景
    this.load.image('map_grassland', 'assets/art/maps/grassland.png');
    this.load.image('map_camp', 'assets/art/maps/camp.png');
    this.load.image('map_mine', 'assets/art/maps/mine.png');
    this.load.image('map_saltlake', 'assets/art/maps/saltlake.png');
    this.load.image('map_academy', 'assets/art/maps/academy.png');
    // 精灵表
    this.load.image('player', 'assets/art/chars/player.png');
    this.load.image('ghost', 'assets/art/chars/ghost.png');
    this.load.image('slime', 'assets/art/chars/slime.png');
    this.load.image('mentor_monitor', 'assets/art/chars/mentor_monitor.png');
    this.load.image('mentor_assistant', 'assets/art/chars/mentor_assistant.png');
    this.load.image('mentor_chem', 'assets/art/chars/mentor_chem.png');
    this.load.image('mentor_think', 'assets/art/chars/mentor_think.png');
  }

  async create(): Promise<void> {
    try {
      const data = await DataLoader.loadAll();
      gameManager.loadBalance(data.balance, data.uiStrings);
      knowledgeTip.loadFrom(data.tips);
      recipeDB.loadFrom(data.substances, data.recipes, data.failMessages, data.items, data.tips);
      worldMap.loadFrom(data.worldmap);
      llmClient.loadMentors(data.mentors);
      llmClient.setQaFallback(data.qaFallback);
      llmClient.restoreOfflineFlag();
      mentorRouter.loadFrom(data.mentors);
      qaFallback.loadFrom(data.qaFallback);
      itemEffects.loadFrom(data.items);
      hydrogenEvent.loadQaKeywords(data.qaFallback);
      saveStore.load();

      // 采集物图标（数据驱动加载）
      const iconIds = [
        ...data.substances.map(s => String(s.id)),
        ...data.items.map(i => String(i.id)),
      ];
      for (const id of iconIds) {
        this.load.image(`icon_${id}`, `assets/art/icons/${id}.png`);
      }
      await new Promise<void>(resolve => {
        this.load.once('complete', () => resolve());
        this.load.start();
      });
      // 注册精灵帧（全局一次，Menu/World 共用）
      registerSheetFrames(this);
    } catch (e) {
      console.error('BootScene: 数据加载失败', e);
    }

    this.scene.start('Menu');
  }
}
