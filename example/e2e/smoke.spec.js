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

test('storage is asked to be persistent once the user gives the app a file, and only once, and the page marked as it is', async ({ page }) => {
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
  const marked = name => page.evaluate(n => document.documentElement.classList.contains(n), name);
  // not kept yet: at risk
  expect(await marked('pwa-storage-at-risk')).toBe(true);
  expect(await marked('pwa-storage-kept')).toBe(false);
  await page.setInputFiles('#given-file', file);
  await expect.poll(() => page.evaluate(() => window.persistAsked)).toBe(1);
  // granted: kept
  await expect.poll(() => marked('pwa-storage-kept')).toBe(true);
  expect(await marked('pwa-storage-at-risk')).toBe(false);
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

test.describe('night by the local clock', () => {
  test.use({ timezoneId: 'Europe/Paris' });
  test('the page is marked pwa-night from 22:00 to 07:00 local time', async ({ page }) => {
    // 21:59 in Paris (UTC+2 in June)
    await page.clock.install({ time: new Date('2026-06-01T19:59:00Z') });
    await page.goto('/');
    await page.waitForFunction(() => document.body.textContent.includes('BATS PWA'), { timeout: 15000 });
    const night = () => page.evaluate(() => document.documentElement.classList.contains('pwa-night'));
    expect(await night()).toBe(false);
    // the local offset, for the local day: Paris in June is 120 minutes east
    expect(await page.evaluate(() => document.querySelector('[id^="pwa-utc-offset-"]').id)).toBe('pwa-utc-offset-1560');
    // two minutes on: 22:01
    await page.clock.runFor('02:00');
    expect(await night()).toBe(true);
    // nine hours on: 07:01 the next morning
    await page.clock.runFor('09:00:00');
    expect(await night()).toBe(false);
  });
});

test('sharing: the selection with its citation, and a text as a Markdown file, after the app has written it', async ({ page }) => {
  await page.addInitScript(() => {
    window.shared = [];
    navigator.share = d => { window.shared.push({ text: d.text, title: d.title, files: (d.files || []).map(f => f.name + ':' + f.type) }); return Promise.resolve(); };
    navigator.canShare = d => !!d.files;
  });
  await page.goto('/');
  await page.waitForFunction(() => document.body.textContent.includes('BATS PWA'), { timeout: 15000 });
  expect(await page.evaluate(() => document.documentElement.classList.contains('pwa-can-share'))).toBe(true);
  await page.evaluate(() => {
    document.body.insertAdjacentHTML('beforeend',
      '<p id="words">Some words worth keeping</p><span id="cite" hidden>A Book, Its Author</span>' +
      '<button data-pwa-share-selection="cite">Share selection</button>' +
      '<pre id="notes" hidden></pre><button data-pwa-share-file="notes" data-pwa-share-name="notes.md" id="export">Share notes</button>');
    // the app writes what is shared in its own listener, before the page's
    document.getElementById('export').addEventListener('click', () => { document.getElementById('notes').textContent = '# Notes\n'; });
    const r = document.createRange();
    r.selectNodeContents(document.getElementById('words'));
    getSelection().removeAllRanges(); getSelection().addRange(r);
  });
  await page.evaluate(() => document.querySelector('[data-pwa-share-selection]').click());
  await page.getByRole('button', { name: 'Share notes' }).click();
  await expect.poll(() => page.evaluate(() => window.shared)).toEqual([
    { text: '“Some words worth keeping”\n— A Book, Its Author', files: [] },
    { title: 'notes.md', files: ['notes.md:text/markdown'] },
  ]);
});

const loaded = async page => {
  await page.goto('/');
  await page.waitForFunction(() => document.body.textContent.includes('BATS PWA'), { timeout: 15000 });
};
const marked = (page, name) => page.evaluate(n => document.documentElement.classList.contains(n), name);

test('full screen, by the Fullscreen API: marked where it can be, and a click goes in and out', async ({ page }) => {
  await page.addInitScript(() => {
    let el = null;
    Object.defineProperty(Document.prototype, 'fullscreenElement', { get: () => el, configurable: true });
    Object.defineProperty(Document.prototype, 'fullscreenEnabled', { get: () => true, configurable: true });
    Element.prototype.requestFullscreen = function () { el = this; document.dispatchEvent(new Event('fullscreenchange')); return Promise.resolve(); };
    Document.prototype.exitFullscreen = function () { el = null; document.dispatchEvent(new Event('fullscreenchange')); return Promise.resolve(); };
  });
  await loaded(page);
  expect(await marked(page, 'pwa-can-fullscreen')).toBe(true);
  await page.evaluate(() => document.body.insertAdjacentHTML('beforeend', '<button data-pwa-fullscreen aria-pressed="false">Full screen</button>'));
  const b = page.getByRole('button', { name: 'Full screen' });
  await b.click();
  await expect(b).toHaveAttribute('aria-pressed', 'true');
  expect(await marked(page, 'pwa-fullscreen')).toBe(true);
  await b.click();
  await expect(b).toHaveAttribute('aria-pressed', 'false');
  expect(await marked(page, 'pwa-fullscreen')).toBe(false);
});

test('in the Android app: the status bar hidden, the rotation locked, the brightness set and kept', async ({ page }) => {
  await page.addInitScript(() => {
    window.calls = [];
    const call = name => a => { window.calls.push(name + (a ? ' ' + JSON.stringify(a) : '')); return Promise.resolve(); };
    window.Capacitor = { isNativePlatform: () => true, Plugins: {
      StatusBar: { hide: call('hide'), show: call('show') },
      ScreenOrientation: { lock: call('lock'), unlock: call('unlock') },
      ScreenBrightness: { setBrightness: call('brightness') },
    } };
  });
  await loaded(page);
  for (const n of ['pwa-can-fullscreen', 'pwa-can-lock', 'pwa-can-brightness']) expect(await marked(page, n)).toBe(true);
  await page.evaluate(() => document.body.insertAdjacentHTML('beforeend',
    '<button data-pwa-fullscreen>Full screen</button><button data-pwa-orientation-lock>Lock rotation</button>' +
    '<select data-pwa-brightness aria-label="Brightness"></select>'));
  await page.getByRole('button', { name: 'Full screen' }).click();
  await page.getByRole('button', { name: 'Lock rotation' }).click();
  await expect(page.getByRole('button', { name: 'Lock rotation' })).toHaveAttribute('aria-pressed', 'true');
  const brightness = page.getByRole('combobox', { name: 'Brightness' });
  await expect(brightness.locator('option')).toHaveText(['System', '10%', '25%', '50%', '75%', '100%']);
  await brightness.selectOption({ label: '50%' });
  await expect.poll(() => page.evaluate(() => window.calls)).toEqual(['hide', expect.stringMatching(/^lock \{"orientation":"(landscape|portrait)-primary"\}$/), 'brightness {"brightness":0.5}']);
  // kept: set again when the app starts, and the rotation locked again
  await page.evaluate(() => { window.calls = []; });
  await loaded(page);
  await expect.poll(() => page.evaluate(() => window.calls.map(c => c.split(' ')[0]).sort())).toEqual(['brightness', 'lock']);
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

test('a file shared with the installed app is kept by the service worker and dropped on the app', async ({ page }) => {
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
  await page.addInitScript(() => {
    window.dropped = [];
    new MutationObserver(() => {
      const el = document.getElementById('drop');
      if (el && !el.dataset.watched) { el.dataset.watched = 'y'; el.addEventListener('drop', e => window.dropped.push(...[...e.dataTransfer.files].map(f => f.name + ':' + f.size))); }
    }).observe(document, { childList: true, subtree: true });
    document.addEventListener('DOMContentLoaded', () => document.body.insertAdjacentHTML('beforeend', '<div data-pwa-file-drop id="drop"></div>'));
  });
  await page.goto('/?shared=1');
  await expect.poll(() => page.evaluate(() => window.dropped)).toEqual(['shared.txt:12']);
  expect(await page.evaluate(() => location.search)).toBe('');
});
