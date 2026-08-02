import { describe, it, expect, beforeEach } from 'vitest';
import { llmClient } from '../../src/core/llm_client';
import { gameManager } from '../../src/core/game_manager';
import { injectAllData, resetState } from '../helpers';

beforeEach(() => {
  injectAllData();
  resetState();
  llmClient.setOffline(false);
  llmClient.setApiKey('test-key-for-unit-test');
  llmClient.setTimeoutSeconds(0.05);
  llmClient.setRetryCount(1);
});

describe('UT-M08 超时与兜底切换', () => {
  it('网络失败走兜底且带（离线模式），不抛异常', async () => {
    llmClient.setTransport(async () => ({ result: -1, code: 0, body: '' }));
    const reply = await llmClient.ask('chem', '为什么氢气会爆炸', []);
    expect(reply).toContain('（离线模式）');
  });

  it('超时走兜底', async () => {
    llmClient.setTransport(async () => ({ result: -2, code: 0, body: '' }));
    const reply = await llmClient.ask('chem', '氢气爆炸', []);
    expect(reply).toContain('（离线模式）');
  });

  it('非 200 走兜底', async () => {
    llmClient.setTransport(async () => ({ result: 0, code: 500, body: '{}' }));
    const reply = await llmClient.ask('chem', '氢气爆炸', []);
    expect(reply).toContain('（离线模式）');
  });

  it('畸形 body 走兜底', async () => {
    llmClient.setTransport(async () => ({ result: 0, code: 200, body: 'not-json{{{' }));
    const reply = await llmClient.ask('chem', '氢气爆炸', []);
    expect(reply).toContain('（离线模式）');
  });

  it('重试 1 次共 2 次发包', async () => {
    let attempts = 0;
    llmClient.setTransport(async () => {
      attempts += 1;
      return { result: -1, code: 0, body: '' };
    });
    await llmClient.ask('chem', '氢气', []);
    expect(attempts).toBe(2);
    expect(llmClient.attemptCount()).toBe(2);
  });

  it('成功时返回正文且不带离线角标', async () => {
    llmClient.setTransport(async () => ({
      result: 0, code: 200,
      body: JSON.stringify({ choices: [{ message: { content: '因为氢气不纯。2H₂+O₂=点燃=2H₂O' } }] }),
    }));
    const reply = await llmClient.ask('chem', '氢气为什么爆炸', []);
    expect(reply).toContain('2H₂+O₂');
    expect(reply).not.toContain('（离线模式）');
  });

  it('手动离线开关立即生效', async () => {
    llmClient.setOffline(true);
    let called = false;
    llmClient.setTransport(async () => {
      called = true;
      return { result: 0, code: 200, body: '{}' };
    });
    const reply = await llmClient.ask('chem', '氢气爆炸', []);
    expect(called).toBe(false);
    expect(reply).toContain('（离线模式）');
    expect(llmClient.isOffline()).toBe(true);
  });
});

describe('IT-M07 请求体结构', () => {
  it('包含 system+user、max_tokens≈300、temperature=0.7', () => {
    const body = llmClient.buildRequestBody('chem', '氢气为什么爆炸', []) as {
      model: string;
      messages: { role: string; content: string }[];
      max_tokens: number;
      temperature: number;
    };
    expect(body.model).toBe('deepseek-chat');
    expect(body.max_tokens).toBe(300);
    expect(body.temperature).toBe(0.7);
    expect(body.messages[0].role).toBe('system');
    expect(body.messages[0].content).toContain('袁仲衡');
    expect(body.messages[0].content).toContain('元素炼金物语'); // 通用后缀
    expect(body.messages[body.messages.length - 1]).toEqual({ role: 'user', content: '氢气为什么爆炸' });
  });

  it('历史只带最近 4 轮', () => {
    const history = Array.from({ length: 10 }, (_, i) => ({ question: `q${i}`, answer: `a${i}` }));
    const body = llmClient.buildRequestBody('chem', 'q_new', history) as {
      messages: { role: string; content: string }[];
    };
    // system + 4 轮 × 2 + 当前 user = 10
    expect(body.messages.length).toBe(10);
    expect(body.messages[body.messages.length - 1].content).toBe('q_new');
    expect(body.messages[1].content).toBe('q6'); // 最近 4 轮从 q6 开始
  });
});

describe('UT-G12 道具效果', () => {
  it('氧气瓶 +50 氧气', async () => {
    const { itemEffects } = await import('../../src/gameplay/item_effects');
    gameManager.modifyOxygen(-80);
    itemEffects.useItem('oxygen_tank');
    expect(gameManager.oxygen).toBe(70); // -80 + 50
  });

  it('装备型使用不消耗（effect=light 返回 false）', async () => {
    const { itemEffects } = await import('../../src/gameplay/item_effects');
    const consumed = itemEffects.useItem('sulfur_torch');
    expect(consumed).toBe(false);
    expect(itemEffects.isEquipped('sulfur_torch')).toBe(true);
    itemEffects.useItem('sulfur_torch');
    expect(itemEffects.isEquipped('sulfur_torch')).toBe(false);
  });

  it('效果值读自 balance（effect_value_key）', async () => {
    const { itemEffects } = await import('../../src/gameplay/item_effects');
    expect(itemEffects.effectValue('oxygen_tank')).toBe(50);
    expect(itemEffects.effectValue('sulfur_torch')).toBe(220);
  });
});

describe('UT-G03 首次收集统计', () => {
  it('重复拾取只计一次；计数集合 16（co2 不计入）', async () => {
    const { discovery } = await import('../../src/gameplay/discovery');
    discovery.reset();
    expect(discovery.discover('o2')).toBe(true);
    expect(discovery.discover('o2')).toBe(false);
    expect(discovery.discoveredCount).toBe(1);
    discovery.discover('co2');
    expect(discovery.discoveredCount).toBe(1); // co2 不计入 HUD 计数
    expect(discovery.countTotal).toBe(16);
    expect(discovery.isDiscovered('co2')).toBe(true);
  });
});

describe('氢气爆炸事件', () => {
  it('爆炸精确 -50 并置标记', async () => {
    const { hydrogenEvent } = await import('../../src/gameplay/hydrogen_event');
    gameManager.resetStats();
    hydrogenEvent.ignite();
    expect(gameManager.health).toBe(50);
    expect(gameManager.getFlag('explosion_happened')).toBe(true);
  });

  it('生命不足 50 爆炸致死不卡死', async () => {
    const { hydrogenEvent } = await import('../../src/gameplay/hydrogen_event');
    gameManager.resetStats();
    gameManager.modifyHealth(-70); // 剩 30
    hydrogenEvent.ignite();
    expect(gameManager.health).toBe(0);
    expect(gameManager.isDead()).toBe(true);
  });

  it('验纯解锁后 doPurityCheck 成功', async () => {
    const { hydrogenEvent } = await import('../../src/gameplay/hydrogen_event');
    expect(hydrogenEvent.isPurityCheckAvailable()).toBe(false);
    expect(hydrogenEvent.doPurityCheck()).toBe(false);
    hydrogenEvent.unlockPurityCheck();
    expect(hydrogenEvent.isPurityCheckAvailable()).toBe(true);
    expect(hydrogenEvent.doPurityCheck()).toBe(true);
  });

  it('氢气问题关键词识别（读 qa_fallback，代码零中文关键词）', async () => {
    const { hydrogenEvent } = await import('../../src/gameplay/hydrogen_event');
    expect(hydrogenEvent.questionMentionsHydrogen('为什么氢气会爆炸')).toBe(true);
    expect(hydrogenEvent.questionMentionsHydrogen('今天天气怎么样')).toBe(false);
  });
});

describe('粗盐提纯三步状态机', () => {
  it('必须按顺序，跳步返回 false', async () => {
    const { saltPurifier } = await import('../../src/gameplay/salt_purifier');
    saltPurifier.reset();
    expect(saltPurifier.perform('filter')).toBe(false); // 跳步
    expect(saltPurifier.perform('dissolve')).toBe(true);
    expect(saltPurifier.perform('evaporate')).toBe(false); // 跳步
    expect(saltPurifier.perform('filter')).toBe(true);
    expect(saltPurifier.perform('evaporate')).toBe(true);
    expect(saltPurifier.isDone()).toBe(true);
  });
});
