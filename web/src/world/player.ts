// 玩家：自写平台移动（重力/跳跃/坡地跟随），不用物理引擎，杜绝物理 bug
import Phaser from 'phaser';
import { gameManager } from '../core/game_manager';
import { groundY } from './maps';
import { createAnim, setDisplayHeight, DISPLAY_SIZE } from './sprite_factory';
import { inventory } from '../gameplay/inventory';
import { itemEffects } from '../gameplay/item_effects';

export class Player {
  sprite!: Phaser.GameObjects.Sprite;
  x = 0;
  y = 0;
  vx = 0;
  vy = 0;
  onGround = true;
  facing = 1; // 1 右 -1 左
  inputBlocked = false;
  mapKey = 'main';
  private scene: Phaser.Scene;
  private state: 'idle' | 'run' | 'jump' | 'pickup' | 'death' | 'crafting' | 'learning' = 'idle';
  private stateLock = 0;

  inventory = inventory;
  itemEffects = itemEffects;

  constructor(scene: Phaser.Scene) {
    this.scene = scene;
  }

  create(mapKey: string, x: number): void {
    this.mapKey = mapKey;
    this.x = x;
    this.y = groundY(mapKey, x);
    this.sprite = this.scene.add.sprite(this.x, this.y, 'player', 'idle_0');
    setDisplayHeight(this.sprite, DISPLAY_SIZE.player.h);
    this.sprite.setOrigin(0.5, 1); // 脚底锚点
    createAnim(this.scene, 'player', 'idle', { frameRate: 4 });
    createAnim(this.scene, 'player', 'run', { frameRate: 10 });
    createAnim(this.scene, 'player', 'jump', { frameRate: 8, repeat: 0 });
    createAnim(this.scene, 'player', 'pickup', { frameRate: 8, repeat: 0 });
    createAnim(this.scene, 'player', 'death', { frameRate: 6, repeat: 0 });
    createAnim(this.scene, 'player', 'crafting', { frameRate: 6 });
    createAnim(this.scene, 'player', 'learning', { frameRate: 4 });
    this.play('idle');
  }

  play(state: typeof this.state): void {
    if (this.state === state) return;
    this.state = state;
    this.sprite.play(`player_${state}`, true);
  }

  playOnce(state: typeof this.state, ms: number): void {
    this.play(state);
    this.stateLock = ms;
  }

  teleport(mapKey: string, x: number): void {
    this.mapKey = mapKey;
    this.x = x;
    this.y = groundY(mapKey, x);
    this.vx = 0;
    this.vy = 0;
    this.syncSprite();
  }

  update(deltaMs: number, keys: { left: boolean; right: boolean; jump: boolean }): void {
    const dt = deltaMs / 1000;
    if (this.stateLock > 0) {
      this.stateLock -= deltaMs;
      if (this.stateLock <= 0 && this.state !== 'death') this.play(this.onGround ? 'idle' : 'jump');
    }
    if (gameManager.isDead()) {
      if (this.state !== 'death') this.play('death');
      this.vx = 0;
      this.syncSprite();
      return;
    }
    const locked = this.stateLock > 0 || this.inputBlocked;
    const speed = Number(gameManager.getBalance('player.move_speed', 110)) * gameManager.moveSpeedMultiplier();
    const gravity = Number(gameManager.getBalance('player.gravity', 900));
    const jumpV = Number(gameManager.getBalance('player.jump_velocity', -300));

    let dir = 0;
    if (!locked) {
      if (keys.left) dir -= 1;
      if (keys.right) dir += 1;
    }
    this.vx = dir * speed;
    if (dir !== 0) this.facing = dir;

    const prevY = this.y;
    this.x += this.vx * dt;
    const mapW = this.mapKey === 'main' ? 3072 : 1024;
    this.x = Math.max(24, Math.min(mapW - 24, this.x));

    const floor = groundY(this.mapKey, this.x);
    this.vy += gravity * dt;
    this.y += this.vy * dt;
    if (this.y >= floor) {
      this.y = floor;
      if (!this.onGround && prevY < floor - 4) {
        // 落地
      }
      this.vy = 0;
      this.onGround = true;
    } else if (this.y < floor - 1) {
      this.onGround = false;
    }
    // 坡地跟随：在地面且地面下降时贴合
    if (this.onGround && this.vy === 0) {
      this.y = floor;
    }

    if (!locked && keys.jump && this.onGround) {
      this.vy = jumpV;
      this.onGround = false;
    }

    // 动画状态
    if (this.stateLock <= 0) {
      if (!this.onGround) this.play('jump');
      else if (this.vx !== 0) this.play('run');
      else this.play('idle');
    }
    this.syncSprite();
  }

  private syncSprite(): void {
    this.sprite.setPosition(this.x, this.y);
    this.sprite.setFlipX(this.facing < 0);
  }

  getEquippedItemIds(): string[] {
    return itemEffects.equippedIds();
  }
}
