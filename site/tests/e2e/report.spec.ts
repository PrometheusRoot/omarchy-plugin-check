import { expect, test } from '@playwright/test';

const SECTIONS = [
  'verdict',
  'does',
  'caps',
  'areas',
  'net',
  'deps',
  'secrets',
  'supply',
  'inject',
  'quality',
  'perf',
  'activity',
  'diff',
  'findings',
  'ai',
];

test('report: every section, provider rows, links, no rule ids', async ({ page }) => {
  await page.goto('plugins/omamail/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Omamail');
  const table = page.getByRole('table', { name: 'provider verdicts' });
  await expect(table.locator('tbody tr')).toHaveCount(2);
  const panel = page.locator('#panel-opc');
  for (const s of SECTIONS) await expect(panel.locator(`#sec-opc-${s}`)).toBeVisible();
  await expect(
    page.locator('a[href="https://plugins.omarchy.org/plugin.html?id=omamail"]').first(),
  ).toBeVisible();
  await expect(page.locator('a[href="https://github.com/huacnlee/omamail"]')).toBeVisible();
  // Anti-oracle (ADR-0011): opaque rule ids never reach the page.
  expect(await page.content()).not.toMatch(/\br\.[0-9a-f]{12}\b/);

  // Switching to the marketplace row shows its baseline panel.
  await table.getByRole('button', { name: /mkt/ }).click();
  await expect(page.locator('#panel-marketplace')).toBeVisible();
  await expect(panel).toBeHidden();
  await expect(page.locator('#panel-marketplace')).toContainText('marketplace baseline');
});
