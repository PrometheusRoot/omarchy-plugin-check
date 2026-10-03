import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { siteEnv } from '../../src/lib/env';
import { FIXTURE } from './helpers';

describe('siteEnv', () => {
  it('defaults to the gitignored ../.snapshot next to site/, never an absolute dev path', () => {
    const env = siteEnv({});
    expect(env.apiDir).toBe(resolve('..', '.snapshot', 'api', 'v1'));
    expect(env.base).toBe('/omarchy-plugin-check/');
  });

  it('reads OPC_API_DIR and finds providers.json two levels up', () => {
    const env = siteEnv({ OPC_API_DIR: FIXTURE, OPC_SITE_BASE: 'x' });
    expect(env.apiDir).toBe(FIXTURE);
    expect(env.registry).toBe(resolve(join(FIXTURE, '..', '..', 'providers.json')));
    expect(env.snapshotDir).toBeNull();
    expect(env.base).toBe('/x/');
  });
});
