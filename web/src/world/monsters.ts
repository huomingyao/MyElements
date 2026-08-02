// 怪物：CO 幽灵（追踪、8/s、活性炭砸、口罩免疫）与 酸雾怪（夜刷、冲撞 -10、喷雾消灭）
import Phaser from 'phaser';
import { gameManager } from '../core/game_manager';
import { knowledgeTip } from '../core/knowledge_tip';
import { createAnim, setDisplayHeight, DISPLAY_SIZE } from './sprite_factory';
import { sfx } from '../audio/sfx';

export class Ghost {
  sprite: Phaser.GameObjects.Sprite;
  x: number;
  y: number;
  dead = false;
  readonly mapKey: string;
  private scene: Phaser.Scene;
  private warned = false;

  constructor(scene: Phaser.Scene, mapKey: string, x: number, y: number) {
    this.scene = scene;
    this.mapKey = mapKey;
    this.x = x;
    this.y = y;
    createAnim(scene, 'ghost', 'run', { frameRate: 8 });
    createAnim(scene, 'ghost', 'death', { frameRate: 8, repeat: 0 });
    this.sprite = scene.add.sprite(x, y, 'ghost', 'run_0');
    setDisplayHeight(this.sprite, DISPLAY_SIZE.ghost.h);
    this.sprite.setOrigin(0.5, 0.9);
    this.sprite.setAlpha(0.85);
    this.sprite.play('ghost_run');
  }

  update(dt: number, playerX: number, playerY: number, playerInAcademy: boolean): void {
    if (this.dead) return;
    // 学院内不追踪（安全区）
    if (!playerInAcademy) {
      const speed = Number(gameManager.getBalance('monsters.co_ghost_speed', 28));
      const dx = playerX - this.x;
      const dy = playerY - this.y;
      const d = Math.hypot(dx, dy);
      if (d > 4) {
        this.x += (dx / d) * speed * dt;
        this.y += (dy / d) * speed * dt;
        this.sprite.setFlipX(dx < 0);
      }
      // 首次接近警示
      if (!this.warned && d < 150) {
        this.warned = true;
        knowledgeTip.showOnce('warn_co');
      }
      // 接触掉血 8/s（对策：活性炭砸它）
      if (d < 30) {
        gameManager.modifyHealth(-Number(gameManager.getBalance('damage.co_ghost_per_second', 8)) * dt);
      }
    }
    this.sprite.setPosition(this.x, this.y);
  }

  kill(showTip = true): void {
    if (this.dead) return;
    this.dead = true;
    this.sprite.play('ghost_death');
    if (showTip) knowledgeTip.show('sys_carbon');
    this.sprite.once('animationcomplete', () => this.sprite.destroy());
  }

  destroy(): void {
    this.sprite.destroy();
  }
}

export class Slime {
  sprite: Phaser.GameObjects.Sprite;
  x: number;
  y: number;
  dead = false;
  readonly mapKey: string;
  private scene: Phaser.Scene;
  private dirX = 0;
  private dirY = 0;
  private hitCooldown = 0;
  private life: number;
  private boundX0: number;
  private boundX1: number;

  constructor(scene: Phaser.Scene, mapKey: string, x: number, y: number, boundX0: number, boundX1: number) {
    this.scene = scene;
    this.mapKey = mapKey;
    this.x = x;
    this.y = y;
    this.boundX0 = boundX0;
    this.boundX1 = boundX1;
    this.life = Number(gameManager.getBalance('monsters.acid_mist_lifetime_seconds', 200));
    createAnim(scene, 'slime', 'run', { frameRate: 8 });
    createAnim(scene, 'slime', 'death', { frameRate: 9, repeat: 0 });
    this.sprite = scene.add.sprite(x, y, 'slime', 'run_0');
    setDisplayHeight(this.sprite, DISPLAY_SIZE.slime.h);
    this.sprite.setOrigin(0.5, 1);
    this.sprite.play('slime_run');
  }

  update(dt: number, playerX: number, playerY: number): void {
    if (this.dead) return;
    this.life -= dt;
    if (this.life <= 0) {
      this.kill(false);
      return;
    }
    if (this.hitCooldown > 0) this.hitCooldown -= dt;
    const speed = Number(gameManager.getBalance('monsters.acid_mist_speed', 90));
    // 锁定方向直线冲撞；无方向或出界时重新锁定
    const needLock = (this.dirX === 0 && this.dirY === 0) || this.x <= this.boundX0 || this.x >= this.boundX1;
    if (needLock) {
      const dx = playerX - this.x;
      const dy = playerY - this.y;
      const d = Math.hypot(dx, dy) || 1;
      this.dirX = dx / d;
      this.dirY = dy / d;
      this.x = Math.max(this.boundX0 + 2, Math.min(this.boundX1 - 2, this.x));
    }
    this.x += this.dirX * speed * dt;
    this.y += this.dirY * speed * dt;
    this.sprite.setFlipX(this.dirX < 0);
    // 冲撞命中 -10（单次，冷却 1.2s）
    const d = Math.hypot(playerX - this.x, playerY - this.y);
    if (d < 32 && this.hitCooldown <= 0) {
      this.hitCooldown = 1.2;
      gameManager.modifyHealth(-Number(gameManager.getBalance('damage.acid_mist_per_hit', 10)));
      sfx.hurt();
    }
    this.sprite.setPosition(this.x, this.y);
  }

  kill(showTip = true): void {
    if (this.dead) return;
    this.dead = true;
    this.sprite.play('slime_death');
    if (showTip) knowledgeTip.show('sys_spray');
    this.sprite.once('animationcomplete', () => this.sprite.destroy());
  }

  destroy(): void {
    this.sprite.destroy();
  }
}
