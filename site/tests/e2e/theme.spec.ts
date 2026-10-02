import { expect, test } from '@playwright/test';

test('theme: T cycles skins and the choice survives a reload', async ({ page }) => {
  await page.goto('about/');
  const html = page.locator('html');
  await expect(html).not.toHaveAttribute('data-skin', /.+/);
  await page.keyboard.press('t');
  await expect(html).toHaveAttribute('data-skin', 'tokyo-night');
  await page.keyboard.press('t');
  await expect(html).toHaveAttribute('data-skin', 'catppuccin');
  await page.getByRole('button', { name: /cycle theme/ }).click();
  await expect(html).toHaveAttribute('data-skin', 'gruvbox');
  await expect(page.locator('#themeName')).toHaveText('gruvbox');
  await page.reload();
  await expect(html).toHaveAttribute('data-skin', 'gruvbox');
  // Typing in a field never switches the theme.
  await page.goto('./');
  await page.getByLabel('search plugins').press('t');
  await expect(html).toHaveAttribute('data-skin', 'gruvbox');
});
