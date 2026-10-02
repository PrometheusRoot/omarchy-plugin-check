// Four e2e specs against `astro preview` of the committed fixture (tests/fixtures/api/v1).
// Browser: Playwright's Chromium (`npx playwright install chromium`), or a system one via
// PLAYWRIGHT_CHROMIUM=/usr/bin/chromium.
import { defineConfig } from '@playwright/test';

const port = 4330;
const base = '/omarchy-plugin-check/';
const executablePath = process.env.PLAYWRIGHT_CHROMIUM;

export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: `http://localhost:${port}${base}`,
    colorScheme: 'dark',
    ...(executablePath ? { launchOptions: { executablePath } } : {}),
  },
  webServer: {
    command: `npx astro build && npx astro preview --port ${port}`,
    url: `http://localhost:${port}${base}`,
    reuseExistingServer: false,
    timeout: 180_000,
    env: { OPC_API_DIR: 'tests/fixtures/api/v1', OPC_SITE_BASE: base },
  },
});
