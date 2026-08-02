// 深度冒烟：核心闭环全流程（合成→爆炸→导师→验纯→矿洞→死亡复活→睡觉→盐湖）
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
  if (!existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': MIME[extname(file)] || 'application/octet-stream' });
  res.end(readFileSync(file));
});
await new Promise(r => server.listen(8899, r));

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--no-sandbox', '--window-size=1340,820', '--autoplay-policy=no-user-gesture-required'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1320, height: 780 });
const errors = [];
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));

const shot = n => page.screenshot({ path: join(shotsDir, n + '.png') });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const fails = [];
const check = (name, cond) => {
  console.log(cond ? `  ✓ ${name}` : `  ✗ FAIL: ${name}`);
  if (!cond) fails.push(name);
};

try {
  await page.goto('http://localhost:8899/', { waitUntil: 'networkidle2', timeout: 30000 });
  await sleep(2200);
  await page.evaluate(() => localStorage.clear()); // 新开局
  await page.reload({ waitUntil: 'networkidle2' });
  await sleep(2200);

  // 进入世界
  await page.$$eval('#main-menu .btn', btns => btns[0].click());
  await sleep(1600);
  // —— 任务1：进入网站即全局播放背景音乐 ——
  const bgmPlaying = await page.evaluate(() => window.__ea.sfx.isBgmPlaying());
  check('背景音乐全局播放', bgmPlaying);

  const tp = (x) => page.evaluate((x) => {
    const w = window.__ea.game.scene.getScene('World');
    w.player.teleport(w.mapKey, x);
  }, x);
  const give = (id, n) => page.evaluate((id, n) => window.__ea.inventory.addItem(id, n), id, n);
  const state = (fn) => page.evaluate(fn);

  // ---- 1. 合成硫火把（便携格 + 点燃）----
  await give('stick', 1); await give('s', 1);
  await tp(2410);
  await sleep(300);
  await page.keyboard.press('e'); // 开合成台
  await sleep(700);
  await shot('20_craft_open');
  // 点击背包里的 stick 和 s（craft-inv-row 里按 title/img 顺序）
  await page.$$eval('.craft-inv-row .inv-slot', slots => { slots.find(s => s.querySelector('img')?.src.includes('stick'))?.click(); });
  await sleep(200);
  // —— 任务3：放入材料后出现配方提示 ——
  const hint1 = await state(() => document.querySelector('.craft-hint-area')?.innerHTML ?? '');
  check('合成台材料提示（是什么+怎么合成）', hint1.includes('便携格') && hint1.includes('硫火把'));
  await page.$$eval('.craft-inv-row .inv-slot', slots => { slots.find(s => s.querySelector('img')?.src.includes('/s.png'))?.click(); });
  await sleep(300);
  // 点火把：便携格默认 + 点燃按钮
  await page.$$eval('.craft-actions .btn', btns => { [...btns].find(b => b.textContent === '点燃')?.click(); });
  await sleep(900);
  await shot('21_craft_card');
  const cardVisible = await state(() => !!document.querySelector('#card-popup'));
  check('硫火把合成成功弹出知识卡片', cardVisible);
  const hasTorch = await state(() => window.__ea.inventory.countOf('sulfur_torch') >= 1);
  check('硫火把入包', hasTorch);
  await page.evaluate(() => window.__ea.uiManager.closePanel());
  await sleep(300);

  // ---- 2. 氢气未验纯点燃 → 爆炸 ----
  await page.keyboard.press('e'); // 重开合成台
  await sleep(600);
  await give('h2', 2); await give('o2', 1);
  await page.$$eval('.craft-inv-row .inv-slot', slots => { slots.find(s => s.querySelector('img')?.src.includes('/h2.png'))?.click(); });
  await page.$$eval('.craft-inv-row .inv-slot', slots => { slots.find(s => s.querySelector('img')?.src.includes('/o2.png'))?.click(); });
  await sleep(300);
  await page.$$eval('.craft-actions .btn', btns => { [...btns].find(b => b.textContent === '点燃')?.click(); });
  await sleep(1200);
  await shot('22_explosion');
  const hp = await state(() => window.__ea.gameManager.health);
  check('爆炸精确扣血 50', hp === 50);
  const explosionFlag = await state(() => window.__ea.gameManager.getFlag('explosion_happened'));
  check('爆炸标记置位', explosionFlag === true);
  const purityBtnMissing = await state(() => ![...document.querySelectorAll('.craft-actions .btn')].some(b => b.textContent === '验纯'));
  check('未问导师前无验纯按钮', purityBtnMissing);
  await page.evaluate(() => window.__ea.uiManager.closePanel());
  await sleep(400);

  // ---- 3. 导师问答解锁验纯（离线兜底）----
  await page.keyboard.press('j');
  await sleep(600);
  await page.$$eval('.mentor-card', cards => cards[0].click());
  await sleep(600);
  await page.keyboard.type('为什么氢气会爆炸，怎么验纯');
  await page.keyboard.press('Enter');
  await sleep(4000);
  const unlocked = await state(() => window.__ea.gameManager.getFlag('purity_check_unlocked'));
  check('问导师后解锁验纯', unlocked === true);
  await page.evaluate(() => window.__ea.uiManager.closePanel());
  await sleep(400);

  // ---- 4. 验纯后点燃成功 ----
  await page.keyboard.press('e'); // 重新开合成台
  await sleep(600);
  await give('h2', 1); await give('o2', 1);
  await page.$$eval('.craft-inv-row .inv-slot', slots => { slots.find(s => s.querySelector('img')?.src.includes('/h2.png'))?.click(); });
  await page.$$eval('.craft-inv-row .inv-slot', slots => { slots.find(s => s.querySelector('img')?.src.includes('/o2.png'))?.click(); });
  await sleep(300);
  // 先点验纯
  await page.$$eval('.craft-actions .btn', btns => { [...btns].find(b => b.textContent === '验纯')?.click(); });
  await sleep(600);
  await page.$$eval('.craft-actions .btn', btns => { [...btns].find(b => b.textContent === '点燃')?.click(); });
  await sleep(900);
  await shot('23_purity_success');
  const hp2 = await state(() => window.__ea.gameManager.health);
  check('验纯后点燃不扣血', hp2 === 50);
  const gotCleanWater = await state(() => window.__ea.inventory.countOf('h2o_clean') >= 1);
  check('氢气点燃产物入包（水）', gotCleanWater);
  await page.evaluate(() => window.__ea.uiManager.closePanel());
  await sleep(300);

  // ---- 5. 学院穿梭（导师小人 + 安全区）----
  await tp(2130);
  await sleep(300);
  await page.keyboard.press('e'); // 学院门
  await sleep(1400);
  await shot('23b_academy');
  const zoneAc = await state(() => window.__ea.gameManager.currentZone());
  check('穿梭到学院', zoneAc === 'academy');
  const mentorCount = await state(() => {
    const w = window.__ea.game.scene.getScene('World');
    return w.mapContainers.academy.list.filter(o => o.type === 'Sprite').length;
  });
  check('学院四位导师在场', mentorCount === 4);
  // 导师交互开聊天
  await tp(150);
  await sleep(300);
  await page.keyboard.press('e');
  await sleep(800);
  const chatOpen = await state(() => !!document.querySelector('#chat-panel'));
  check('导师旁按 E 开聊天框', chatOpen);
  await shot('23c_academy_chat');
  await page.evaluate(() => window.__ea.uiManager.closePanel());
  await sleep(300);
  // 穿出学院回营地
  await tp(60);
  await sleep(200);
  await page.keyboard.press('e');
  await sleep(1400);

  // ---- 6. 矿洞穿梭 + CO 幽灵 ----
  await tp(1960);
  await sleep(300);
  await page.keyboard.press('e'); // 矿洞入口
  await sleep(1400);
  await shot('24_mine');
  const zone = await state(() => window.__ea.gameManager.currentZone());
  check('穿梭到矿洞', zone === 'mine');
  const ghostCount = await state(() => window.__ea.game.scene.getScene('World').ghosts.filter(g => !g.dead).length);
  check('矿洞 CO 幽灵刷新', ghostCount >= 1);
  // 氧气快速下降验证（等 3 秒）
  const o2a = await state(() => window.__ea.gameManager.oxygen);
  await sleep(3000);
  const o2b = await state(() => window.__ea.gameManager.oxygen);
  check('矿洞氧气加速消耗', o2a - o2b > 4);
  // 等幽灵靠近触发 warn_co
  await sleep(4000);
  await shot('25_mine_ghost');

  // ---- 6. 死亡与复活（任务2：物品清空 + 采集物回位）----
  await page.evaluate(() => {
    const w = window.__ea.game.scene.getScene('World');
    // 模拟已捡走一个采集物
    const c = w.collectables.find(c => c.active);
    if (c) { c.active = false; c.sprite.setVisible(false); }
    window.__test_collectable = c;
    const gm = window.__ea.gameManager;
    gm.dayCount = 3;
    gm.timeOfDay = 100;
    window.__ea.gameManager.modifyHealth(-999);
  });
  await sleep(1200);
  await shot('26_death');
  const deathVisible = await state(() => !!document.querySelector('#death-screen'));
  check('死亡画面弹出', deathVisible);
  const invEmpty = await state(() => window.__ea.inventory.slots.length === 0);
  check('死亡后背包物品清空', invEmpty);
  await page.keyboard.press('x'); // 任意键复活
  await sleep(1200);
  await shot('27_respawn');
  const zone2 = await state(() => window.__ea.gameManager.currentZone());
  const hp3 = await state(() => window.__ea.gameManager.health);
  const dayAfterDeath = await state(() => window.__ea.gameManager.dayCount);
  const nightAfterDeath = await state(() => window.__ea.gameManager.isNight());
  const collectableBack = await state(() => window.__test_collectable ? window.__test_collectable.active : false);
  check('复活回营地（zone=camp）', zone2 === 'camp');
  check('复活三值回满', hp3 === 100);
  check('死亡后回到第一天白天（dayCount=1 且非夜晚）', dayAfterDeath === 1 && nightAfterDeath === false);
  check('采集物回到地图原本位置', collectableBack);

  // ---- 7. 床睡觉（任务4：白天拒绝，夜晚才能睡）----
  await tp(2268);
  await sleep(300);
  const day1 = await state(() => window.__ea.gameManager.dayCount);
  const timeDay = await state(() => { window.__ea.gameManager.timeOfDay = 50; });
  await page.keyboard.press('e'); // 白天按床 → 应被拒绝
  await sleep(600);
  const dayRefused = await state(() => window.__ea.gameManager.dayCount);
  check('白天不能睡觉（防刷天数）', dayRefused === day1);
  await page.evaluate(() => {
    // 快进到夜晚（入夜提醒弹出）
    window.__ea.gameManager.timeOfDay = Number(window.__ea.gameManager.getBalance('daynight.day_duration', 360)) + 5;
  });
  await sleep(400);
  await page.keyboard.press('e'); // 夜晚按床 → 睡觉
  await sleep(1400);
  await shot('28_sleep');
  const day2 = await state(() => window.__ea.gameManager.dayCount);
  const isNight = await state(() => window.__ea.gameManager.isNight());
  check('夜晚睡觉天数 +1', day2 === day1 + 1);
  check('睡觉后到清晨', isNight === false);

  // ---- 8. 盐湖 + 粗盐 ----
  await tp(512);
  await sleep(600);
  await shot('29_saltlake');
  const zone3 = await state(() => window.__ea.gameManager.currentZone());
  check('穿梭到盐湖', zone3 === 'saltlake');
  // 肥皂水试湖水
  await give('soap_water', 1);
  await page.keyboard.press('e'); // 湖水交互
  await sleep(800);
  const soapLeft = await state(() => window.__ea.inventory.countOf('soap_water'));
  check('肥皂水消耗（硬水字幕）', soapLeft === 0);

  // ---- 9. 电解 + 过滤设施 ----
  await tp(2970);
  await sleep(200);
  await page.keyboard.press('e'); // 河边取水
  await sleep(400);
  await tp(2710);
  await sleep(200);
  await page.keyboard.press('e'); // 过滤器
  await sleep(400);
  const clean = await state(() => window.__ea.inventory.countOf('h2o_clean') >= 1);
  check('过滤器得水→纯净水', clean);
  await tp(2860);
  await sleep(200);
  await page.keyboard.press('e'); // 电解器
  await sleep(400);
  const h2cnt = await state(() => window.__ea.inventory.countOf('h2'));
  const tank = await state(() => window.__ea.inventory.countOf('oxygen_tank'));
  check('电解器得 H₂（1:2）', h2cnt >= 2);
  check('额外灌装氧气瓶', tank >= 1);

  // ---- 10. 夜晚怪物（快进时间到夜晚）----
  await page.evaluate(() => {
    const gm = window.__ea.gameManager;
    gm.timeOfDay = gm.getBalance('daynight.day_duration', 360) - 2;
  });
  await sleep(3000);
  await shot('30_night');
  const slimeCount = await state(() => window.__ea.game.scene.getScene('World').slimes.filter(s => !s.dead).length);
  check('夜晚酸雾怪刷新 2~3 只', slimeCount >= 2 && slimeCount <= 3);
  const nightGhost = await state(() => window.__ea.game.scene.getScene('World').ghosts.filter(g => !g.dead && g.mapKey === 'main').length);
  check('夜晚草原 CO 幽灵刷新', nightGhost >= 1);

  // ---- 11. 中和喷雾打酸雾怪 ----
  await page.evaluate(() => {
    const w = window.__ea.game.scene.getScene('World');
    const s = w.slimes.find(s => !s.dead);
    if (s) { s.x = w.player.x + 40; s.y = w.player.y - 10; }
  });
  await give('neutral_spray', 1);
  await page.evaluate(() => {
    // 把喷雾放第一格并按 1
    const inv = window.__ea.inventory;
    const idx = inv.slots.findIndex(s => s.id === 'neutral_spray');
    if (idx > 0) { const t = inv.slots[0]; inv.slots[0] = inv.slots[idx]; inv.slots[idx] = t; }
  });
  const slimeBefore = await state(() => window.__ea.game.scene.getScene('World').slimes.filter(s => !s.dead).length);
  await page.keyboard.press('1');
  await sleep(600);
  const slimeAfter = await state(() => window.__ea.game.scene.getScene('World').slimes.filter(s => !s.dead).length);
  check('中和喷雾消灭酸雾怪', slimeAfter === slimeBefore - 1);
  await shot('31_spray_kill');

  // ---- 12. 原住民交易 ----
  await tp(2120);
  await sleep(300);
  await page.keyboard.press('e'); // 进交易态
  await sleep(500);
  await page.evaluate(() => { window.__ea.gameManager.energy = 50; });
  const energyBefore = await state(() => window.__ea.gameManager.energy);
  await give('oxygen_tank', 1);
  await page.evaluate(() => {
    const inv = window.__ea.inventory;
    const idx = inv.slots.findIndex(s => s.id === 'oxygen_tank');
    if (idx > 0) { const t = inv.slots[0]; inv.slots[0] = inv.slots[idx]; inv.slots[idx] = t; }
  });
  await page.keyboard.press('1'); // 卖出第 1 格
  await sleep(500);
  const energyAfter = await state(() => window.__ea.gameManager.energy);
  check('原住民交易 +20 能量', Math.abs(energyAfter - 70) < 2);
  await page.keyboard.press('e'); // 退出交易态
  await sleep(300);

  // ---- 13. 吃盐回能量（任务4）----
  await give('nacl', 1);
  await page.evaluate(() => {
    window.__ea.gameManager.energy = 40;
    const inv = window.__ea.inventory;
    const idx = inv.slots.findIndex(s => s.id === 'nacl');
    if (idx > 0) { const t = inv.slots[0]; inv.slots[0] = inv.slots[idx]; inv.slots[idx] = t; }
  });
  await page.keyboard.press('1'); // 吃盐
  await sleep(500);
  const energyFood = await state(() => window.__ea.gameManager.energy);
  check('吃盐回复能量（+12）', energyFood > 50 && energyFood < 53);

  // ---- 14. 物质就近信息卡（任务6）----
  await tp(1180);
  await sleep(600);
  const infoCard = await state(() => {
    const el = document.querySelector('#info-card');
    return el && el.style.display !== 'none' ? el.innerHTML : '';
  });
  check('经过物质显示信息卡（名称+化学式+作用）', infoCard.includes('氧气') && infoCard.includes('O₂'));
  await shot('32_info_card');

  // ---- 15. 怪物武器按键提示（任务5，有武器才显示）----
  await page.evaluate(() => {
    const w = window.__ea.game.scene.getScene('World');
    w.setMap('mine', 400);
  });
  await sleep(800);
  await give('activated_carbon', 1);
  await page.evaluate(() => {
    // 把幽灵拉到玩家附近
    const w = window.__ea.game.scene.getScene('World');
    const g = w.ghosts.find(g => !g.dead);
    if (g) { g.x = w.player.x + 50; g.y = w.player.y - 30; }
  });
  await sleep(600);
  const combatPrompt = await state(() => {
    const el = document.querySelector('#combat-prompt');
    return el && el.style.display !== 'none' ? el.textContent : '';
  });
  check('持有活性炭时显示武器按键提示', combatPrompt.includes('按 F') && combatPrompt.includes('活性炭'));
  await shot('33_combat_prompt');
  // 按 F 专属攻击键消灭（消耗品用掉一个）
  const carbonBefore = await state(() => window.__ea.inventory.countOf('activated_carbon'));
  const ghostsBefore = await state(() => window.__ea.game.scene.getScene('World').ghosts.filter(g => !g.dead).length);
  await page.keyboard.press('f');
  await sleep(600);
  const ghostsAfter = await state(() => window.__ea.game.scene.getScene('World').ghosts.filter(g => !g.dead).length);
  const carbonAfter = await state(() => window.__ea.inventory.countOf('activated_carbon'));
  check('F 键消灭 CO 幽灵', ghostsAfter === ghostsBefore - 1);
  check('活性炭是消耗品（用掉一个）', carbonAfter === carbonBefore - 1);
  // 怪物每日刷新：跳到第二天清晨
  await page.evaluate(() => window.__ea.gameManager.sleepUntilMorning());
  await sleep(800);
  const ghostsRespawn = await state(() => window.__ea.game.scene.getScene('World').ghosts.filter(g => !g.dead && g.mapKey === 'mine').length);
  check('怪物每天清晨刷新', ghostsRespawn >= 2);
} catch (e) {
  errors.push('SMOKE2 EXCEPTION: ' + e.message);
  await shot('98_exception');
}

console.log('=== console errors:', errors.length);
for (const e of errors.slice(0, 20)) console.log('  ERR:', e.slice(0, 200));
console.log('=== functional checks failed:', fails.length);
for (const f of fails) console.log('  FAIL:', f);
await browser.close();
server.close();
process.exit(errors.length + fails.length > 0 ? 1 : 0);
