// 类型化事件总线：所有跨模块事件的唯一通道（§3.9）
export interface EventMap {
  oxygen_changed: { current: number; max: number };
  energy_changed: { current: number; max: number };
  health_changed: { current: number; max: number };
  zone_changed: { zoneId: string };
  day_started: { dayCount: number };
  night_started: { dayCount: number };
  resources_respawned: Record<string, never>;
  player_died: { deathPosition: { x: number; y: number } };
  player_respawned: Record<string, never>;
  flag_changed: { key: string; value: boolean };
  tip_shown: { tipId: string };
  tip_finished: { tipId: string };
  reply_started: { mentorId: string };
  reply_finished: { mentorId: string; fullText: string; offline: boolean };
  mode_changed: { offline: boolean };
  inventory_changed: Record<string, never>;
  substance_discovered: { substanceId: string };
  explosion_triggered: Record<string, never>;
  purity_check_performed: Record<string, never>;
  pause_toggled: { paused: boolean };
  // 场景层辅助事件（不进冻结面，但同样走总线）
  world_travel: { to: string };
  ui_panel_changed: { panel: string };
  [key: string]: unknown;
}

type Handler<T> = (payload: T) => void;

export class EventBus {
  private handlers = new Map<string, Set<Handler<never>>>();

  on<K extends keyof EventMap>(event: K, handler: Handler<EventMap[K]>): () => void {
    let set = this.handlers.get(event as string);
    if (!set) {
      set = new Set();
      this.handlers.set(event as string, set);
    }
    set.add(handler as Handler<never>);
    return () => this.off(event, handler);
  }

  off<K extends keyof EventMap>(event: K, handler: Handler<EventMap[K]>): void {
    this.handlers.get(event as string)?.delete(handler as Handler<never>);
  }

  emit<K extends keyof EventMap>(event: K, payload: EventMap[K]): void {
    const set = this.handlers.get(event as string);
    if (!set) return;
    for (const h of [...set]) {
      try {
        (h as Handler<EventMap[K]>)(payload);
      } catch (e) {
        console.error(`eventBus: handler for ${String(event)} threw`, e);
      }
    }
  }

  clear(): void {
    this.handlers.clear();
  }
}

export const eventBus = new EventBus();
