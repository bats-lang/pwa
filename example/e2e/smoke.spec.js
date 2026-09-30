import { test, expect } from '@playwright/test';

test('WASM app renders BATS PWA text', async ({ page }) => {
  const errors = [];
  page.on('pageerror', err => errors.push(err.message));

  await page.goto('/');

  await page.waitForFunction(
    () => document.body.textContent.includes('BATS PWA'),
    { timeout: 15000 }
  );

  const bodyText = await page.evaluate(() => document.body.textContent);
  expect(bodyText).toContain('BATS PWA');
  expect(errors.length).toBe(0);
});

test('storage is asked to be persistent once the user gives the app a file, and only once', async ({ page }) => {
  await page.addInitScript(() => {
    window.persistAsked = 0;
    navigator.storage.persisted = () => Promise.resolve(false);
    navigator.storage.persist = () => { window.persistAsked++; return Promise.resolve(true); };
  });
  await page.goto('/');
  await page.waitForFunction(() => document.body.textContent.includes('BATS PWA'), { timeout: 15000 });
  await page.evaluate(() => {
    const input = document.createElement('input');
    input.type = 'file';
    input.id = 'given-file';
    document.body.append(input);
  });
  // not before
  await page.mouse.click(5, 5);
  expect(await page.evaluate(() => window.persistAsked)).toBe(0);
  const file = { name: 'book.txt', mimeType: 'text/plain', buffer: Buffer.from('a book') };
  await page.setInputFiles('#given-file', file);
  await expect.poll(() => page.evaluate(() => window.persistAsked)).toBe(1);
  await page.setInputFiles('#given-file', { ...file, name: 'another.txt' });
  await page.waitForTimeout(200);
  expect(await page.evaluate(() => window.persistAsked)).toBe(1);
});
