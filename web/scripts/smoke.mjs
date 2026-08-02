// 冒烟测试：驱动系统 Chrome 跑构建产物，全流程截图 + console 错误检查
import puppeteer from 'puppeteer-core';
import { createServer } from 'node:http';
import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const distDir = join(root, 'dist');
const shotsDir = join(root, 'scripts', '_shots');
mkdirSync(shotsDir, { recursive: true });

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.mp3': 'audio/mpeg' };

const server = createServer((req, res) => {
  let p = decodeURIComponent((req.url || '/').split('?')[0]);
  if (p === '/') p = '/index.html';
  const file = join(distDir, p);
  if (!existsSync(file)) {
    res.writeHead(404); res.end('nf');
    return;
  }
  res.writeHead(200, { 'Content-Type': MIME[extname(file)] || 'application/octet-stream' });
  res.end(readFileSync(file));
});

await new Promise(r => server.listen(8899, r));
console.log('server on 8899');

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--no-sandbox', '--disable-gpu-sandbox', '--window-size=1340,820', '--autoplay-policy=no-user-gesture-required'],
});

const page = await browser.newPage();
await page.setViewport({ width: 1320, height: 780 });

const errors = [];
const warnings = [];
page.on('console', msg => {
  const type = msg.type();
  if (type === 'error') errors.push(msg.text());
  if (type === 'warning') warnings.push(msg.text());
});
page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
page.on('requestfailed', r => errors.push('REQFAIL: ' + r.url()));

const shot = (name) => page.screenshot({ path: join(shotsDir, name + '.png') });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

try {
  await page.goto('http://localhost:8899/', { waitUntil: 'networkidle2', timeout: 30000 });
  await sleep(2500);
  await shot('01_menu');
  console.log('menu loaded');

  const btns = await page.$$('#main-menu .btn');
  console.log('menu buttons:', btns.length);
  if (btns.length < 5) throw new Error('主菜单按钮数量异常: ' + btns.length);

  // —— 任务1：主菜单打开图鉴 → 关闭 → 按键必须还在 ——
  await btns[2].click(); // 图鉴·背包
  await sleep(700);
  await shot('01b_menu_codex');
  await page.keyboard.press('Escape');
  await sleep(500);
  const btnsAfterCodex = await page.$$('#main-menu .btn');
  console.log('menu buttons after codex close:', btnsAfterCodex.length);
  if (btnsAfterCodex.length < 5) errors.push('BUG任务1: 关闭图鉴后主菜单按键丢失: ' + btnsAfterCodex.length);

  // —— 任务1：主菜单打开世界地图 → 关闭 → 按键必须还在 ——
  const btns2 = await page.$$('#main-menu .btn');
  await btns2[3].click(); // 世界地图
  await sleep(700);
  await shot('01c_menu_worldmap');
  // 已解锁区必须有图片素材填充
  const unlockedImgs = await page.$$eval('.map-zone.unlocked img', imgs => imgs.length);
  const unlockedZones = await page.$$eval('.map-zone.unlocked', zs => zs.length);
  console.log('worldmap unlocked zones:', unlockedZones, 'with imgs:', unlockedImgs);
  if (unlockedZones !== 5 || unlockedImgs !== 5) errors.push(`BUG任务1: 世界地图素材缺失 ${unlockedImgs}/${unlockedZones}`);
  await page.keyboard.press('Escape');
  await sleep(500);
  const btnsAfterMap = await page.$$('#main-menu .btn');
  console.log('menu buttons after worldmap close:', btnsAfterMap.length);
  if (btnsAfterMap.length < 5) errors.push('BUG任务1: 关闭地图后主菜单按键丢失: ' + btnsAfterMap.length);

  // 开始冒险
  const btns3 = await page.$$('#main-menu .btn');
  await btns3[0].click();
  await sleep(2000);
  await shot('02_world_grassland');

  // 移动 + 跳跃
  await page.keyboard.down('d');
  await sleep(1500);
  await page.keyboard.up('d');
  await page.keyboard.press(' ');
  await sleep(800);
  await shot('03_move_jump');

  // 向左回走到 O₂ 光球按 E 拾取
  await page.keyboard.down('a');
  await sleep(1200);
  await page.keyboard.up('a');
  await page.keyboard.press('e');
  await sleep(1200);
  await shot('04_pickup');

  // Tab 背包
  await page.keyboard.press('Tab');
  await sleep(700);
  await shot('05_inventory');
  await page.keyboard.press('Escape');
  await sleep(400);

  // M 世界地图
  await page.keyboard.press('m');
  await sleep(700);
  await shot('06_worldmap');
  await page.keyboard.press('Escape');
  await sleep(400);

  // C 图鉴
  await page.keyboard.press('c');
  await sleep(700);
  await shot('07_codex');
  await page.keyboard.press('Escape');
  await sleep(400);

  // J 导师室
  await page.keyboard.press('j');
  await sleep(700);
  await shot('08_mentorroom');

  // 点一个导师开聊天
  const cards = await page.$$('.mentor-card');
  if (cards.length > 0) {
    await cards[0].click();
    await sleep(800);
    await shot('09_chat');
    // 输入问题并发送（离线兜底）
    await page.keyboard.type('为什么氢气会爆炸');
    await page.keyboard.press('Enter');
    await sleep(3500);
    await shot('10_chat_answer');
    await page.keyboard.press('Escape');
    await sleep(400);
  } else {
    errors.push('SMOKE: 导师室卡片为空');
  }

  // 向右走到营地（长距离）
  await page.keyboard.down('d');
  await sleep(12000);
  await page.keyboard.up('d');
  await shot('11_camp');

  // Esc 暂停
  await page.keyboard.press('Escape');
  await sleep(500);
  await shot('12_pause');
  await page.keyboard.press('Escape');
  await sleep(400);
} catch (e) {
  errors.push('SMOKE EXCEPTION: ' + e.message);
  await shot('99_exception');
}

console.log('=== console errors:', errors.length);
for (const e of errors.slice(0, 30)) console.log('  ERR:', e.slice(0, 220));
console.log('=== warnings:', warnings.length);
for (const w of warnings.slice(0, 10)) console.log('  WARN:', w.slice(0, 160));

await browser.close();
server.close();
process.exit(errors.length > 0 ? 1 : 0);
