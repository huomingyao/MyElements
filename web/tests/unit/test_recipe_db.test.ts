import { describe, it, expect, beforeEach } from 'vitest';
import { recipeDB } from '../../src/core/recipe_db';
import { gameManager } from '../../src/core/game_manager';
import { injectAllData, resetState } from '../helpers';

beforeEach(() => {
  injectAllData();
  resetState();
});

describe('UT-G04 配方引擎：12 条配方逐条正例', () => {
  const cases: [string, string[], string, string, string[]][] = [
    ['r_sulfur_torch', ['stick', 's'], 'portable', 'ignite', ['sulfur_torch']],
    ['r_carbon_burn', ['c'], 'alcohol_lamp', 'ignite', ['co2']],
    ['r_carbon_incomplete', ['c'], 'alcohol_lamp', 'low_oxygen', ['co']],
    ['r_electrolysis', ['h2o_clean'], 'electrolyzer', 'electrify', ['h2', 'o2']],
    ['r_neutralize', ['hcl', 'naoh'], 'bench', 'none', ['neutral_spray']],
    ['r_co2_lab', ['caco3', 'hcl'], 'bench', 'none', ['co2']],
    ['r_co2_test', ['co2', 'caoh2'], 'bench', 'none', ['caco3']],
    ['r_wet_copper', ['fe', 'cuso4'], 'bench', 'none', ['cu']],
    ['r_extinguisher', ['nahco3', 'hcl'], 'bench', 'none', ['extinguisher']],
    ['r_salt_purify', ['crude_salt'], 'bench', 'three_step', ['nacl']],
    ['r_carbon_activate', ['c'], 'alcohol_lamp', 'heat', ['activated_carbon']],
  ];

  for (const [rid, inputs, tool, condition, outputs] of cases) {
    it(`${rid} 正例成功`, () => {
      const r = recipeDB.tryCraft(inputs, tool, condition);
      expect(r.success).toBe(true);
      expect(r.recipe_id).toBe(rid);
      expect([...r.outputs].sort()).toEqual([...outputs].sort());
      expect(r.fail_reason).toBe('');
      expect(recipeDB.unlockedRecipes()).toContain(rid);
    });
  }

  it('R4 氢气验纯后成功', () => {
    gameManager.setFlag('purity_check_unlocked', true);
    const r = recipeDB.tryCraft(['h2', 'o2'], 'portable', 'ignite');
    expect(r.success).toBe(true);
    expect(r.recipe_id).toBe('r_hydrogen_burn');
  });

  it('R4 未验纯返回 needs_purity_check', () => {
    const r = recipeDB.tryCraft(['h2', 'o2'], 'portable', 'ignite');
    expect(r.success).toBe(false);
    expect(r.fail_reason).toBe('needs_purity_check');
    expect(r.requires_pure_check).toBe(true);
    expect(r.fail_tip_id).toBe('');
  });

  it('debug.force_purity_unlock 演示保险开关（默认关闭不生效）', () => {
    expect(gameManager.bool('debug.force_purity_unlock')).toBe(false);
  });
});

describe('UT-G04 匹配规则', () => {
  it('材料顺序不影响匹配', () => {
    const a = recipeDB.tryCraft(['s', 'stick'], 'portable', 'ignite');
    const b = recipeDB.tryCraft(['stick', 's'], 'portable', 'ignite');
    expect(a.success).toBe(b.success);
    expect(a.recipe_id).toBe(b.recipe_id);
  });

  it('材料对但器材不符 → wrong_condition', () => {
    const r = recipeDB.tryCraft(['stick', 's'], 'bench', 'ignite');
    expect(r.success).toBe(false);
    expect(r.fail_reason).toBe('wrong_condition');
    expect(r.fail_tip_id).toMatch(/^fail_/);
  });

  it('材料对但条件不符 → wrong_condition', () => {
    const r = recipeDB.tryCraft(['stick', 's'], 'portable', 'none');
    expect(r.success).toBe(false);
    expect(r.fail_reason).toBe('wrong_condition');
  });

  it('完全不匹配 → no_match', () => {
    const r = recipeDB.tryCraft(['o2', 'nacl'], 'portable', 'none');
    expect(r.success).toBe(false);
    expect(r.fail_reason).toBe('no_match');
  });

  it('返回结构字段齐全', () => {
    const r = recipeDB.tryCraft(['stick', 's'], 'portable', 'ignite');
    expect(r).toHaveProperty('success');
    expect(r).toHaveProperty('recipe_id');
    expect(r).toHaveProperty('outputs');
    expect(r).toHaveProperty('card');
    expect(r).toHaveProperty('fail_reason');
    expect(r).toHaveProperty('fail_tip_id');
    expect(r).toHaveProperty('requires_pure_check');
    const card = r.card as { title: string; equation: string; body: string; application: string; footer: string };
    expect(card.title).toBeTruthy();
    expect(card.equation).toContain('SO₂');
    expect(card.footer).toContain('质量守恒');
  });
});

describe('UT-G07 失败文案', () => {
  it('两个 reason 池绝不混用', () => {
    const nm = recipeDB.tryCraft(['o2', 'nacl'], 'portable', 'none');
    const wc = recipeDB.tryCraft(['stick', 's'], 'bench', 'none');
    const nmMsg = recipeDB.getFailMessage(nm.fail_tip_id);
    const wcMsg = recipeDB.getFailMessage(wc.fail_tip_id);
    expect('reason' in nmMsg && nmMsg.reason).toBe('no_match');
    expect('reason' in wcMsg && wcMsg.reason).toBe('wrong_condition');
  });

  it('连续两次同类失败文案不同（确定性轮转）', () => {
    const a = recipeDB.tryCraft(['o2', 'nacl'], 'portable', 'none');
    const b = recipeDB.tryCraft(['o2', 'nacl'], 'portable', 'none');
    expect(a.fail_tip_id).not.toBe(b.fail_tip_id);
    const c = recipeDB.tryCraft(['stick', 's'], 'bench', 'none');
    const d = recipeDB.tryCraft(['stick', 's'], 'bench', 'none');
    expect(c.fail_tip_id).not.toBe(d.fail_tip_id);
  });

  it('彩蛋：铜+酸触发 fail_copper_acid', () => {
    const r = recipeDB.tryCraft(['cu', 'hcl'], 'bench', 'none');
    expect(r.fail_reason).toBe('no_match');
    expect(r.fail_tip_id).toBe('fail_copper_acid');
  });

  it('彩蛋不参与通用轮转', () => {
    // 连续 8 次 no_match 不应出现彩蛋
    const ids = new Set<string>();
    for (let i = 0; i < 8; i++) {
      ids.add(recipeDB.tryCraft(['o2', 'nacl'], 'portable', 'none').fail_tip_id);
    }
    expect(ids.has('fail_copper_acid')).toBe(false);
  });
});
