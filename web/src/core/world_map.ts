// WorldMap：13 区域状态（§3.7，冻结面）。MVP 静态解锁。
import type { Row } from './data_loader';
import { eventBus } from './event_bus';

export class WorldMap {
  private zones: Row[] = [];
  private open_ = false;

  loadFrom(rows: Row[]): void {
    this.zones = rows || [];
  }

  open(): void {
    if (this.open_) return;
    this.open_ = true;
    eventBus.emit('ui_panel_changed', { panel: 'worldmap' });
  }

  close(): void {
    if (!this.open_) return;
    this.open_ = false;
    eventBus.emit('ui_panel_changed', { panel: '' });
  }

  isOpen(): boolean {
    return this.open_;
  }

  isUnlocked(zoneId: string): boolean {
    const z = this.zones.find(z => z.id === zoneId);
    return z ? z.unlocked === true : false;
  }

  allZones(): Row[] {
    return this.zones;
  }

  getZone(zoneId: string): Row {
    return this.zones.find(z => z.id === zoneId) ?? {};
  }
}

export const worldMap = new WorldMap();
