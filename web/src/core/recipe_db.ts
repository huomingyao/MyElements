// RecipeDB：物质表 / 配方表 / 失败文案池的查询与匹配（§3.4，冻结面）
import type { Row } from './data_loader';
import { gameManager } from './game_manager';

export interface CraftResult {
  success: boolean;
  recipe_id: string;
  outputs: string[];
  card: { title: string; equation: string; body: string; application: string; footer: string } | Record<string, never>;
  fail_reason: '' | 'no_match' | 'wrong_condition' | 'needs_purity_check';
  fail_tip_id: string;
  requires_pure_check: boolean;
}

const EMPTY_RESULT: CraftResult = {
  success: false, recipe_id: '', outputs: [], card: {},
  fail_reason: '', fail_tip_id: '', requires_pure_check: false,
};

export class RecipeDB {
  private substances: Row[] = [];
  private recipes: Row[] = [];
  private failMessages: Row[] = [];
  private substanceById = new Map<string, Row>();
  private itemIds = new Set<string>();
  private unlocked = new Set<string>();
  private rotation: Record<string, number> = { no_match: 0, wrong_condition: 0 };
  private cardFooter = '反应前后原子种类和数目不变——质量守恒定律';

  loadFrom(substances: Row[], recipes: Row[], failMessages: Row[], items: Row[], tips: Row[]): void {
    this.substances = substances || [];
    this.recipes = recipes || [];
    this.failMessages = failMessages || [];
    this.substanceById.clear();
    for (const s of this.substances) this.substanceById.set(String(s.id), s);
    this.itemIds = new Set((items || []).map(i => String(i.id)));
    const footer = (tips || []).find(t => t.id === 'card_footer');
    if (footer) this.cardFooter = String(footer.text);
  }

  reload(substances: Row[], recipes: Row[], failMessages: Row[], items: Row[], tips: Row[]): void {
    this.loadFrom(substances, recipes, failMessages, items, tips);
  }

  getSubstance(id: string): Row {
    return this.substanceById.get(id) ?? {};
  }

  allSubstances(): Row[] {
    return this.substances;
  }

  allRecipes(): Row[] {
    return this.recipes;
  }

  allFailMessages(): Row[] {
    return this.failMessages;
  }

  getRecipe(id: string): Row {
    return this.recipes.find(r => r.id === id) ?? {};
  }

  isItem(id: string): boolean {
    return this.itemIds.has(id);
  }

  tryCraft(items: string[], tool: string, condition: string): CraftResult {
    const sortedInputs = [...items].sort();
    // 材料匹配（顺序无关）
    const materialMatched = this.recipes.filter(r => {
      const ri = [...(r.inputs as string[])].sort();
      return ri.length === sortedInputs.length && ri.every((v, i) => v === sortedInputs[i]);
    });
    if (materialMatched.length === 0) {
      return {
        ...EMPTY_RESULT,
        fail_reason: 'no_match',
        fail_tip_id: this.nextFailId('no_match', sortedInputs),
      };
    }
    // 条件/器材匹配
    const fullMatched = materialMatched.filter(r => r.tool === tool && r.condition === condition);
    if (fullMatched.length === 0) {
      return {
        ...EMPTY_RESULT,
        fail_reason: 'wrong_condition',
        fail_tip_id: this.nextFailId('wrong_condition', sortedInputs),
      };
    }
    const recipe = fullMatched[0];
    // 验纯检查（R4）
    if (recipe.requires_pure_check === true && !gameManager.getFlag('purity_check_unlocked') && !gameManager.bool('debug.force_purity_unlock')) {
      return {
        ...EMPTY_RESULT,
        fail_reason: 'needs_purity_check',
        fail_tip_id: '',
        requires_pure_check: true,
        recipe_id: String(recipe.id),
      };
    }
    this.markUnlock(String(recipe.id));
    return {
      success: true,
      recipe_id: String(recipe.id),
      outputs: [...(recipe.outputs as string[])],
      card: this.buildCard(recipe),
      fail_reason: '',
      fail_tip_id: '',
      requires_pure_check: recipe.requires_pure_check === true,
    };
  }

  buildCard(recipe: Row): CraftResult['card'] {
    return {
      title: String(recipe.card_title ?? ''),
      equation: String(recipe.equation ?? ''),
      body: String(recipe.card_body ?? ''),
      application: String(recipe.card_application ?? ''),
      footer: this.cardFooter,
    };
  }

  private nextFailId(reason: 'no_match' | 'wrong_condition', inputs: string[]): string {
    // 彩蛋：铜+酸类组合
    if (reason === 'no_match' && inputs.includes('cu') && inputs.some(i => ['hcl'].includes(i))) {
      return 'fail_copper_acid';
    }
    const pool = this.failMessages.filter(f => f.reason === reason && f.id !== 'fail_copper_acid');
    if (pool.length === 0) return '';
    const idx = this.rotation[reason] % pool.length;
    this.rotation[reason] += 1;
    return String(pool[idx].id);
  }

  getFailMessage(failId: string): { id: string; reason: string; text: string } | Record<string, never> {
    const row = this.failMessages.find(f => f.id === failId);
    if (!row) return {};
    return { id: String(row.id), reason: String(row.reason), text: String(row.text) };
  }

  unlockedRecipes(): string[] {
    return [...this.unlocked];
  }

  markUnlock(recipeId: string): void {
    this.unlocked.add(recipeId);
  }

  resetUnlocked(): void {
    this.unlocked.clear();
  }

  restoreUnlocked(ids: string[]): void {
    this.unlocked = new Set(ids);
  }

  resetRotation(): void {
    this.rotation = { no_match: 0, wrong_condition: 0 };
  }
}

export const recipeDB = new RecipeDB();
