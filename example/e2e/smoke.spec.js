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

test('where the browser offers to install the app, the page is marked, and a click on an install element asks it to', async ({ page }) => {
  await page.goto('/');
  await page.waitForFunction(() => document.body.textContent.includes('BATS PWA'), { timeout: 15000 });
  const marked = name => page.evaluate(n => document.documentElement.classList.contains(n), name);
  expect(await marked('pwa-can-install')).toBe(false);
  await page.evaluate(() => {
    window.prompted = 0;
    const e = new Event('beforeinstallprompt', { cancelable: true });
    e.prompt = () => { window.prompted++; return Promise.resolve(); };
    window.dispatchEvent(e);
    window.bannerKept = e.defaultPrevented;
    const b = document.createElement('button');
    b.textContent = 'Install';
    b.dataset.pwaInstall = 'y';
    document.body.append(b);
  });
  expect(await marked('pwa-can-install')).toBe(true);
  expect(await page.evaluate(() => window.bannerKept)).toBe(true);
  await page.getByRole('button', { name: 'Install' }).click();
  expect(await page.evaluate(() => window.prompted)).toBe(1);
  // the offer is used once
  expect(await marked('pwa-can-install')).toBe(false);
  await page.getByRole('button', { name: 'Install' }).click();
  expect(await page.evaluate(() => window.prompted)).toBe(1);
  // not iOS: no Home Screen mark
  expect(await marked('pwa-ios-browser')).toBe(false);
});

test('on iOS Safari outside the Home Screen, the page is marked for the app to say how to add it', async ({ page }) => {
  await page.addInitScript(() => Object.defineProperty(navigator, 'standalone', { value: false }));
  await page.goto('/');
  await page.waitForFunction(() => document.body.textContent.includes('BATS PWA'), { timeout: 15000 });
  expect(await page.evaluate(() => document.documentElement.classList.contains('pwa-ios-browser'))).toBe(true);
});
