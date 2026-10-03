import { describe, expect, it } from 'vitest';
import { copyLabel, GETS, INSTALL_CMD, STORE_REPO } from '../../src/lib/install';

describe('install (ADR-0042)', () => {
  it('is the one omarchy-store command', () => {
    expect(INSTALL_CMD).toBe('omarchy plugin add https://github.com/PrometheusRoot/omarchy-store --enable');
    expect(INSTALL_CMD).toContain(STORE_REPO);
  });
  it('lists what you get, terse, each with a sprite icon', () => {
    expect(GETS.map((g) => g.title)).toEqual(['store', 'bar shield', 'verified locally', 'optional']);
    for (const g of GETS) {
      expect(g.icon).toMatch(/^i-[a-z]+$/);
      expect(g.text.length).toBeLessThan(70);
    }
  });
  it('copy label', () => {
    expect(copyLabel(true)).toBe('copied');
    expect(copyLabel(false)).toBe('select + copy');
  });
});
