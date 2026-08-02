// 把仓库根 data/*.json 同步进 public/data/（构建期单写者：仓库根 data/）
import { copyFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = join(root, 'data');
const dst = join(root, 'public', 'data');
mkdirSync(dst, { recursive: true });
for (const f of readdirSync(src)) {
  if (f.endsWith('.json')) {
    copyFileSync(join(src, f), join(dst, f));
  }
}
console.log('data synced -> public/data');
