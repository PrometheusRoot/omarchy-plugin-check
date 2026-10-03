import { expect, test } from '@playwright/test';

test('index: search, filter and open a report', async ({ page }) => {
  await page.goto('./');
  await expect(page.locator('#installCmd')).toHaveText(
    'omarchy plugin add https://github.com/PrometheusRoot/omarchy-store --enable',
  );
  const rows = page.locator('#rows .pl');
  await expect(rows.first()).toBeVisible();
  await page.getByLabel('search plugins').fill('clickup');
  await expect(rows).toHaveCount(1);
  await expect(page).toHaveURL(/\?q=clickup/);

  await page.getByLabel('search plugins').fill('');
  await page.locator('#filters [data-f="blocked"]').click();
  await expect(rows).toHaveCount(1);
  await expect(rows.first()).toContainText('Blocked Widget');

  await rows.first().getByRole('link', { name: 'Blocked Widget' }).click();
  await expect(page).toHaveURL(/plugins\/fixture\.blocked-widget\/$/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Blocked Widget');
});
