import { describe, it, expect, beforeEach } from 'vitest';
import { inventory } from '../../src/gameplay/inventory';
import { injectAllData, resetState } from '../helpers';

beforeEach(() => {
  injectAllData();
  resetState();
  inventory.clear();
});

describe('UT-G02 背包', () => {
  it('堆叠到 99 后溢出到新格', () => {
    inventory.addItem('o2', 99);
    inventory.addItem('o2', 5);
    expect(inventory.countOf('o2')).toBe(104);
    expect(inventory.slots.length).toBe(2);
    expect(inventory.slots[0].count).toBe(99);
    expect(inventory.slots[1].count).toBe(5);
  });

  it('背包满时 addItem 返回未装入数量，不静默丢弃', () => {
    // 24 格 × 99 = 2376 容量
    for (let i = 0; i < 24; i++) {
      inventory.addItem(`item_${i}`, 99);
    }
    expect(inventory.slots.length).toBe(24);
    const leftover = inventory.addItem('o2', 10);
    expect(leftover).toBe(10);
    expect(inventory.countOf('o2')).toBe(0);
  });

  it('removeItem 数量不足返回 false 且状态不变', () => {
    inventory.addItem('c', 3);
    const ok = inventory.removeItem('c', 5);
    expect(ok).toBe(false);
    expect(inventory.countOf('c')).toBe(3);
  });

  it('removeItem 正常扣除并清空格子', () => {
    inventory.addItem('c', 3);
    expect(inventory.removeItem('c', 2)).toBe(true);
    expect(inventory.countOf('c')).toBe(1);
    expect(inventory.removeItem('c', 1)).toBe(true);
    expect(inventory.slots.length).toBe(0);
  });

  it('clear 返回全部物品快照', () => {
    inventory.addItem('o2', 5);
    inventory.addItem('c', 3);
    const snap = inventory.clear();
    expect(snap.length).toBe(2);
    expect(inventory.slots.length).toBe(0);
  });
});
