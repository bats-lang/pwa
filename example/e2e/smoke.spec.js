import { test, expect } from '@playwright/test';

const loaded = async page => {
  await page.goto('/');
  await page.waitForFunction(() => document.body.textContent.includes('BATS PWA'), { timeout: 15000 });
};

test('WASM app renders BATS PWA text', async ({ page }) => {
  const errors = [];
  page.on('pageerror', err => errors.push(err.message));
  await loaded(page);
  const bodyText = await page.evaluate(() => document.body.textContent);
  expect(bodyText).toContain('BATS PWA');
  expect(errors.length).toBe(0);
});

// pwa emits no JS logic (bats-lang/pwa#49): the page's one script is
// bridge's, and nothing marks the page or acts on it but the app
test('the page holds no script but bridge\'s, and marks nothing of its own', async ({ page, request }) => {
  const html = await (await request.get('/')).text();
  const scripts = html.match(/<script\b[^>]*>/g) || [];
  expect(scripts).toEqual(['<script type="module" src="bridge.js">']);
  expect(html).not.toMatch(/<script>/);
  await page.addInitScript(() => {
    window.persistAsked = 0;
    navigator.storage.persisted = () => Promise.resolve(false);
    navigator.storage.persist = () => { window.persistAsked++; return Promise.resolve(true); };
  });
  await loaded(page);
  // no pwa-* mark on the page, and no element of the app's touched
  expect(await page.evaluate(() => [...document.documentElement.classList].filter(c => c.startsWith('pwa-')))).toEqual([]);
  expect(await page.evaluate(() => document.querySelectorAll('[id^="pwa-"]').length)).toBe(0);
  // a file given to the page asks nothing by itself: that is the app's
  await page.evaluate(() => {
    const input = document.createElement('input');
    input.type = 'file';
    input.id = 'given-file';
    document.body.append(input);
  });
  await page.setInputFiles('#given-file', { name: 'book.txt', mimeType: 'text/plain', buffer: Buffer.from('a book') });
  await page.waitForTimeout(200);
  expect(await page.evaluate(() => window.persistAsked)).toBe(0);
});

test('a file the system opens with the app reaches it through the bridge, launchQueue\'s only consumer', async ({ page }) => {
  await page.addInitScript(() => {
    window.consumers = [];
    Object.defineProperty(window, 'launchQueue', { value: { setConsumer: f => { window.consumers.push(f); } }, configurable: true });
  });
  await loaded(page);
  // one consumer, bridge's: the page's own scripts set none
  expect(await page.evaluate(() => window.consumers.length)).toBe(1);
  await page.evaluate(() => {
    window.consumers[0]({ files: [{ getFile: () => Promise.resolve(new File(['a book'], 'opened.txt', { type: 'text/plain' })) }] });
  });
  // the app, listening for external files, shows the file's name
  await expect(page.locator('#opened')).toHaveText('opened.txt');
});

test('a file shared with the installed app is kept by bridge\'s service worker and reaches the app', async ({ page }) => {
  await loaded(page);
  // once the service worker has the page
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, { timeout: 15000 });
  const redirected = await page.evaluate(async () => {
    const form = new FormData();
    form.append('file', new File(['shared words'], 'shared.txt', { type: 'text/plain' }));
    const r = await fetch('share-target', { method: 'POST', body: form, redirect: 'manual' });
    return r.type;
  });
  expect(redirected).toBe('opaqueredirect');
  // kept by bridge's worker, in its own cache
  expect(await page.evaluate(async () => (await (await caches.open('bats-shared')).keys()).length)).toBe(1);
  await page.goto('/?shared=1');
  await expect(page.locator('#opened')).toHaveText('shared.txt');
  expect(await page.evaluate(() => location.search)).toBe('');
});

// The Android app's activity calls bridge's entry points and nothing
// else: a file it hands over, and a volume key, here called as it calls
// them
test('the Android app\'s entry points: a file handed over reaches the app, and a volume key it does not take is left', async ({ page }) => {
  await page.route('**/_capacitor_file_/**', r => r.fulfill({ body: 'handed words', contentType: 'application/octet-stream' }));
  await loaded(page);
  const handed = await page.evaluate(() => globalThis.batsNative.deliverFile('/_capacitor_file_/data/cache/incoming/file1.bin', 'handed.txt'));
  expect(handed).toBe(true);
  await expect(page.locator('#opened')).toHaveText('handed.txt');
  // the example app does not take the volume keys
  expect(await page.evaluate(() => globalThis.batsNative.key('AudioVolumeUp'))).toBe(false);
});
