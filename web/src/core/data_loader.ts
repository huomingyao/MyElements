// 数据加载层：统一 fetch 数据表，并把 res://assets/ 改写为 assets/ 相对 URL（§4.1）
export type Row = Record<string, unknown>;

const cache = new Map<string, unknown>();

export function rewriteAssetPaths<T>(value: T): T {
  if (typeof value === 'string') {
    if (value.startsWith('res://assets/')) return value.replace('res://assets/', 'assets/') as T;
    return value;
  }
  if (Array.isArray(value)) return value.map(rewriteAssetPaths) as T;
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) out[k] = rewriteAssetPaths(v);
    return out as T;
  }
  return value;
}

export class DataLoader {
  static async loadJson<T = unknown>(name: string): Promise<T> {
    if (cache.has(name)) return cache.get(name) as T;
    const resp = await fetch(`data/${name}.json`);
    if (!resp.ok) throw new Error(`DataLoader: 加载 ${name}.json 失败 HTTP ${resp.status}`);
    const json = rewriteAssetPaths(await resp.json()) as T;
    cache.set(name, json);
    return json;
  }

  static async loadAll(): Promise<{
    substances: Row[]; recipes: Row[]; failMessages: Row[]; tips: Row[];
    mentors: Row[]; qaFallback: Row[]; worldmap: Row[]; balance: Row;
    items: Row[]; uiStrings: Record<string, string>;
  }> {
    const [substances, recipes, failMessages, tips, mentors, qaFallback, worldmap, balance, items, uiStrings] =
      await Promise.all([
        DataLoader.loadJson<Row[]>('substances'),
        DataLoader.loadJson<Row[]>('recipes'),
        DataLoader.loadJson<Row[]>('fail_messages'),
        DataLoader.loadJson<Row[]>('tips'),
        DataLoader.loadJson<Row[]>('mentors'),
        DataLoader.loadJson<Row[]>('qa_fallback'),
        DataLoader.loadJson<Row[]>('worldmap'),
        DataLoader.loadJson<Row>('balance'),
        DataLoader.loadJson<Row[]>('items'),
        DataLoader.loadJson<Record<string, string>>('ui_strings'),
      ]);
    return { substances, recipes, failMessages, tips, mentors, qaFallback, worldmap, balance, items, uiStrings };
  }

  static injectForTest(name: string, data: unknown): void {
    cache.set(name, rewriteAssetPaths(data));
  }

  static clearCache(): void {
    cache.clear();
  }
}
