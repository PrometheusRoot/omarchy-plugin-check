import { expect, test } from '@playwright/test';

test('providers: registry cards and phone layout without horizontal scroll', async ({ page }) => {
  await page.goto('providers/');
  for (const id of ['opc', 'marketplace', 'example']) await expect(page.locator(`#p-${id}`)).toBeVisible();
  await expect(page.locator('#p-marketplace')).toContainText('≤caution');
  await expect(page.locator('#p-opc')).toContainText('safe-to-run');
  await expect(page.locator('#p-opc .cover a').first()).toBeVisible();

  await page.setViewportSize({ width: 360, height: 780 });
  for (const path of ['providers/', './', 'plugins/omamail/']) {
    await page.goto(path);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, path).toBeLessThanOrEqual(0);
  }
});
