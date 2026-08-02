// 音频：BGM（素材库音乐，进网站即全局循环）+ WebAudio 程序化音效（无素材依赖，缺失静默）
export class Sfx {
  private ctx: AudioContext | null = null;
  private bgm: HTMLAudioElement | null = null;
  private unlocked = false;
  private bgmStarted = false;

  // 页面加载即调用：立刻尝试自动播放；被浏览器拦截则挂文档级首次交互监听（DOM 点击也能触发）
  init(): void {
    this.bgm = new Audio('assets/audio/bgm/main_theme.mp3');
    this.bgm.loop = true;
    this.bgm.volume = 0.45;
    this.bgm.preload = 'auto';
    // 立即尝试（部分浏览器/已交互过的会话允许自动播放）
    this.tryStartBgm();
    // 文档级首次交互解锁（捕获阶段：DOM 按钮点击、canvas、键盘全覆盖）
    const onFirstGesture = () => {
      this.unlock();
    };
    document.addEventListener('pointerdown', onFirstGesture, { capture: true, once: false });
    document.addEventListener('keydown', onFirstGesture, { capture: true, once: false });
    document.addEventListener('touchstart', onFirstGesture, { capture: true, once: false });
    // 页面重新可见时补偿尝试
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) this.tryStartBgm();
    });
  }

  unlock(): void {
    if (!this.unlocked) {
      this.unlocked = true;
      try {
        this.ctx = new AudioContext();
      } catch {
        this.ctx = null;
      }
    }
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume().catch(() => { /* 静默 */ });
    }
    this.tryStartBgm();
  }

  private tryStartBgm(): void {
    if (!this.bgm) return;
    const p = this.bgm.play();
    if (p) {
      p.then(() => {
        this.bgmStarted = true;
      }).catch(() => {
        // 浏览器 Autoplay 策略拦截：等待下一次交互/可见性变化再试
      });
    } else {
      this.bgmStarted = true;
    }
  }

  isBgmPlaying(): boolean {
    return !!this.bgm && !this.bgm.paused;
  }

  private tone(freq: number, duration: number, type: OscillatorType = 'square', volume = 0.18, slideTo?: number): void {
    if (!this.ctx || this.ctx.state !== 'running') return;
    try {
      const t0 = this.ctx.currentTime;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = type;
      osc.frequency.setValueAtTime(freq, t0);
      if (slideTo !== undefined) osc.frequency.exponentialRampToValueAtTime(Math.max(1, slideTo), t0 + duration);
      gain.gain.setValueAtTime(volume, t0);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + duration);
      osc.connect(gain).connect(this.ctx.destination);
      osc.start(t0);
      osc.stop(t0 + duration);
    } catch { /* 静默 */ }
  }

  private noise(duration: number, volume = 0.3, lowpass = 1000): void {
    if (!this.ctx || this.ctx.state !== 'running') return;
    try {
      const t0 = this.ctx.currentTime;
      const len = Math.floor(this.ctx.sampleRate * duration);
      const buffer = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / len);
      const src = this.ctx.createBufferSource();
      src.buffer = buffer;
      const filter = this.ctx.createBiquadFilter();
      filter.type = 'lowpass';
      filter.frequency.value = lowpass;
      const gain = this.ctx.createGain();
      gain.gain.setValueAtTime(volume, t0);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + duration);
      src.connect(filter).connect(gain).connect(this.ctx.destination);
      src.start(t0);
    } catch { /* 静默 */ }
  }

  pickup(): void { this.tone(880, 0.09, 'square', 0.12); this.tone(1320, 0.14, 'square', 0.1); }
  craftSuccess(): void { this.tone(523, 0.12, 'triangle', 0.16); this.tone(784, 0.2, 'triangle', 0.14); }
  craftFail(): void { this.tone(220, 0.25, 'sawtooth', 0.1, 110); }
  explosion(): void { this.noise(0.9, 0.5, 700); this.tone(90, 0.7, 'sawtooth', 0.3, 30); }
  purity(): void { this.tone(300, 0.18, 'sine', 0.2, 90); }
  hurt(): void { this.tone(180, 0.15, 'sawtooth', 0.14, 90); }
  death(): void { this.tone(330, 0.8, 'triangle', 0.2, 55); }
  sleep(): void { this.tone(440, 0.4, 'sine', 0.1, 220); }
  page(): void { this.tone(660, 0.06, 'square', 0.08); }
  type(): void { this.tone(1100, 0.02, 'square', 0.03); }
  splash(): void { this.noise(0.3, 0.15, 2000); }
  spray(): void { this.noise(0.25, 0.2, 3500); }
  trade(): void { this.tone(988, 0.1, 'triangle', 0.12); this.tone(1319, 0.16, 'triangle', 0.1); }
}

export const sfx = new Sfx();
