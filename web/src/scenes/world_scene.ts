// WorldScene：一张连续主世界（盐湖|草原|营地拼接）+ 矿洞 + 学院（黑屏穿梭）
import Phaser from 'phaser';
import { gameManager } from '../core/game_manager';
import { knowledgeTip } from '../core/knowledge_tip';
import { eventBus } from '../core/event_bus';
import { recipeDB } from '../core/recipe_db';
import { uiManager } from '../ui/ui_manager';
import { tipsLayer } from '../ui/tips_layer';
import { hud } from '../ui/hud';
import { inventory } from '../gameplay/inventory';
import { discovery } from '../gameplay/discovery';
import { itemEffects } from '../gameplay/item_effects';
import { saveStore } from '../save/save_store';
import { sfx } from '../audio/sfx';
import { Player } from '../world/player';
import { registerSheetFrames, createAnim, setDisplayHeight, DISPLAY_SIZE } from '../world/sprite_factory';
import { interactRegistry } from '../world/interactables';
import type { Interactable } from '../world/interactables';
import { Ghost, Slime } from '../world/monsters';
import { craftPanel } from '../ui/panels_game';
import { pausePanel, deathPanel, mentorRoomPanel } from '../ui/panels_menu';
import {
  MAP_MAIN, MAP_MINE, MAP_ACADEMY, MAPS, MAIN_SEGMENTS, TRAVEL_POINTS,
  SPAWN_DEFAULT, SPAWN_BED,
  COLLECTABLES, FACILITIES, CUSO4_POOL, CUSO4_WARN_RADIUS, MENTOR_POSITIONS, MONSTER_SPAWNS,
  groundY,
} from '../world/maps';

// 全局一次性出生点覆盖（FR-C-08 D2 裁决：导师学院门 → 学院出生）
export let worldSpawnOverride: { map: string; x: number } | null = null;
export function setWorldSpawnOverride(v: { map: string; x: number } | null): void {
  worldSpawnOverride = v;
}

interface CollectableEntity extends Interactable {
  defId: string;
  substanceId: string;
  active: boolean;
  sprite: Phaser.GameObjects.Image;
  glow: Phaser.GameObjects.Image;
  tween?: Phaser.Tweens.Tween;
}

export class WorldScene extends Phaser.Scene {
  private player!: Player;
  private mapKey = MAP_MAIN;
  private mapContainers: Record<string, Phaser.GameObjects.Container> = {};
  private collectables: CollectableEntity[] = [];
  private ghosts: Ghost[] = [];
  private slimes: Slime[] = [];
  private keyA!: Phaser.Input.Keyboard.Key;
  private keyD!: Phaser.Input.Keyboard.Key;
  private keySpace!: Phaser.Input.Keyboard.Key;
  private keyLeft!: Phaser.Input.Keyboard.Key;
  private keyRight!: Phaser.Input.Keyboard.Key;
  private promptEl: HTMLElement | null = null;
  private combatPromptEl: HTMLElement | null = null;
  private infoCardEl: HTMLElement | null = null;
  private darknessCanvas!: Phaser.Textures.CanvasTexture;
  private darknessImg!: Phaser.GameObjects.Image;
  private campfireUses = 0;
  private tradeMode = false;
  private cuso4Warned = false;
  private mineBreathShown = false;
  private autosaveTimer = 0;
  private firstEnterRiver = false;
  private photosynthesisShown = false;
  private carbonHintShown = false;
  private sprayHintShown = false;
  private unsubs: (() => void)[] = [];

  constructor() {
    super('World');
  }

  create(): void {
    registerSheetFrames(this);
    uiManager.basePanel = '';
    interactRegistry.clear();
    this.collectables = [];
    this.ghosts = [];
    this.slimes = [];
    this.unsubs = [];

    this.makeGlowTexture();
    this.buildMaps();
    this.buildPlayer();
    this.buildCollectables();
    this.buildFacilities();
    this.buildMentors();
    this.buildTraderAndMarkers();
    this.buildDarkness();
    this.setupInput();
    this.setupEvents();

    hud.init(document.getElementById('ui-root')!);
    tipsLayer.init(document.getElementById('ui-root')!);
    this.promptEl = document.createElement('div');
    this.promptEl.id = 'interact-prompt';
    document.getElementById('ui-root')!.appendChild(this.promptEl);
    this.combatPromptEl = document.createElement('div');
    this.combatPromptEl.id = 'combat-prompt';
    document.getElementById('ui-root')!.appendChild(this.combatPromptEl);
    this.infoCardEl = document.createElement('div');
    this.infoCardEl.id = 'info-card';
    document.getElementById('ui-root')!.appendChild(this.infoCardEl);

    const spawn = worldSpawnOverride ?? SPAWN_DEFAULT;
    worldSpawnOverride = null; // 一次性标记，消费后清除
    this.setMap(spawn.map, spawn.x);
    this.cameras.main.fadeIn(400, 0, 0, 0);

    this.events.once('shutdown', () => this.cleanup());
  }

  private cleanup(): void {
    for (const u of this.unsubs) u();
    this.unsubs = [];
    this.promptEl?.remove();
    this.promptEl = null;
    this.combatPromptEl?.remove();
    this.combatPromptEl = null;
    this.infoCardEl?.remove();
    this.infoCardEl = null;
    uiManager.onKey = null;
    interactRegistry.clear();
  }

  // ---------------- 纹理生成 ----------------
  private makeGlowTexture(): void {
    if (this.textures.exists('glow_tex')) return;
    const c = this.textures.createCanvas('glow_tex', 64, 64);
    if (!c) return;
    const ctx = c.getContext();
    const grad = ctx.createRadialGradient(32, 32, 2, 32, 32, 30);
    grad.addColorStop(0, 'rgba(255,255,220,0.9)');
    grad.addColorStop(0.5, 'rgba(255,240,150,0.35)');
    grad.addColorStop(1, 'rgba(255,240,150,0)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 64, 64);
    c.refresh();
  }

  private makeTraderTexture(): void {
    if (this.textures.exists('trader_tex')) return;
    const c = this.textures.createCanvas('trader_tex', 40, 64);
    if (!c) return;
    const ctx = c.getContext();
    ctx.fillStyle = '#8a6b4a';
    ctx.beginPath();
    ctx.moveTo(20, 4); ctx.lineTo(38, 20); ctx.lineTo(2, 20); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#d99a6c';
    ctx.fillRect(13, 20, 14, 10);
    ctx.fillStyle = '#6b4f36';
    ctx.fillRect(10, 30, 20, 28);
    ctx.fillStyle = '#4a3626';
    ctx.fillRect(10, 52, 8, 10);
    ctx.fillRect(22, 52, 8, 10);
    ctx.fillStyle = '#a89078';
    ctx.fillRect(32, 22, 3, 38);
    ctx.fillStyle = '#ffd94a';
    ctx.fillRect(31, 18, 5, 5);
    c.refresh();
  }

  private makeMarkerTexture(key: string, dark: string, light: string): void {
    if (this.textures.exists(key)) return;
    const c = this.textures.createCanvas(key, 56, 64);
    if (!c) return;
    const ctx = c.getContext();
    ctx.fillStyle = dark;
    ctx.beginPath();
    ctx.moveTo(8, 64); ctx.lineTo(8, 20); ctx.quadraticCurveTo(28, 0, 48, 20); ctx.lineTo(48, 64); ctx.closePath(); ctx.fill();
    ctx.strokeStyle = light;
    ctx.lineWidth = 3;
    ctx.stroke();
    c.refresh();
  }

  // ---------------- 地图构建 ----------------
  private buildMaps(): void {
    this.mapContainers = {};
    const main = this.add.container(0, 0);
    for (const seg of MAIN_SEGMENTS) {
      main.add(this.add.image(seg.x, 0, seg.img).setOrigin(0, 0));
    }
    this.mapContainers[MAP_MAIN] = main;

    const mine = this.add.container(0, 0);
    mine.add(this.add.image(0, 0, 'map_mine').setOrigin(0, 0));
    mine.setVisible(false);
    this.mapContainers[MAP_MINE] = mine;

    const academy = this.add.container(0, 0);
    academy.add(this.add.image(0, 0, 'map_academy').setOrigin(0, 0));
    academy.setVisible(false);
    this.mapContainers[MAP_ACADEMY] = academy;
  }

  private buildPlayer(): void {
    this.player = new Player(this);
    this.player.create(MAP_MAIN, SPAWN_DEFAULT.x);
    this.player.sprite.setDepth(100);
  }

  // ---------------- 采集物 ----------------
  private buildCollectables(): void {
    for (const def of COLLECTABLES) {
      const container = this.mapContainers[def.map];
      const gy = groundY(def.map, def.x);
      const y = def.y !== 0 ? gy - def.y : gy - 26;
      const glow = this.add.image(def.x, y, 'glow_tex');
      glow.setAlpha(0.55);
      glow.setScale(0.5);
      const icon = this.add.image(def.x, y, `icon_${def.substanceId}`);
      // 统一目标展示尺寸（图标源图裁剪尺寸不一，按高度归一）
      const targetH = 30;
      icon.setScale(targetH / icon.height);
      container.add([glow, icon]);
      const tw = this.tweens.add({
        targets: [icon, glow],
        y: y - 6,
        duration: 1100 + Math.random() * 500,
        yoyo: true,
        repeat: -1,
        ease: 'Sine.easeInOut',
      });
      const entity: CollectableEntity = {
        defId: def.id,
        substanceId: def.substanceId,
        active: true,
        sprite: icon,
        glow,
        tween: tw,
        map: def.map,
        x: def.x,
        y,
        radius: 44, // 宽容的拾取范围（经过即提示）
        getInteractPrompt: () => gameManager.getUiString('prompt_interact'),
        canInteract: () => entity.active && !gameManager.isDead(),
        interact: () => this.pickUp(entity),
      };
      interactRegistry.add(entity);
      this.collectables.push(entity);
    }
  }

  private pickUp(entity: CollectableEntity): void {
    if (!entity.active) return;
    const leftover = inventory.addItem(entity.substanceId, 1);
    if (leftover > 0) return;
    entity.active = false;
    entity.sprite.setVisible(false);
    entity.glow.setVisible(false);
    entity.tween?.stop();
    sfx.pickup();
    this.player.playOnce('pickup', 400);
    const sub = recipeDB.getSubstance(entity.substanceId);
    const isFirst = discovery.discover(entity.substanceId);
    if (isFirst && sub.tip_id) {
      knowledgeTip.showOnce(String(sub.tip_id));
    }
    if (entity.substanceId === 'o2' && !this.photosynthesisShown) {
      this.photosynthesisShown = true;
      knowledgeTip.showOnce('zone_photosynthesis');
    }
    saveStore.save();
  }

  // ---------------- 设施 ----------------
  private buildFacilities(): void {
    const gm = gameManager;
    for (const f of FACILITIES) {
      const gy = groundY(f.map, f.x);
      const it: Interactable = {
        map: f.map,
        x: f.x,
        y: gy,
        radius: f.radius,
        getInteractPrompt: () => gm.getUiString('prompt_interact'),
        canInteract: () => !gameManager.isDead(),
        interact: () => this.onFacility(f.id),
      };
      interactRegistry.add(it);
    }
  }

  private onFacility(id: string): void {
    switch (id) {
      case 'bed': this.sleepInBed(); break;
      case 'craft_bench': uiManager.openPanel('craft'); break;
      case 'campfire': this.useCampfire(); break;
      case 'filter': this.useFilter(); break;
      case 'electrolyzer': this.useElectrolyzer(); break;
      case 'river': this.fetchRiverWater(); break;
      case 'trader': this.enterTradeMode(); break;
      case 'signpost': uiManager.openPanel('worldmap'); break;
      case 'lakewater': this.useSoapOnLake(); break;
    }
  }

  private sleepInBed(): void {
    // 只有夜晚（入夜提醒 warn_night 已弹出）才能睡觉，防止白天刷存活天数
    if (!gameManager.isNight()) {
      knowledgeTip.show('sys_no_sleep');
      return;
    }
    sfx.sleep();
    void uiManager.fadeThrough(() => {
      gameManager.sleepUntilMorning();
      this.player.teleport(this.mapKey, this.player.x);
      knowledgeTip.show('sys_sleep');
      saveStore.save();
    });
  }

  private useCampfire(): void {
    const limit = Number(gameManager.getBalance('items.campfire_daily_limit', 3));
    if (this.campfireUses >= limit) {
      knowledgeTip.show('sys_energy_food');
      return;
    }
    this.campfireUses += 1;
    gameManager.modifyEnergy(Number(gameManager.getBalance('items.campfire_meal_restore', 40)));
    knowledgeTip.show('sys_energy_food');
    sfx.craftSuccess();
  }

  private useFilter(): void {
    if (!inventory.hasItem('h2o', 1)) {
      knowledgeTip.show('sys_filter');
      return;
    }
    inventory.removeItem('h2o', 1);
    inventory.addItem('h2o_clean', 1);
    discovery.discover('h2o_clean');
    knowledgeTip.show('sys_filter');
    sfx.craftSuccess();
  }

  private useElectrolyzer(): void {
    if (!inventory.hasItem('h2o_clean', 1)) {
      knowledgeTip.show('sys_electrolysis');
      return;
    }
    inventory.removeItem('h2o_clean', 1);
    // 正氧负氢 1:2 给量；成功时额外灌装氧气瓶 ×1（D4 裁决）
    inventory.addItem('h2', 2);
    inventory.addItem('o2', 1);
    inventory.addItem('oxygen_tank', 1);
    discovery.discover('h2');
    recipeDB.markUnlock('r_electrolysis');
    knowledgeTip.show('sys_electrolysis');
    sfx.craftSuccess();
    saveStore.save();
  }

  private fetchRiverWater(): void {
    inventory.addItem('h2o', 1);
    discovery.discover('h2o');
    sfx.splash();
    if (!this.firstEnterRiver) {
      this.firstEnterRiver = true;
      knowledgeTip.showOnce('zone_river');
    }
  }

  private useSoapOnLake(): void {
    if (inventory.hasItem('soap_water', 1)) {
      inventory.removeItem('soap_water', 1);
      knowledgeTip.show('sys_hardwater');
      sfx.splash();
    }
  }

  // ---------------- 交易 ----------------
  private enterTradeMode(): void {
    this.tradeMode = true;
    knowledgeTip.show('sys_trade_prompt');
  }

  private exitTradeMode(): void {
    this.tradeMode = false;
  }

  private tradeSlot(index: number): void {
    const slot = inventory.slots[index];
    if (!slot || slot.count <= 0) {
      knowledgeTip.show('sys_trade_empty');
      return;
    }
    const item = itemEffects.item(slot.id);
    const sellable = !!item.id && ['equip', 'consume'].includes(String(item.type));
    if (!sellable) {
      knowledgeTip.show('sys_trade_empty');
      return;
    }
    if (itemEffects.isEquipped(slot.id)) itemEffects.unequip(slot.id);
    inventory.removeItem(slot.id, 1);
    gameManager.modifyEnergy(Number(gameManager.getBalance('items.trade_energy_restore', 20)));
    knowledgeTip.show('sys_trade_done');
    sfx.trade();
  }

  // ---------------- 导师 ----------------
  private buildMentors(): void {
    const container = this.mapContainers[MAP_ACADEMY];
    for (const [mentorId, pos] of Object.entries(MENTOR_POSITIONS)) {
      const sheet = `mentor_${mentorId}`;
      const gy = MAPS[MAP_ACADEMY].groundY;
      createAnim(this, sheet, 'idle', { frameRate: 3 });
      const sprite = this.add.sprite(pos.x, gy, sheet, 'idle_0');
      setDisplayHeight(sprite, DISPLAY_SIZE[sheet]?.h ?? 78);
      sprite.setOrigin(0.5, 1);
      sprite.play(`${sheet}_idle`);
      container.add(sprite);

      const it: Interactable = {
        map: MAP_ACADEMY,
        x: pos.x,
        y: gy,
        radius: 55,
        getInteractPrompt: () => gameManager.getUiString('prompt_ask'),
        canInteract: () => !gameManager.isDead(),
        interact: () => uiManager.openPanel('chat', mentorId),
      };
      interactRegistry.add(it);
    }
  }

  // ---------------- 原住民 / 标记物 / 穿梭点 ----------------
  private buildTraderAndMarkers(): void {
    this.makeTraderTexture();
    this.makeMarkerTexture('marker_mine', '#221f2e', '#6b6478');
    this.makeMarkerTexture('marker_academy', '#2c2457', '#7f6fd6');
    const main = this.mapContainers[MAP_MAIN];

    const traderGy = groundY(MAP_MAIN, 2120);
    const trader = this.add.image(2120, traderGy, 'trader_tex');
    trader.setOrigin(0.5, 1);
    main.add(trader);
    this.tweens.add({ targets: trader, y: traderGy - 3, duration: 1400, yoyo: true, repeat: -1, ease: 'Sine.easeInOut' });

    main.add(this.add.image(1990, groundY(MAP_MAIN, 1990), 'marker_mine').setOrigin(0.5, 1));
    main.add(this.add.image(2130, groundY(MAP_MAIN, 2130), 'marker_academy').setOrigin(0.5, 1));

    for (const tp of TRAVEL_POINTS) {
      const it: Interactable = {
        map: tp.map,
        x: tp.x,
        y: groundY(tp.map, tp.x),
        radius: 46,
        getInteractPrompt: () => gameManager.getUiString('prompt_interact'),
        canInteract: () => !gameManager.isDead(),
        interact: () => this.travelTo(tp.toMap, tp.toX),
      };
      interactRegistry.add(it);
    }
  }

  // ---------------- 夜晚压暗层 ----------------
  private buildDarkness(): void {
    this.darknessCanvas = this.textures.createCanvas('darkness', 640, 360) as Phaser.Textures.CanvasTexture;
    this.darknessImg = this.add.image(0, 0, 'darkness').setOrigin(0, 0).setScrollFactor(0).setDepth(900);
    this.darknessImg.setVisible(false);
  }

  private renderDarkness(): void {
    const inMine = this.mapKey === MAP_MINE;
    const inAcademy = this.mapKey === MAP_ACADEMY;
    const night = gameManager.isNight();
    const needDark = inMine || (night && !inAcademy);
    if (!needDark) {
      if (this.darknessImg.visible) this.darknessImg.setVisible(false);
      return;
    }
    const brightness = Number(gameManager.getBalance('daynight.night_brightness', 0.35));
    const torch = itemEffects.isEquipped('sulfur_torch');
    const radius = torch
      ? Number(gameManager.getBalance('daynight.torch_view_radius', 220))
      : Number(gameManager.getBalance('daynight.dark_view_radius', 80));
    const alpha = 1 - brightness;
    const ctx = this.darknessCanvas.getContext();
    ctx.clearRect(0, 0, 640, 360);
    const cam = this.cameras.main;
    const sx = this.player.x - cam.scrollX;
    const sy = this.player.y - 40 - cam.scrollY;
    const grad = ctx.createRadialGradient(sx, sy, Math.max(10, radius * 0.35), sx, sy, radius);
    grad.addColorStop(0, `rgba(0,0,0,${(alpha * 0.25).toFixed(3)})`);
    grad.addColorStop(1, `rgba(0,0,0,${alpha.toFixed(3)})`);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 640, 360);
    this.darknessCanvas.refresh();
    if (!this.darknessImg.visible) this.darknessImg.setVisible(true);
  }

  // ---------------- 输入 ----------------
  private setupInput(): void {
    const kb = this.input.keyboard!;
    this.keyA = kb.addKey(Phaser.Input.Keyboard.KeyCodes.A);
    this.keyD = kb.addKey(Phaser.Input.Keyboard.KeyCodes.D);
    this.keySpace = kb.addKey(Phaser.Input.Keyboard.KeyCodes.SPACE);
    this.keyLeft = kb.addKey(Phaser.Input.Keyboard.KeyCodes.LEFT);
    this.keyRight = kb.addKey(Phaser.Input.Keyboard.KeyCodes.RIGHT);
    uiManager.onKey = (action) => this.onActionKey(action);
  }

  private isTyping(): boolean {
    const a = document.activeElement;
    return !!a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA');
  }

  private onActionKey(action: string): void {
    if (!this.sys.isActive()) return;
    if (action === 'pause') {
      if (uiManager.currentPanel()) uiManager.closePanel();
      else uiManager.openPanel('pause');
      return;
    }
    if (uiManager.currentPanel()) return;

    if (this.tradeMode && action.startsWith('slot_')) {
      this.tradeSlot(Number(action.slice(5)) - 1);
      return;
    }
    switch (action) {
      case 'interact': {
        if (this.tradeMode) {
          this.exitTradeMode();
          return;
        }
        const target = interactRegistry.nearest(this.mapKey, this.player.x, this.player.y - 20);
        target?.interact();
        break;
      }
      case 'inventory': uiManager.openPanel('inventory'); break;
      case 'worldmap': uiManager.openPanel('worldmap'); break;
      case 'codex': uiManager.openPanel('codex'); break;
      case 'mentorroom': uiManager.openPanel('mentorroom'); break;
      case 'attack': this.attackNearestMonster(); break;
      default:
        if (action.startsWith('slot_')) {
          this.useHotbarSlot(Number(action.slice(5)) - 1);
        }
    }
  }

  // F 键打怪：自动选用对应克制物品（消耗品，用一次少一个）
  private attackNearestMonster(): void {
    const ghost = this.ghosts.find(g => !g.dead && g.mapKey === this.mapKey &&
      Math.hypot(g.x - this.player.x, g.y - this.player.y) < 140);
    const slime = this.slimes.find(s => !s.dead && s.mapKey === this.mapKey &&
      Math.hypot(s.x - this.player.x, s.y - this.player.y) < 150);
    const monster = ghost ?? slime;
    if (!monster) {
      knowledgeTip.show('sys_hint_no_target');
      return;
    }
    const weaponId = ghost ? 'activated_carbon' : 'neutral_spray';
    if (inventory.hasItem(weaponId, 1)) {
      inventory.removeItem(weaponId, 1);
      if (ghost) ghost.kill();
      else slime!.kill();
      sfx.spray();
      return;
    }
    // 没有对应物品：提示获取方式（消耗品说明）
    knowledgeTip.show(ghost ? 'sys_hint_carbon' : 'sys_hint_spray');
  }

  private useHotbarSlot(index: number): void {
    const slot = inventory.slots[index];
    if (!slot || slot.count <= 0) return;
    const id = slot.id;
    // 可食用物质：喝水 / 吃盐回复能量
    const subFood = recipeDB.getSubstance(id);
    const foodEnergy = Number(subFood.energy_restore ?? 0);
    if (foodEnergy > 0) {
      inventory.removeItem(id, 1);
      gameManager.modifyEnergy(foodEnergy);
      knowledgeTip.show('sys_energy_food');
      sfx.craftSuccess();
      return;
    }
    if (id === 'soap_water') {
      // 肥皂水只对盐湖湖水生效
      if (gameManager.currentZone() !== 'saltlake') {
        knowledgeTip.show('sys_hint_no_target');
        return;
      }
      inventory.removeItem(id, 1);
      knowledgeTip.show('sys_hardwater');
      sfx.splash();
      return;
    }
    if (id === 'activated_carbon') {
      const target = this.ghosts.find(g => !g.dead && g.mapKey === this.mapKey &&
        Math.hypot(g.x - this.player.x, g.y - this.player.y) < 140);
      if (!target) {
        knowledgeTip.show('sys_hint_no_target');
        return;
      }
      inventory.removeItem(id, 1);
      target.kill();
      sfx.spray();
      return;
    }
    if (id === 'neutral_spray') {
      const target = this.slimes.find(s => !s.dead &&
        Math.hypot(s.x - this.player.x, s.y - this.player.y) < 150);
      if (!target) {
        knowledgeTip.show('sys_hint_no_target');
        return;
      }
      inventory.removeItem(id, 1);
      target.kill();
      sfx.spray();
      return;
    }
    const item = itemEffects.item(id);
    if (!item.id) return;
    const consumed = itemEffects.useItem(id);
    if (consumed) inventory.removeItem(id, 1);
    if (String(item.type) === 'equip') sfx.page();
  }

  // ---------------- 事件 ----------------
  private setupEvents(): void {
    this.unsubs.push(eventBus.on('player_died', () => this.onPlayerDied()));
    this.unsubs.push(eventBus.on('night_started', () => {
      knowledgeTip.show('warn_night');
      this.spawnNightMonsters();
    }));
    this.unsubs.push(eventBus.on('day_started', () => this.clearNightMonsters()));
    this.unsubs.push(eventBus.on('resources_respawned', () => {
      this.respawnCollectables();
      this.campfireUses = 0;
      // 怪物每天刷新一次：清除尸体，矿洞幽灵重新出现（夜晚怪由 night_started 刷新）
      this.ghosts = this.ghosts.filter(g => !g.dead);
      this.slimes = this.slimes.filter(s => !s.dead);
      if (this.mapKey === MAP_MINE) this.spawnMineGhosts();
    }));
    this.unsubs.push(eventBus.on('day_started', () => {
      this.sprayHintShown = false;
    }));
    this.unsubs.push(eventBus.on('zone_changed', (p) => {
      const tipMap: Record<string, string> = {
        grassland: 'zone_grass', saltlake: 'zone_salt', mine: 'zone_mine',
        camp: 'zone_camp', academy: 'zone_academy',
      };
      const tipId = tipMap[p.zoneId];
      if (tipId) knowledgeTip.showOnce(tipId);
      if (p.zoneId === 'mine') this.spawnMineGhosts();
      saveStore.save();
    }));
    this.unsubs.push(eventBus.on('explosion_triggered', () => {
      this.cameras.main.shake(450, 0.02);
      this.cameras.main.flash(220, 255, 120, 40);
    }));
    pausePanel.onToMenu = () => {
      saveStore.save();
      this.scene.start('Menu');
    };
    deathPanel.onRespawn = () => this.respawnPlayer();
    mentorRoomPanel.onSelect = (mentorId) => uiManager.openPanel('chat', mentorId);
    craftPanel.getZone = () => gameManager.currentZone();
  }

  // ---------------- 怪物刷新 ----------------
  private spawnMineGhosts(): void {
    // 补足到目标数量（每天清晨/进洞时调用）
    const alive = this.ghosts.filter(g => !g.dead && g.mapKey === MAP_MINE);
    const need = MONSTER_SPAWNS.ghost_mine.length - alive.length;
    for (let i = 0; i < need; i++) {
      const spot = MONSTER_SPAWNS.ghost_mine.find(s => !alive.some(g => Math.abs(g.x - s.x) < 80))
        ?? MONSTER_SPAWNS.ghost_mine[i % MONSTER_SPAWNS.ghost_mine.length];
      const g = new Ghost(this, MAP_MINE, spot.x, MAPS[MAP_MINE].groundY - 30);
      g.sprite.setVisible(this.mapKey === MAP_MINE);
      this.ghosts.push(g);
      alive.push(g);
    }
  }

  private spawnNightMonsters(): void {
    for (const s of MONSTER_SPAWNS.ghost_grass_night) {
      this.ghosts.push(new Ghost(this, MAP_MAIN, s.x, groundY(MAP_MAIN, s.x) - 30));
    }
    const min = Number(gameManager.getBalance('monsters.acid_mist_night_count_min', 2));
    const max = Number(gameManager.getBalance('monsters.acid_mist_night_count_max', 3));
    const count = min + Math.floor(Math.random() * (max - min + 1));
    const spots = [...MONSTER_SPAWNS.slime_camp_night].sort(() => Math.random() - 0.5).slice(0, count);
    for (const s of spots) {
      this.slimes.push(new Slime(this, MAP_MAIN, s.x, groundY(MAP_MAIN, s.x), 2060, 3060));
    }
    if (count > 0) knowledgeTip.show('warn_acid');
  }

  private clearNightMonsters(): void {
    for (const s of this.slimes) if (!s.dead) s.kill(false);
    this.slimes = [];
    for (const g of this.ghosts) {
      if (g.mapKey === MAP_MAIN && !g.dead) g.kill(false);
    }
    this.ghosts = this.ghosts.filter(g => g.mapKey !== MAP_MAIN);
  }

  // ---------------- 资源刷新 ----------------
  private respawnCollectables(): void {
    for (const c of this.collectables) {
      if (!c.active) {
        c.active = true;
        c.sprite.setVisible(true);
        c.glow.setVisible(true);
        c.tween?.play();
      }
    }
  }

  // ---------------- 死亡与复活 ----------------
  private onPlayerDied(): void {
    knowledgeTip.show('sys_death');
    sfx.death();
    // 背包物品清空；复活时采集物回到地图原本位置（resources_respawned 驱动）
    inventory.clear();
    uiManager.openPanel('death');
  }

  private respawnPlayer(): void {
    gameManager.respawnPlayer();
    if (this.mapKey !== MAP_MAIN) {
      this.setMap(MAP_MAIN, SPAWN_BED.x);
    } else {
      this.player.teleport(MAP_MAIN, SPAWN_BED.x);
    }
    uiManager.closePanel();
    this.cameras.main.flash(300, 255, 255, 255);
    saveStore.save();
  }

  // ---------------- 穿梭 ----------------
  private travelTo(toMap: string, toX: number): void {
    void uiManager.fadeThrough(() => {
      this.setMap(toMap, toX);
    });
  }

  private setMap(mapKey: string, x: number): void {
    this.mapKey = mapKey;
    for (const [key, container] of Object.entries(this.mapContainers)) {
      container.setVisible(key === mapKey);
    }
    this.player.teleport(mapKey, x);
    for (const g of this.ghosts) g.sprite.setVisible(g.mapKey === mapKey);
    for (const s of this.slimes) s.sprite.setVisible(s.mapKey === mapKey);
    this.carbonHintShown = false; // 换图后允许再次提示消灭方式
    const def = MAPS[mapKey];
    this.cameras.main.setBounds(0, 0, def.width, Math.max(def.height, 360));
    this.cameras.main.startFollow(this.player.sprite, true, 0.1, 0.1);
    this.cameras.main.setFollowOffset(0, 40);
    this.updateZone();
    if (mapKey === MAP_MINE) this.spawnMineGhosts();
  }

  private updateZone(): void {
    if (this.mapKey === MAP_MINE) {
      gameManager.setZone('mine');
      return;
    }
    if (this.mapKey === MAP_ACADEMY) {
      gameManager.setZone('academy');
      return;
    }
    const x = this.player.x;
    for (const z of MAPS[MAP_MAIN].zones) {
      if (x >= z.x0 && x < z.x1) {
        gameManager.setZone(z.id);
        return;
      }
    }
  }

  // ---------------- 主循环 ----------------
  update(_time: number, delta: number): void {
    if (!this.player) return;
    const dt = Math.min(delta, 100) / 1000;
    const panelOpen = uiManager.inputBlocked;
    this.player.inputBlocked = panelOpen || this.isTyping();

    if (!panelOpen) {
      gameManager.tick(dt);
      gameManager.setRespawnReferencePosition(this.player.x, this.player.y);
      const keys = {
        left: this.keyA.isDown || this.keyLeft.isDown,
        right: this.keyD.isDown || this.keyRight.isDown,
        jump: Phaser.Input.Keyboard.JustDown(this.keySpace),
      };
      this.player.update(delta, keys);
      this.updateZone();
      this.updateMonsters(dt);
      this.updateHazards(dt);
      this.updateCampfireRegen(dt);
      this.updateTradeDistance();
    }

    this.renderDarkness();
    tipsLayer.update(panelOpen ? 0 : delta);
    this.updateInteractPrompt();
    this.updateCombatPrompt();
    this.updateBubbleTarget();

    this.autosaveTimer += delta;
    if (this.autosaveTimer > 8000) {
      this.autosaveTimer = 0;
      saveStore.save();
    }
  }

  private updateMonsters(dt: number): void {
    const inAcademy = this.mapKey === MAP_ACADEMY;
    for (const g of this.ghosts) {
      if (g.dead || g.mapKey !== this.mapKey) continue;
      g.update(dt, this.player.x, this.player.y - 30, inAcademy);
    }
    for (const s of this.slimes) {
      if (s.dead || s.mapKey !== this.mapKey) continue;
      s.update(dt, this.player.x, this.player.y - 10);
    }
  }

  private updateHazards(dt: number): void {
    if (this.mapKey === MAP_MINE) {
      const inPool = this.player.x >= CUSO4_POOL.x0 && this.player.x <= CUSO4_POOL.x1;
      if (inPool && !gameManager.isDead()) {
        gameManager.modifyHealth(-Number(gameManager.getBalance('damage.cuso4_pool_per_second', 5)) * dt);
      }
      const distToPool = Math.min(
        Math.abs(this.player.x - CUSO4_POOL.x0),
        Math.abs(this.player.x - CUSO4_POOL.x1),
      );
      if (!this.cuso4Warned && distToPool < CUSO4_WARN_RADIUS) {
        this.cuso4Warned = true;
        knowledgeTip.showOnce('warn_cuso4');
      }
      if (!this.mineBreathShown && gameManager.oxygen < 50) {
        this.mineBreathShown = true;
        knowledgeTip.show('sys_mine_breath');
      }
    } else {
      this.mineBreathShown = false;
    }
  }

  private updateCampfireRegen(dt: number): void {
    if (this.mapKey !== MAP_MAIN) return;
    const campfire = FACILITIES.find(f => f.id === 'campfire')!;
    if (Math.abs(this.player.x - campfire.x) < 100 && !gameManager.isDead()) {
      gameManager.modifyHealth(Number(gameManager.getBalance('stats.health_regen_campfire', 1)) * dt);
    }
  }

  private updateTradeDistance(): void {
    if (!this.tradeMode) return;
    const trader = FACILITIES.find(f => f.id === 'trader')!;
    if (Math.abs(this.player.x - trader.x) > trader.radius * 2) {
      this.exitTradeMode();
    }
  }

  private updateInteractPrompt(): void {
    if (!this.promptEl || !this.infoCardEl) return;
    if (uiManager.inputBlocked || this.isTyping() || gameManager.isDead()) {
      this.promptEl.style.display = 'none';
      this.infoCardEl.style.display = 'none';
      return;
    }
    const target = interactRegistry.nearest(this.mapKey, this.player.x, this.player.y - 20);
    if (!target) {
      this.promptEl.style.display = 'none';
      this.infoCardEl.style.display = 'none';
      return;
    }
    const cam = this.cameras.main;
    const sx = (target.x - cam.scrollX) / 640;
    const sy = (target.y - 60 - cam.scrollY) / 360;
    if (sx < -0.1 || sx > 1.1 || sy < -0.1 || sy > 1.1) {
      this.promptEl.style.display = 'none';
      this.infoCardEl.style.display = 'none';
      return;
    }
    // 采集物：显示物质信息卡（名称 + 化学式 + 作用解释）
    const collectable = this.collectables.find(c => c.active && c === target);
    if (collectable) {
      this.promptEl.style.display = 'none';
      const sub = recipeDB.getSubstance(collectable.substanceId);
      const item = itemEffects.item(collectable.substanceId);
      const name = sub.name ?? item.name ?? collectable.substanceId;
      const formula = sub.formula ? ` ${sub.formula}` : '';
      const line = String(sub.codex_line ?? item.tip_id ?? '');
      this.infoCardEl.innerHTML =
        `<div class="info-title">${name}${formula}</div>` +
        (line ? `<div class="info-line">${line}</div>` : '') +
        `<div class="info-key">${gameManager.getUiString('prompt_interact')}</div>`;
      this.infoCardEl.style.left = `${sx * 100}%`;
      this.infoCardEl.style.top = `${sy * 100}%`;
      this.infoCardEl.style.transform = 'translate(-50%, -100%)';
      this.infoCardEl.style.display = 'block';
      return;
    }
    this.infoCardEl.style.display = 'none';
    this.promptEl.textContent = target.getInteractPrompt();
    this.promptEl.style.left = `${sx * 100}%`;
    this.promptEl.style.top = `${sy * 100}%`;
    this.promptEl.style.transform = 'translate(-50%, -100%)';
    this.promptEl.style.display = 'block';
  }

  // 怪物对策提示：接触怪物显示消灭方式；持有对应武器时给出数字键提示（无武器不显示按键）
  private updateCombatPrompt(): void {
    if (!this.combatPromptEl) return;
    if (uiManager.inputBlocked || this.isTyping() || gameManager.isDead()) {
      this.combatPromptEl.style.display = 'none';
      return;
    }
    const RANGE = 90;
    const ghost = this.ghosts.find(g => !g.dead && g.mapKey === this.mapKey &&
      Math.hypot(g.x - this.player.x, g.y - this.player.y) < RANGE);
    const slime = this.slimes.find(s => !s.dead && s.mapKey === this.mapKey &&
      Math.hypot(s.x - this.player.x, s.y - this.player.y) < RANGE);
    const monster = ghost ?? slime;
    if (!monster) {
      this.combatPromptEl.style.display = 'none';
      return;
    }
    const weaponId = ghost ? 'activated_carbon' : 'neutral_spray';
    const slotIndex = inventory.slots.findIndex(s => s.id === weaponId && s.count > 0);
    if (slotIndex >= 0) {
      // 持有武器：显示专属攻击键提示（消耗品，用一次少一个）
      const weapon = itemEffects.item(weaponId);
      this.combatPromptEl.textContent = `按 F 使用 ${weapon.name}（消耗品）`;
      const cam = this.cameras.main;
      const sx = (monster.x - cam.scrollX) / 640;
      const sy = (monster.y - 70 - cam.scrollY) / 360;
      this.combatPromptEl.style.left = `${sx * 100}%`;
      this.combatPromptEl.style.top = `${sy * 100}%`;
      this.combatPromptEl.style.transform = 'translate(-50%, -100%)';
      this.combatPromptEl.style.display = 'block';
    } else {
      // 无武器：显示消灭方式提示（每次进图/每天只提示一次）
      this.combatPromptEl.style.display = 'none';
      if (ghost && !this.carbonHintShown) {
        this.carbonHintShown = true;
        knowledgeTip.show('sys_hint_carbon');
      }
      if (slime && !this.sprayHintShown) {
        this.sprayHintShown = true;
        knowledgeTip.show('sys_hint_spray');
      }
    }
  }

  private updateBubbleTarget(): void {
    const cam = this.cameras.main;
    tipsLayer.bubbleTarget = {
      x: (this.player.x - cam.scrollX) / 640,
      y: (this.player.y - 78 - cam.scrollY) / 360,
    };
  }
}

