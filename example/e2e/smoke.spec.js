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

test('read aloud: sentence by sentence, marked, turning on with the next element, at the speed chosen', async ({ page }) => {
  await page.addInitScript(() => {
    window.spoken = [];
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const synth = {
      current: null,
      getVoices: () => [{ name: 'Reader', lang: 'en-US', voiceURI: 'reader', default: true }],
      speak(u) { window.spoken.push({ text: u.text, rate: u.rate }); this.current = u; },
      cancel() { this.current = null; },
      addEventListener() {},
    };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
    window.sentenceSpoken = () => { const u = synth.current; synth.current = null; if (u && u.onend) u.onend({}); };
  });
  await page.goto('/');
  await page.waitForFunction(() => document.body.textContent.includes('BATS PWA'), { timeout: 15000 });
  expect(await page.evaluate(() => document.documentElement.classList.contains('pwa-can-speak'))).toBe(true);
  // a text with its next part behind a button, as a reader's pages are
  await page.evaluate(() => {
    document.body.insertAdjacentHTML('beforeend',
      '<div id="text" lang="en"><p>First one. Second one!</p></div>' +
      '<button data-pwa-speak="text" aria-pressed="false">Read</button>' +
      '<button data-pwa-speech-next="y" id="more">More</button>' +
      '<select data-pwa-speech-rate="y" aria-label="Speed"></select>');
    document.getElementById('more').addEventListener('click', () => {
      document.getElementById('text').innerHTML = '<p>Third one.</p>';
    });
  });
  await expect(page.getByRole('combobox', { name: 'Speed' }).locator('option')).toHaveCount(6);
  await page.getByRole('combobox', { name: 'Speed' }).selectOption('1.25');
  await page.getByRole('button', { name: 'Read' }).click();
  await expect(page.getByRole('button', { name: 'Read' })).toHaveAttribute('aria-pressed', 'true');
  await expect.poll(() => page.evaluate(() => window.spoken)).toEqual([{ text: 'First one.', rate: 1.25 }]);
  expect(await page.evaluate(() => CSS.highlights.has('pwa-spoken'))).toBe(true);
  await page.evaluate(() => window.sentenceSpoken());
  await page.evaluate(() => window.sentenceSpoken());
  await expect.poll(() => page.evaluate(() => window.spoken.map(s => s.text))).toEqual(['First one.', 'Second one!', 'Third one.']);
  // paused
  await page.getByRole('button', { name: 'Read' }).click();
  await expect(page.getByRole('button', { name: 'Read' })).toHaveAttribute('aria-pressed', 'false');
  expect(await page.evaluate(() => CSS.highlights.has('pwa-spoken'))).toBe(false);
});
