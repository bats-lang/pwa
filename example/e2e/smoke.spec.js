import { test, expect } from '@playwright/test';

test('WASM app renders BATS PWA text', async ({ page }) => {
  const errors = [];
  const logs = [];
  page.on('pageerror', err => {
    errors.push(err.message);
    console.error('PAGE ERROR:', err.message);
  });
  page.on('console', msg => logs.push(`[${msg.type()}] ${msg.text()}`));

  await page.goto('/');
  await page.waitForTimeout(5000);

  const html = await page.content();
  console.log('PAGE HTML (first 2000):', html.substring(0, 2000));
  console.log('LOGS:', logs);
  console.log('ERRORS:', errors);

  const root = await page.locator('#bats-root').innerHTML().catch(() => 'NOT FOUND');
  console.log('BATS-ROOT innerHTML:', root);

  await page.waitForFunction(
    () => document.body.textContent.includes('BATS PWA'),
    { timeout: 15000 }
  );

  const bodyText = await page.evaluate(() => document.body.textContent);
  expect(bodyText).toContain('BATS PWA');
  expect(errors.length).toBe(0);
});
