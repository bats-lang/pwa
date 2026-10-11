import { defineConfig } from '@playwright/test';

// build-pwa test serves dist/pwa at a port it chooses and says where in
// PWA_TEST_BASE_URL (bats-lang/pwa#82); run by hand, npx playwright test
// serves it itself
const served = process.env.PWA_TEST_BASE_URL;

export default defineConfig({
  testDir: './e2e',
  timeout: 30000,
  use: {
    baseURL: served || 'http://localhost:3737',
    headless: true,
  },
  webServer: served ? undefined : {
    command: 'npx serve dist/pwa -l 3737 --no-clipboard',
    port: 3737,
    reuseExistingServer: !process.env.CI,
  },
  projects: [
    {
      name: 'chromium',
      use: {
        browserName: 'chromium',
        viewport: { width: 1024, height: 768 },
        launchOptions: {
          args: ['--no-sandbox', '--disable-setuid-sandbox'],
        },
      },
    },
  ],
});
