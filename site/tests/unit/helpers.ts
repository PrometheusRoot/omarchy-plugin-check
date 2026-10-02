import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { Meta, PluginDoc } from '../../src/lib/types';

export const FIXTURE = join(import.meta.dirname, '..', 'fixtures', 'api', 'v1');

export function fixtureDocs(): PluginDoc[] {
  const dir = join(FIXTURE, 'plugins');
  return readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(readFileSync(join(dir, f), 'utf8')) as PluginDoc);
}

export const fixtureMeta = (): Meta => JSON.parse(readFileSync(join(FIXTURE, 'meta.json'), 'utf8')) as Meta;

export function doc(id: string): PluginDoc {
  const d = fixtureDocs().find((x) => x.id === id);
  if (!d) throw new Error(`no fixture ${id}`);
  return d;
}
