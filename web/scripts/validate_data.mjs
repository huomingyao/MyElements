// 数据校验器（FR-D-07）：10 类检查，全过打印 DATA OK 退出码 0
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dataDir = join(root, 'data');
const errors = [];

function loadJson(name) {
  try {
    return JSON.parse(readFileSync(join(dataDir, name), 'utf-8'));
  } catch (e) {
    errors.push(`${name}: JSON 解析失败 ${e.message}`);
    return null;
  }
}

const substances = loadJson('substances.json');
const recipes = loadJson('recipes.json');
const failMessages = loadJson('fail_messages.json');
const tips = loadJson('tips.json');
const mentors = loadJson('mentors.json');
const qa = loadJson('qa_fallback.json');
const worldmap = loadJson('worldmap.json');
const balance = loadJson('balance.json');
const items = loadJson('items.json');
const uiStrings = loadJson('ui_strings.json');

function checkUnique(rows, table) {
  if (!Array.isArray(rows)) return;
  const seen = new Set();
  for (const r of rows) {
    if (!r.id) { errors.push(`${table}: 存在缺 id 的行`); continue; }
    if (seen.has(r.id)) errors.push(`${table}: id 重复 ${r.id}`);
    seen.add(r.id);
  }
}

function checkNonEmpty(rows, table, fields) {
  if (!Array.isArray(rows)) return;
  for (const r of rows) {
    for (const f of fields) {
      const v = r[f];
      if (v === undefined || v === null || v === '') {
        errors.push(`${table}: ${r.id} 字段 ${f} 为空`);
      }
    }
  }
}

function checkEnum(rows, table, field, allowed) {
  if (!Array.isArray(rows)) return;
  for (const r of rows) {
    if (!allowed.includes(r[field])) {
      errors.push(`${table}: ${r.id} 字段 ${field}=${r[field]} 不在枚举 ${allowed.join('/')}`);
    }
  }
}

// 1-3 可解析（loadJson 已报）+ id 唯一
for (const [t, rows] of [['substances', substances], ['recipes', recipes], ['fail_messages', failMessages],
  ['tips', tips], ['mentors', mentors], ['qa_fallback', qa], ['worldmap', worldmap], ['items', items]]) {
  checkUnique(rows, t);
}

// 必填字段
checkNonEmpty(substances, 'substances', ['name', 'formula', 'category', 'tip_id', 'icon', 'codex_line']);
checkNonEmpty(recipes, 'recipes', ['inputs', 'tool', 'condition', 'outputs', 'equation', 'card_title', 'card_body', 'card_application']);
checkNonEmpty(tips, 'tips', ['text']);
checkNonEmpty(mentors, 'mentors', ['name', 'title', 'room', 'avatar_idle', 'avatar_talk', 'sprite', 'route_class', 'mention', 'system_prompt']);
checkNonEmpty(qa, 'qa_fallback', ['answer']);
checkNonEmpty(items, 'items', ['name', 'type', 'icon', 'effect']);

// 4 枚举
checkEnum(substances, 'substances', 'category', ['单质', '化合物', '氧化物', '酸', '碱', '盐']);
checkEnum(tips, 'tips', 'style', ['bubble', 'banner', 'warning']);
checkEnum(recipes, 'recipes', 'tool', ['portable', 'alcohol_lamp', 'bench', 'electrolyzer', 'filter']);
checkEnum(recipes, 'recipes', 'condition', ['none', 'ignite', 'heat', 'electrify', 'catalyst', 'low_oxygen', 'three_step']);
checkEnum(items, 'items', 'type', ['equip', 'consume', 'material']);
checkEnum(items, 'items', 'effect', ['light', 'kill_co', 'kill_acid', 'immune_co', 'extinguish', 'restore_oxygen', 'restore_energy', 'test_hardwater', 'none']);
checkEnum(failMessages, 'fail_messages', 'reason', ['no_match', 'wrong_condition']);

// 5 交叉引用
const tipIds = new Set((tips || []).map(t => t.id));
for (const s of substances || []) {
  if (!tipIds.has(s.tip_id)) errors.push(`substances: ${s.id} 的 tip_id=${s.tip_id} 不在 tips 表`);
}
const subIds = new Set((substances || []).map(s => s.id));
const itemIds = new Set((items || []).map(i => i.id));
const resolvable = new Set([...subIds, ...itemIds]);
for (const r of recipes || []) {
  for (const id of [...(r.inputs || []), ...(r.outputs || [])]) {
    if (!resolvable.has(id)) errors.push(`recipes: ${r.id} 引用未知 id=${id}`);
  }
  if (r.unlock_tip && !tipIds.has(r.unlock_tip)) errors.push(`recipes: ${r.id} 的 unlock_tip=${r.unlock_tip} 不在 tips 表`);
}

// 6 资源路径存在
function assetExists(p) {
  if (typeof p !== 'string' || !p) return true;
  const rel = p.replace(/^res:\/\//, '');
  return existsSync(join(root, 'public', rel));
}
for (const s of substances || []) if (!assetExists(s.icon)) errors.push(`substances: ${s.id} 图标缺失 ${s.icon}`);
for (const it of items || []) if (!assetExists(it.icon)) errors.push(`items: ${it.id} 图标缺失 ${it.icon}`);
for (const m of mentors || []) {
  for (const f of ['avatar_idle', 'avatar_talk', 'sprite']) {
    if (!assetExists(m[f])) errors.push(`mentors: ${m.id} 资源缺失 ${m[f]}`);
  }
}

// 7 条数约束
if (Array.isArray(substances)) {
  if (substances.length !== 17) errors.push(`substances: 期望 17 条，实际 ${substances.length}`);
  const hud = substances.filter(s => s.count_in_hud !== false);
  if (hud.length !== 16) errors.push(`substances: HUD 计数集合期望 16，实际 ${hud.length}`);
}
if (Array.isArray(recipes) && recipes.length !== 12) errors.push(`recipes: 期望 12 条，实际 ${recipes.length}`);
if (Array.isArray(recipes)) {
  const pure = recipes.filter(r => r.requires_pure_check === true);
  if (pure.length !== 1) errors.push(`recipes: requires_pure_check 应恰好 1 条，实际 ${pure.length}`);
}
if (Array.isArray(mentors) && mentors.length !== 4) errors.push(`mentors: 期望 4 条，实际 ${mentors.length}`);
if (Array.isArray(worldmap)) {
  if (worldmap.length !== 13) errors.push(`worldmap: 期望 13 条，实际 ${worldmap.length}`);
  const un = worldmap.filter(z => z.unlocked === true);
  if (un.length !== 5) errors.push(`worldmap: 解锁区期望 5，实际 ${un.length}`);
  for (const z of worldmap) {
    if (z.unlocked && !z.brief) errors.push(`worldmap: ${z.id} 解锁但 brief 为空`);
    if (!z.unlocked && !z.teaser) errors.push(`worldmap: ${z.id} 未解锁但 teaser 为空`);
    const hs = z.hotspot || {};
    if (hs.x < 0 || hs.y < 0 || hs.x + hs.w > 640 || hs.y + hs.h > 360) {
      errors.push(`worldmap: ${z.id} 热区越界`);
    }
  }
}
if (Array.isArray(qa)) {
  if (qa.length < 20) errors.push(`qa_fallback: 期望 >=20 条，实际 ${qa.length}`);
  const emptyKw = qa.filter(r => Array.isArray(r.keywords) && r.keywords.length === 0);
  if (emptyKw.length !== 1) errors.push(`qa_fallback: 兜底行（keywords 空）应恰好 1 行，实际 ${emptyKw.length}`);
  for (const r of qa) {
    if (!Array.isArray(r.keywords)) { errors.push(`qa_fallback: ${r.id} keywords 缺失`); continue; }
    if (r.keywords.length > 0 && r.keywords.some(k => !k)) errors.push(`qa_fallback: ${r.id} 含空关键词`);
  }
}
if (Array.isArray(failMessages)) {
  for (const reason of ['no_match', 'wrong_condition']) {
    const pool = failMessages.filter(f => f.reason === reason);
    if (pool.length < 2) errors.push(`fail_messages: ${reason} 池至少 2 条，实际 ${pool.length}`);
  }
}

// 8 配方三元组无歧义
if (Array.isArray(recipes)) {
  const sigs = new Map();
  for (const r of recipes) {
    const sig = `${[...(r.inputs || [])].sort().join(',')}|${r.tool}|${r.condition}`;
    if (sigs.has(sig)) errors.push(`recipes: 三元组歧义 ${sigs.get(sig)} 与 ${r.id}`);
    sigs.set(sig, r.id);
  }
}

// 9 导师 prompt 与 dispatch 约束
if (Array.isArray(mentors)) {
  const ids = new Set(mentors.map(m => m.id));
  for (const need of ['chem', 'monitor', 'assistant', 'think']) {
    if (!ids.has(need)) errors.push(`mentors: 缺少 ${need}`);
  }
  const monitor = mentors.find(m => m.id === 'monitor');
  if (monitor) {
    for (const kw of ['@化学老师', '@思维老师', '@助理']) {
      if (!monitor.system_prompt.includes(kw)) errors.push(`mentors: monitor prompt 缺调度关键字 ${kw}`);
    }
    const dispatch = monitor.dispatch;
    if (!Array.isArray(dispatch) || dispatch.length !== 4) {
      errors.push('mentors: monitor.dispatch 应恰好 4 项');
    } else {
      const order = ['combat', 'learning', 'chemistry', 'other'];
      dispatch.forEach((d, i) => {
        if (d.category !== order[i]) errors.push(`mentors: dispatch[${i}] category 应为 ${order[i]}，实际 ${d.category}`);
        if (!Array.isArray(d.targets) || d.targets.length < 1 || d.targets.length > 2) {
          errors.push(`mentors: dispatch ${d.category} targets 数量非法`);
        }
        for (const t of d.targets || []) {
          if (!ids.has(t) || t === 'monitor') errors.push(`mentors: dispatch ${d.category} 非法 target ${t}`);
          const tm = mentors.find(m => m.id === t);
          if (tm && !(d.line || '').includes('@' + tm.mention)) {
            errors.push(`mentors: dispatch ${d.category} line 缺 @${tm.mention}`);
          }
        }
        if (d.category === 'learning' && (d.targets || []).length !== 2) {
          errors.push('mentors: learning 应恰好 2 个 target');
        }
        if (d.category !== 'other' && (!Array.isArray(d.keywords) || d.keywords.length === 0)) {
          errors.push(`mentors: dispatch ${d.category} keywords 为空`);
        }
        if (d.category === 'other' && Array.isArray(d.keywords) && d.keywords.length !== 0) {
          errors.push('mentors: other.keywords 应为空数组');
        }
        if (!d.line) errors.push(`mentors: dispatch ${d.category} line 为空`);
      });
    }
  }
  const mentions = new Set();
  for (const m of mentors) {
    if (!m.mention || m.mention.startsWith('@')) errors.push(`mentors: ${m.id} mention 非法 ${m.mention}`);
    if (mentions.has(m.mention)) errors.push(`mentors: mention 重复 ${m.mention}`);
    mentions.add(m.mention);
    if (m.id !== 'monitor' && !m.system_prompt.includes('绝不出现 @')) {
      errors.push(`mentors: ${m.id} prompt 缺"绝不出现 @"约束`);
    }
    if (m.id !== 'monitor' && m.dispatch) errors.push(`mentors: ${m.id} 不应有 dispatch`);
  }
}

// 10 ui_strings key 覆盖
const UI_KEYS = ['prompt_interact', 'prompt_ask', 'menu_start', 'menu_academy', 'menu_codex', 'menu_quit',
  'craft_react', 'craft_purity', 'craft_ignite', 'codex_locked', 'map_locked_badge', 'chat_placeholder',
  'chat_offline_badge', 'collected_counter', 'death_title', 'death_info', 'death_day', 'death_hint',
  'config_note', 'hud_day', 'hud_night', 'pause_title', 'pause_continue', 'pause_to_menu', 'menu_map',
  'chat_send', 'chat_close', 'chat_config', 'config_apply', 'craft_title', 'craft_tool_portable',
  'craft_tool_lamp', 'craft_tool_bench', 'craft_tool_electrolyzer', 'craft_tool_filter', 'craft_cancel',
  'craft_slot_empty', 'craft_hint_with', 'craft_hint_at', 'craft_hint_make', 'craft_hint_none',
  'cond_ignite', 'cond_heat', 'cond_none', 'cond_low_oxygen', 'cond_electrify', 'cond_three_step',
  'cond_catalyst', 'item_usable_energy', 'inventory_title'];
if (uiStrings) {
  for (const k of UI_KEYS) {
    if (!uiStrings[k]) errors.push(`ui_strings: 缺 key ${k}`);
  }
  for (const [k, v] of Object.entries(uiStrings)) {
    if (!v) errors.push(`ui_strings: ${k} 为空`);
    const ph = String(v).match(/\{[^}]*\}/g) || [];
    for (const p of ph) if (p !== '{n}') errors.push(`ui_strings: ${k} 非法占位符 ${p}`);
  }
}

// balance.json 键覆盖（§2.4 每个参数）
const BALANCE_KEYS = ['stats.oxygen_max', 'stats.energy_max', 'stats.health_max', 'stats.oxygen_drain',
  'stats.oxygen_regen_safe', 'stats.energy_drain', 'stats.health_regen_campfire', 'stats.oxygen_zero_health_drain',
  'stats.low_energy_speed_multiplier', 'stats.hud_low_oxygen_threshold', 'stats.tutorial_oxygen_hint_at',
  'daynight.day_duration', 'daynight.night_duration', 'daynight.night_brightness', 'daynight.dark_view_radius',
  'daynight.torch_view_radius', 'damage.co_ghost_per_second', 'damage.acid_mist_per_hit',
  'damage.hydrogen_explosion', 'damage.cuso4_pool_per_second', 'player.move_speed', 'player.jump_velocity',
  'player.gravity', 'player.interact_radius', 'monsters.co_ghost_speed', 'monsters.acid_mist_speed',
  'monsters.acid_mist_night_count_min', 'monsters.acid_mist_night_count_max', 'monsters.acid_mist_lifetime_seconds',
  'items.oxygen_tank_restore', 'items.trade_energy_restore', 'items.campfire_meal_restore',
  'items.campfire_daily_limit', 'inventory.hotbar_slots', 'inventory.stack_limit',
  'llm.timeout_seconds', 'llm.retry_count', 'llm.history_rounds', 'llm.max_tokens', 'llm.temperature',
  'llm.input_max_chars', 'debug.force_purity_unlock', 'debug.fast_daynight'];
if (balance) {
  for (const k of BALANCE_KEYS) {
    const parts = k.split('.');
    let cur = balance;
    for (const p of parts) cur = cur == null ? undefined : cur[p];
    if (cur === undefined) errors.push(`balance: 缺键 ${k}`);
  }
}
// items.effect_value_key 可解析
if (balance && Array.isArray(items)) {
  for (const it of items) {
    if (it.effect_value_key) {
      const parts = it.effect_value_key.split('.');
      let cur = balance;
      for (const p of parts) cur = cur == null ? undefined : cur[p];
      if (cur === undefined) errors.push(`items: ${it.id} 的 effect_value_key=${it.effect_value_key} 在 balance 中不可解析`);
    }
  }
}

if (errors.length > 0) {
  console.error('DATA ERRORS:');
  for (const e of errors) console.error('  - ' + e);
  process.exit(1);
}
console.log('DATA OK');
process.exit(0);
