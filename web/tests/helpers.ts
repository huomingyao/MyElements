// 测试共享：把真实数据表注入各单例
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gameManager } from '../src/core/game_manager';
import { knowledgeTip } from '../src/core/knowledge_tip';
import { recipeDB } from '../src/core/recipe_db';
import { worldMap } from '../src/core/world_map';
import { mentorRouter } from '../src/mentor/mentor_router';
import { qaFallback } from '../src/mentor/qa_fallback';
import { llmClient } from '../src/core/llm_client';
import { itemEffects } from '../src/gameplay/item_effects';
import { hydrogenEvent } from '../src/gameplay/hydrogen_event';
import { eventBus } from '../src/core/event_bus';

const dataDir = join(__dirname, '..', 'data');

export function loadJson(name: string): never {
  return JSON.parse(readFileSync(join(dataDir, `${name}.json`), 'utf-8')) as never;
}

export function injectAllData(): void {
  const substances = loadJson('substances') as unknown as Record<string, unknown>[];
  const recipes = loadJson('recipes') as unknown as Record<string, unknown>[];
  const failMessages = loadJson('fail_messages') as unknown as Record<string, unknown>[];
  const tips = loadJson('tips') as unknown as Record<string, unknown>[];
  const mentors = loadJson('mentors') as unknown as Record<string, unknown>[];
  const qa = loadJson('qa_fallback') as unknown as Record<string, unknown>[];
  const worldmap = loadJson('worldmap') as unknown as Record<string, unknown>[];
  const balance = loadJson('balance') as unknown as Record<string, unknown>;
  const items = loadJson('items') as unknown as Record<string, unknown>[];
  const uiStrings = loadJson('ui_strings') as unknown as Record<string, string>;

  gameManager.loadBalance(balance, uiStrings);
  knowledgeTip.loadFrom(tips);
  recipeDB.loadFrom(substances, recipes, failMessages, items, tips);
  worldMap.loadFrom(worldmap);
  mentorRouter.loadFrom(mentors);
  qaFallback.loadFrom(qa);
  llmClient.loadMentors(mentors);
  llmClient.setQaFallback(qa);
  itemEffects.loadFrom(items);
  hydrogenEvent.loadQaKeywords(qa);
}

export function resetState(): void {
  eventBus.clear();
  gameManager.resetStats();
  gameManager.resetClock();
  gameManager.setZone('grassland');
  gameManager.setFlag('explosion_happened', false);
  gameManager.setFlag('purity_check_unlocked', false);
  recipeDB.resetRotation();
  recipeDB.resetUnlocked();
  knowledgeTip.clearQueue();
  knowledgeTip.resetShown();
}
