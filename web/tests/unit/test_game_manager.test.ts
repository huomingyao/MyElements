import { describe, it, expect, beforeEach } from 'vitest';
import { gameManager } from '../../src/core/game_manager';
import { knowledgeTip } from '../../src/core/knowledge_tip';
import { eventBus } from '../../src/core/event_bus';
import { injectAllData, resetState } from '../helpers';

beforeEach(() => {
  injectAllData();
  resetState();
});

describe('UT-C02 三值系统', () => {
  it('上限 100 初始 100', () => {
    expect(gameManager.oxygenMax).toBe(100);
    expect(gameManager.energyMax).toBe(100);
    expect(gameManager.healthMax).toBe(100);
    expect(gameManager.oxygen).toBe(100);
    expect(gameManager.health).toBe(100);
  });

  it('数值变化经事件总线发出，载荷正确', () => {
    const events: { current: number; max: number }[] = [];
    eventBus.on('oxygen_changed', p => events.push(p));
    gameManager.modifyOxygen(-10);
    expect(events.length).toBe(1);
    expect(events[0]).toEqual({ current: 90, max: 100 });
  });

  it('氧气归零后生命按 5/s 下降（矿洞无回复环境）', () => {
    gameManager.setZone('mine');
    gameManager.modifyOxygen(-100);
    const hpBefore = gameManager.health;
    gameManager.tick(2);
    expect(gameManager.health).toBeCloseTo(hpBefore - 10, 1);
  });

  it('能量归零移动速度倍率 0.5', () => {
    expect(gameManager.moveSpeedMultiplier()).toBe(1);
    gameManager.modifyEnergy(-100);
    expect(gameManager.moveSpeedMultiplier()).toBe(0.5);
  });

  it('生命归零只发一次 player_died（同帧多次伤害不重复）', () => {
    let deaths = 0;
    eventBus.on('player_died', () => deaths += 1);
    gameManager.modifyHealth(-100);
    gameManager.modifyHealth(-50);
    gameManager.modifyHealth(-10);
    expect(deaths).toBe(1);
    expect(gameManager.isDead()).toBe(true);
  });
});

describe('UT-C03 区域与分区消耗', () => {
  it('setZone 去重：同区域重复设置不发事件', () => {
    let changes = 0;
    eventBus.on('zone_changed', () => changes += 1);
    gameManager.setZone('mine');
    gameManager.setZone('mine');
    gameManager.setZone('mine');
    expect(changes).toBe(1);
    expect(gameManager.currentZone()).toBe('mine');
  });

  it('五区域氧气净速率与 balance 一致', () => {
    const cases: [string, number][] = [
      ['grassland', 0.5], ['camp', 0.5], ['saltlake', 0], ['mine', -2.0], ['academy', 0],
    ];
    for (const [zone, expected] of cases) {
      gameManager.setZone(zone);
      expect(gameManager.oxygenNetRate()).toBeCloseTo(expected, 3);
    }
  });

  it('矿洞氧气 60 秒掉 120（封顶 0）', () => {
    gameManager.setZone('mine');
    gameManager.tick(30);
    expect(gameManager.oxygen).toBeCloseTo(40, 1);
  });
});

describe('UT-C04 昼夜循环', () => {
  it('推进 360s 进夜、再 180s 回昼，事件各一次', () => {
    let nights = 0;
    let days = 0;
    let respawns = 0;
    eventBus.on('night_started', () => nights += 1);
    eventBus.on('day_started', () => days += 1);
    eventBus.on('resources_respawned', () => respawns += 1);
    expect(gameManager.isNight()).toBe(false);
    gameManager.tick(361);
    expect(gameManager.isNight()).toBe(true);
    expect(nights).toBe(1);
    gameManager.tick(181);
    expect(gameManager.isNight()).toBe(false);
    expect(days).toBe(1);
    expect(respawns).toBe(1);
    expect(gameManager.dayCount).toBe(2);
  });

  it('睡觉跳夜：清晨、生命满、天数 +1', () => {
    gameManager.tick(400); // 进入夜晚
    gameManager.modifyHealth(-40);
    gameManager.sleepUntilMorning();
    expect(gameManager.isNight()).toBe(false);
    expect(gameManager.dayCount).toBe(2);
    expect(gameManager.health).toBe(100);
  });

  it('死亡复活：三值回满并回到第一天白天刚开始', () => {
    gameManager.tick(700); // 第 2 天夜晚
    expect(gameManager.dayCount).toBe(2);
    gameManager.modifyHealth(-999);
    expect(gameManager.isDead()).toBe(true);
    gameManager.respawnPlayer();
    expect(gameManager.isDead()).toBe(false);
    expect(gameManager.health).toBe(100);
    expect(gameManager.oxygen).toBe(100);
    expect(gameManager.dayCount).toBe(1); // 回到第一天
    expect(gameManager.timeOfDay).toBe(0); // 白天刚开始
    expect(gameManager.isNight()).toBe(false);
  });
});

describe('UT-D08 balance 读取', () => {
  it('缺键返回默认值不崩溃', () => {
    expect(gameManager.getBalance('nonexistent.key', 42)).toBe(42);
    expect(gameManager.getBalance('stats.oxygen_max', 0)).toBe(100);
  });

  it('debug.* 默认 false', () => {
    expect(gameManager.bool('debug.force_purity_unlock')).toBe(false);
    expect(gameManager.bool('debug.fast_daynight')).toBe(false);
  });

  it('ui_strings 缺 key 返回 key 本身不崩溃', () => {
    expect(gameManager.getUiString('no_such_key')).toBe('no_such_key');
    expect(gameManager.getUiString('menu_start')).toBe('开始冒险');
  });
});

describe('UT-U01 字幕引擎', () => {
  it('三种 style 时长正确', () => {
    knowledgeTip.show('tip_o2'); // bubble 3s
    expect(knowledgeTip.currentStyle()).toBe('bubble');
    knowledgeTip.advance(3.1);
    knowledgeTip.show('zone_grass'); // banner 4s
    expect(knowledgeTip.currentStyle()).toBe('banner');
    knowledgeTip.advance(4.1);
    knowledgeTip.show('warn_co'); // warning 5s
    expect(knowledgeTip.currentStyle()).toBe('warning');
  });

  it('不存在的 id 不崩溃', () => {
    knowledgeTip.show('no_such_tip');
    expect(knowledgeTip.currentTipId()).toBe('');
  });

  it('队列串行不重叠', () => {
    knowledgeTip.show('zone_grass');
    knowledgeTip.show('zone_camp');
    expect(knowledgeTip.currentTipId()).toBe('zone_grass');
    knowledgeTip.advance(4.1);
    expect(knowledgeTip.currentTipId()).toBe('zone_camp');
  });

  it('warning 打断在播字幕，被打断 once 可再触发', () => {
    knowledgeTip.showOnce('zone_grass');
    expect(knowledgeTip.currentTipId()).toBe('zone_grass');
    knowledgeTip.show('warn_co'); // warning 抢占
    expect(knowledgeTip.currentTipId()).toBe('warn_co');
    // 被打断的 once 字幕已撤销记录
    expect(knowledgeTip.isShown('zone_grass')).toBe(false);
  });

  it('showOnce 只显示一次', () => {
    knowledgeTip.showOnce('tip_o2');
    knowledgeTip.advance(3.1);
    knowledgeTip.showOnce('tip_o2');
    expect(knowledgeTip.currentTipId()).toBe('');
    expect(knowledgeTip.isShown('tip_o2')).toBe(true);
  });

  it('tip 事件发射', () => {
    const shown: string[] = [];
    const finished: string[] = [];
    eventBus.on('tip_shown', p => shown.push(p.tipId));
    eventBus.on('tip_finished', p => finished.push(p.tipId));
    knowledgeTip.show('zone_grass');
    knowledgeTip.advance(4.1);
    expect(shown).toEqual(['zone_grass']);
    expect(finished).toEqual(['zone_grass']);
  });
});
