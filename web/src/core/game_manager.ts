// GameManager：三值 / 昼夜时钟 / 区域判定 / 死亡复活 / 全局标记（§3.2，冻结面）
import { eventBus } from './event_bus';
import type { Row } from './data_loader';

const KNOWN_FLAGS = new Set(['explosion_happened', 'purity_check_unlocked']);

// 数据表缺失时的兜底默认值（不算违规，§NFR-04 口径）
const DEFAULTS: Record<string, unknown> = {
  'stats.oxygen_max': 100, 'stats.energy_max': 100, 'stats.health_max': 100,
  'stats.oxygen_regen_safe': 1.0, 'stats.energy_drain': 0.3,
  'stats.health_regen_campfire': 1.0, 'stats.oxygen_zero_health_drain': 5.0,
  'stats.low_energy_speed_multiplier': 0.5, 'stats.hud_low_oxygen_threshold': 30,
  'stats.tutorial_oxygen_hint_at': 70,
  'daynight.day_duration': 360, 'daynight.night_duration': 180,
  'daynight.night_brightness': 0.35, 'daynight.dark_view_radius': 80, 'daynight.torch_view_radius': 220,
  'damage.co_ghost_per_second': 8, 'damage.acid_mist_per_hit': 10,
  'damage.hydrogen_explosion': 50, 'damage.cuso4_pool_per_second': 5,
  'player.move_speed': 110, 'player.jump_velocity': -300, 'player.gravity': 900, 'player.interact_radius': 28,
  'monsters.co_ghost_speed': 28, 'monsters.acid_mist_speed': 90,
  'monsters.acid_mist_night_count_min': 2, 'monsters.acid_mist_night_count_max': 3,
  'monsters.acid_mist_lifetime_seconds': 200,
  'items.oxygen_tank_restore': 50, 'items.trade_energy_restore': 20,
  'items.campfire_meal_restore': 40, 'items.campfire_daily_limit': 3,
  'inventory.hotbar_slots': 8, 'inventory.stack_limit': 99,
  'llm.timeout_seconds': 8, 'llm.retry_count': 1, 'llm.history_rounds': 4,
  'llm.max_tokens': 300, 'llm.temperature': 0.7, 'llm.input_max_chars': 200,
  'debug.force_purity_unlock': false, 'debug.fast_daynight': false,
};

export class GameManager {
  oxygen = 100;
  energy = 100;
  health = 100;
  oxygenMax = 100;
  energyMax = 100;
  healthMax = 100;

  dayCount = 1;
  timeOfDay = 0;

  explosionHappened = false;
  purityCheckUnlocked = false;

  private zone = 'grassland';
  private balance: Row = {};
  private uiStrings: Record<string, string> = {};
  private deadFired = false;
  private respawnPos = { x: 0, y: 0 };
  private tutorialHintShown = false;

  loadBalance(balance: Row, uiStrings: Record<string, string>): void {
    this.balance = balance || {};
    this.uiStrings = uiStrings || {};
    this.oxygenMax = this.num('stats.oxygen_max');
    this.energyMax = this.num('stats.energy_max');
    this.healthMax = this.num('stats.health_max');
    this.oxygen = this.oxygenMax;
    this.energy = this.energyMax;
    this.health = this.healthMax;
  }

  getBalance(key: string, defaultValue?: unknown): unknown {
    const parts = key.split('.');
    let cur: unknown = this.balance;
    for (const p of parts) cur = cur == null ? undefined : (cur as Row)[p];
    if (cur === undefined) {
      if (key in DEFAULTS) return DEFAULTS[key];
      console.warn(`GameManager: balance 缺键 ${key}，使用传入默认值`);
      return defaultValue;
    }
    return cur;
  }

  num(key: string): number {
    return Number(this.getBalance(key, 0));
  }

  bool(key: string): boolean {
    return this.getBalance(key, false) === true;
  }

  getUiString(key: string): string {
    const v = this.uiStrings[key];
    if (v === undefined || v === '') {
      console.warn(`GameManager: ui_strings 缺 key ${key}`);
      return key;
    }
    return v;
  }

  ui(key: string, n?: number): string {
    const raw = this.getUiString(key);
    return n === undefined ? raw : raw.replace('{n}', String(n));
  }

  // ---- 时间推进（唯一入口）----
  tick(delta: number): void {
    if (this.deadFired) return; // 死亡后冻结结算
    const dayLen = this.num('daynight.day_duration');
    const nightLen = this.num('daynight.night_duration');
    const cycle = dayLen + nightLen;
    const wasNight = this.isNight();
    const prevDay = this.dayCount;
    this.timeOfDay += delta;
    while (this.timeOfDay >= cycle) {
      this.timeOfDay -= cycle;
      this.dayCount += 1;
    }
    const isNightNow = this.isNight();
    if (!wasNight && isNightNow) {
      eventBus.emit('night_started', { dayCount: this.dayCount });
    } else if (wasNight && !isNightNow) {
      eventBus.emit('day_started', { dayCount: this.dayCount });
      eventBus.emit('resources_respawned', {});
    } else if (this.dayCount !== prevDay) {
      eventBus.emit('day_started', { dayCount: this.dayCount });
      eventBus.emit('resources_respawned', {});
    }
    this.settleStats(delta);
  }

  private settleStats(delta: number): void {
    // 氧气净速率 = 安全区回复 − 区域消耗（§2.4.1）
    const zone = this.zone;
    const drainMap = this.getBalance('stats.oxygen_drain', {}) as Row;
    const drain = Number((drainMap as Record<string, number>)[zone] ?? 0);
    const regenZones = new Set(['grassland', 'camp']);
    const regen = regenZones.has(zone) ? this.num('stats.oxygen_regen_safe') : 0;
    const net = regen - drain;
    if (net !== 0) this.modifyOxygen(net * delta);
    // 能量全区一致消耗
    this.modifyEnergy(-this.num('stats.energy_drain') * delta);
    // 氧气归零扣血
    if (this.oxygen <= 0) {
      this.modifyHealth(-this.num('stats.oxygen_zero_health_drain') * delta);
    }
    // 教学提示：氧气首次跌破阈值
    if (!this.tutorialHintShown && this.oxygen < this.num('stats.tutorial_oxygen_hint_at')) {
      this.tutorialHintShown = true;
      eventBus.emit('tutorial_oxygen_hint', {});
    }
  }

  oxygenNetRate(): number {
    const drainMap = this.getBalance('stats.oxygen_drain', {}) as Record<string, number>;
    const drain = Number(drainMap[this.zone] ?? 0);
    const regen = ['grassland', 'camp'].includes(this.zone) ? this.num('stats.oxygen_regen_safe') : 0;
    return regen - drain;
  }

  isNight(): boolean {
    return this.timeOfDay >= this.num('daynight.day_duration');
  }

  currentZone(): string {
    return this.zone;
  }

  setZone(zoneId: string): void {
    if (zoneId === this.zone) return;
    this.zone = zoneId;
    eventBus.emit('zone_changed', { zoneId });
  }

  modifyOxygen(delta: number): void {
    const next = Math.max(0, Math.min(this.oxygenMax, this.oxygen + delta));
    if (next === this.oxygen) return;
    this.oxygen = next;
    eventBus.emit('oxygen_changed', { current: this.oxygen, max: this.oxygenMax });
  }

  modifyEnergy(delta: number): void {
    const next = Math.max(0, Math.min(this.energyMax, this.energy + delta));
    if (next === this.energy) return;
    this.energy = next;
    eventBus.emit('energy_changed', { current: this.energy, max: this.energyMax });
  }

  modifyHealth(delta: number): void {
    const next = Math.max(0, Math.min(this.healthMax, this.health + delta));
    if (next === this.health) return;
    this.health = next;
    eventBus.emit('health_changed', { current: this.health, max: this.healthMax });
    if (this.health <= 0 && !this.deadFired) {
      this.deadFired = true;
      eventBus.emit('player_died', { deathPosition: { ...this.respawnPos } });
    }
  }

  moveSpeedMultiplier(): number {
    return this.energy <= 0 ? this.num('stats.low_energy_speed_multiplier') : 1.0;
  }

  sleepUntilMorning(): void {
    const dayLen = this.num('daynight.day_duration');
    const nightLen = this.num('daynight.night_duration');
    const cycle = dayLen + nightLen;
    if (this.isNight()) {
      this.timeOfDay = cycle; // 触发跨天
    } else {
      this.timeOfDay = dayLen; // 直接到夜晚再跳清晨？不：白天睡觉也跳到次日清晨
      this.timeOfDay = cycle;
    }
    // 归一到下一清晨
    this.timeOfDay = 0;
    this.dayCount += 1;
    this.deadFired = false;
    this.modifyHealth(this.healthMax);
    eventBus.emit('day_started', { dayCount: this.dayCount });
    eventBus.emit('resources_respawned', {});
  }

  respawnPlayer(): void {
    this.deadFired = false;
    this.oxygen = this.oxygenMax;
    this.energy = this.energyMax;
    this.health = this.healthMax;
    // 死亡复活：时间回到第一天的白天刚开始
    this.dayCount = 1;
    this.timeOfDay = 0;
    eventBus.emit('oxygen_changed', { current: this.oxygen, max: this.oxygenMax });
    eventBus.emit('energy_changed', { current: this.energy, max: this.energyMax });
    eventBus.emit('health_changed', { current: this.health, max: this.healthMax });
    eventBus.emit('day_started', { dayCount: this.dayCount });
    eventBus.emit('resources_respawned', {});
    eventBus.emit('player_respawned', {});
  }

  isDead(): boolean {
    return this.deadFired;
  }

  setFlag(key: string, value: boolean): void {
    if (!KNOWN_FLAGS.has(key)) {
      console.warn(`GameManager: 未知标记 ${key}`);
      return;
    }
    if (key === 'explosion_happened') this.explosionHappened = value;
    if (key === 'purity_check_unlocked') this.purityCheckUnlocked = value;
    eventBus.emit('flag_changed', { key, value });
  }

  getFlag(key: string): boolean {
    if (!KNOWN_FLAGS.has(key)) {
      console.warn(`GameManager: 读取未知标记 ${key}`);
      return false;
    }
    return key === 'explosion_happened' ? this.explosionHappened : this.purityCheckUnlocked;
  }

  setRespawnReferencePosition(x: number, y: number): void {
    this.respawnPos = { x, y };
  }

  resetStats(): void {
    this.oxygen = this.oxygenMax;
    this.energy = this.energyMax;
    this.health = this.healthMax;
    this.deadFired = false;
    this.tutorialHintShown = false;
  }

  resetClock(): void {
    this.dayCount = 1;
    this.timeOfDay = 0;
    this.deadFired = false;
  }

  reloadConfig(balance: Row, uiStrings: Record<string, string>): void {
    this.loadBalance(balance, uiStrings);
  }
}

export const gameManager = new GameManager();
