// The page watch (bats-lang/pwa#230): the preload gen-pwa test supplies, run
// against a stand-in playwright-core and @playwright/test, so each outcome is
// played without a browser: a page that does not answer (the pause, and the
// profile when it does not pause), a test near its timeout, and each part
// failing (no DevTools session, a directory that cannot be written, a launch
// that cannot be watched, no playwright-core at all).
// usage: PWA_WATCH=<the watch.cjs gen-pwa test wrote> node --test tests/test-command/watch.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const WATCH = process.env.PWA_WATCH;
if (!WATCH) throw new Error('PWA_WATCH names the preload gen-pwa test wrote');

const CORE = `
class BrowserType { async launch() { return globalThis.__browser; } name() { return 'chromium'; } }
if (process.env.FREEZE_PROTO) Object.freeze(BrowserType.prototype);
exports.chromium = new BrowserType();
`;
const PLAYWRIGHT_TEST = `
exports.test = { info() { if (process.env.NO_INFO) throw new Error('outside a test'); return { testId: 't1', titlePath: ['a.spec.js', 'the test'], project: { name: 'desktop' }, timeout: Number(process.env.TEST_TIMEOUT) }; } };
`;
// the driver launches, waits for an evidence file (or ends after WAIT_MS), and says what launch returned
const DRIVER = `
if (process.env.NO_CORE_NEEDED) { console.log('ran unchanged'); process.exit(0); }
const { EventEmitter } = require('events');
const fs = require('fs');
const mode = process.env.MODE;
const counts = { sessions: 0, enable: 0 };
const scene = { paused: false, resumes: 0 };
const session = Object.assign(new EventEmitter(), {
  send: async (method) => {
    if (method === 'Debugger.enable') counts.enable += 1;
    if (method === 'Debugger.pause' && mode === 'frames') setImmediate(() => session.emit('Debugger.paused', { reason: 'other', callFrames: [{ functionName: 'loop', url: 'http://x/a.js', location: { scriptId: '1', lineNumber: 3, columnNumber: 4 } }] }));
    // a page that runs no script while the pause is waited for (3 s) and the profile is taken (2 s), and
    // runs script 4 s after the pause was asked for: the pause fires then, in the profile's window
    if (method === 'Debugger.pause' && mode === 'late-script') setTimeout(() => { scene.paused = true; session.emit('Debugger.paused', { reason: 'other', callFrames: [] }); }, 4000);
    if (method === 'Debugger.resume') { scene.paused = false; scene.resumes += 1; }
    if (method === 'Profiler.stop') return { profile: { nodes: [{ callFrame: { functionName: 'busy', url: 'u', lineNumber: 0, columnNumber: 0 }, hitCount: 9 }, { callFrame: { functionName: 'idle', url: 'u', lineNumber: 1, columnNumber: 0 }, hitCount: 1 }] } };
    return {};
  },
});
const page = Object.assign(new EventEmitter(), {
  isClosed: () => false, url: () => 'http://x/',
  evaluate: () => (process.env.ANSWERS ? Promise.resolve(1) : new Promise(() => {})),
  probe: () => !scene.paused,
  context: () => ({ newCDPSession: async () => { counts.sessions += 1; if (mode === 'no-session') throw new Error('no session for you'); return session; } }),
});
const early = process.env.EARLY === '1';
const browser = Object.assign(new EventEmitter(), {
  browserType: () => (mode === 'bad-browser' ? null : { name: () => 'chromium' }),
  contexts: () => (early ? [] : [{ pages: () => [page] }]),
});
if (early) browser.newContext = async () => Object.assign(new EventEmitter(), { pages: () => [] });
if (mode === 'one-client') {
  // the routes by which the watch reaches a spinning page (ROUTES: both, page, scans); newContext is
  // defined before launch returns, which is when the preload wraps it (a later assignment would replace the wrapper)
  const routes = process.env.ROUTES;
  const scanned = Object.assign(new EventEmitter(), { pages: () => [page] });
  // the context newContext makes keeps no page in pages(), so only its page event can reach the page
  const made = Object.assign(new EventEmitter(), { pages: () => [] });
  browser.contexts = () => (routes === 'page' ? [] : [scanned]);
  if (routes !== 'scans') browser.newContext = async () => made;
}
globalThis.__browser = browser;
(async () => {
  const launched = await require('playwright-core').chromium.launch();
  console.log('launched ' + (launched === browser));
  if (mode === 'one-client') {
    if (process.env.ROUTES !== 'scans') {
      const made = await launched.newContext();
      made.emit('page', page);
      made.emit('page', page);
    }
    await new Promise((r) => setTimeout(r, 3000));
    console.log('counts ' + JSON.stringify(counts));
    process.exit(0);
  }
  if (early) {
    // a page is created and writes at once, before any scan could have seen it
    const context = await launched.newContext();
    context.emit('page', page);
    page.emit('console', { type: () => 'log', text: () => 'written at creation' });
    page.emit('request', { method: () => 'GET', url: () => 'http://x/slow' });
  }
  const dir = process.env.PWA_TEST_EVIDENCE_DIR;
  const end = Date.now() + Number(process.env.WAIT_MS);
  while (Date.now() < end) {
    let found = false;
    try { found = fs.readdirSync(dir).length > 0; } catch (e) { /* not made yet */ }
    if (found) break;
    await new Promise((r) => setTimeout(r, 200));
  }
  await new Promise((r) => setTimeout(r, 300));
  if (mode === 'late-script') console.log('answers ' + page.probe() + ' resumes ' + scene.resumes);
  process.exit(0);
})();
`;

function play(env, { withCore = true, withTest = true, requires = 1 } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'pwa-watch-'));
  mkdirSync(join(root, 'node_modules', 'playwright-core'), { recursive: true });
  mkdirSync(join(root, 'node_modules', '@playwright', 'test'), { recursive: true });
  if (withCore) writeFileSync(join(root, 'node_modules', 'playwright-core', 'index.js'), CORE);
  if (withTest) writeFileSync(join(root, 'node_modules', '@playwright', 'test', 'index.js'), PLAYWRIGHT_TEST);
  writeFileSync(join(root, 'driver.cjs'), DRIVER);
  const evidence = join(root, 'evidence');
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [...Array(requires).fill(['--require', WATCH]).flat(), 'driver.cjs'], {
      cwd: root, env: { ...process.env, PWA_TEST_EVIDENCE_DIR: evidence, WAIT_MS: '20000', ...env },
    });
    let out = ''; let err = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('close', (code) => {
      let files = [];
      try { files = readdirSync(evidence).sort(); } catch (e) { /* none */ }
      const read = (name) => JSON.parse(readFileSync(join(evidence, name), 'utf8'));
      resolve({ code, out, err, files, read, done: () => rmSync(root, { recursive: true, force: true }) });
    });
  });
}

test('a page that does not answer: the pause frames, the history and the load, one line printed', async () => {
  const r = await play({ MODE: 'frames' });
  assert.equal(r.code, 0);
  assert.match(r.out, /launched true/);
  assert.equal(r.files.length, 1);
  assert.match(r.files[0], /^desktop-a\.spec\.js-the-test-1\.json$/);
  const body = r.read(r.files[0]);
  assert.match(body.reason, /did not answer an evaluate within 5 s/);
  assert.equal(body.pause.frames[0].function, 'loop');
  assert.equal(body.pause.frames[0].url, 'http://x/a.js');
  assert.equal(body.pause.frames[0].line, 4);
  assert.equal(body.url, 'http://x/');
  assert.ok(Array.isArray(body.history.console) && Array.isArray(body.history.inFlight));
  assert.ok(Array.isArray(body.runnerLoad.now.loadavg));
  assert.match(r.err, /gen-pwa test: hang evidence: .*desktop-a\.spec\.js-the-test-1\.json \(page did not answer/);
  r.done();
});

test('a page that writes at once is recorded from its creation', async () => {
  const r = await play({ MODE: 'frames', EARLY: '1' });
  const body = r.read(r.files[0]);
  assert.equal(body.history.console[0].text, 'written at creation');
  assert.equal(body.history.inFlight[0].url, 'http://x/slow');
  assert.ok(body.history.inFlight[0].ageMs >= 0);
  r.done();
});

test('a page that does not pause: a profile, most samples first', async () => {
  const r = await play({ MODE: 'profile' });
  const body = r.read(r.files[0]);
  assert.match(body.pause, /^not available: no pause within 3000 ms/);
  assert.equal(body.profile.top[0].where, 'busy u:1:1');
  assert.equal(body.profile.top[0].samples, 9);
  r.done();
});

test('a test near its timeout is captured though its page answers', async () => {
  const r = await play({ MODE: 'frames', ANSWERS: '1', TEST_TIMEOUT: '6000' });
  assert.equal(r.files.length, 1);
  assert.match(r.read(r.files[0]).reason, /test is within \d+ s of its timeout/);
  r.done();
});

test('injected: no DevTools session is said, and the capture is still written', async () => {
  const r = await play({ MODE: 'no-session' });
  const body = r.read(r.files[0]);
  assert.match(body.pause, /^not available: no session for you/);
  assert.ok(body.history && body.runnerLoad);
  r.done();
});

test('injected: a directory that cannot be written is said, and launch still returns the browser', async () => {
  const r = await play({ MODE: 'frames', PWA_TEST_EVIDENCE_DIR: '/dev/null/evidence', WAIT_MS: '9000' });
  assert.match(r.out, /launched true/);
  assert.match(r.err, /hang evidence not available: cannot write \/dev\/null\/evidence\//);
  r.done();
});

test('injected: a browser that cannot be watched is said, and launch still returns it', async () => {
  const r = await play({ MODE: 'bad-browser', WAIT_MS: '1000' });
  assert.match(r.out, /launched true/);
  assert.match(r.err, /hang evidence not available: /);
  assert.equal(r.files.length, 0);
  r.done();
});

test('no playwright-core: the preload says why it cannot arm, and the process runs as it would', async () => {
  const r = await play({ MODE: 'frames', WAIT_MS: '500', NO_CORE_NEEDED: '1' }, { withCore: false });
  assert.equal(r.code, 0);
  assert.match(r.out, /^ran unchanged/);
  assert.match(r.err, /gen-pwa test: hang evidence not available: Cannot find module 'playwright-core'/);
  r.done();
});

test('injected: a launch that cannot be wrapped is said, and launch still returns the browser', async () => {
  const r = await play({ MODE: 'frames', FREEZE_PROTO: '1', WAIT_MS: '500' });
  assert.equal(r.code, 0);
  assert.match(r.out, /launched true/);
  assert.match(r.err, /gen-pwa test: hang evidence not available: Cannot define property __pwaEvidence/);
  assert.equal(r.files.length, 0);
  r.done();
});

test('no evidence directory in the environment: launch is not wrapped', async () => {
  const r = await play({ MODE: 'frames', PWA_TEST_EVIDENCE_DIR: '', WAIT_MS: '7000' });
  assert.match(r.out, /launched true/);
  assert.equal(r.files.length, 0);
  assert.doesNotMatch(r.err, /gen-pwa test/);
  r.done();
});

// pwa#289: the preload is the one DevTools client of a page, so a second watch (quire's own
// stall-capture.js) stands down; the lines printed are what check.yml's job shows. The two controls
// each reach the page by one route only, so a route that does not reach track fails its own test.
async function oneClient(routes, how) {
  const r = await play({ MODE: 'one-client', ROUTES: routes, WAIT_MS: '4000' }, { requires: 2 });
  assert.equal(r.code, 0);
  const counts = JSON.parse(/^counts (.*)$/m.exec(r.out)[1]);
  assert.deepEqual(counts, { sessions: 1, enable: 1 });
  console.log(`one DevTools client: Debugger.enable sent ${counts.enable} time for 1 spinning page${how} (${counts.sessions} session)`);
  r.done();
}

test('exactly one DevTools client arms a spinning page, however the page is reached', async () => {
  await oneClient('both', '');
});

test('the context page event alone arms a spinning page once', async () => {
  await oneClient('page', ' reached by the page event alone');
});

test('the scans alone arm a spinning page once', async () => {
  await oneClient('scans', ' reached by the scans alone');
});

// pwa#329: a pause the preload asked for and did not get while the page ran no script is not left
// pending: the page's script starts after the wait ended (in the profile's window), the pause fires
// then, and the page must answer a probe afterwards; the line is what check.yml's job shows
test('a page that runs script only after the pause wait is not left paused', async () => {
  const r = await play({ MODE: 'late-script', WAIT_MS: '30000' });
  assert.equal(r.code, 0);
  const body = r.read(r.files[0]);
  assert.match(body.pause, /^not available: no pause within 3000 ms/);
  const answered = /^answers (true|false) resumes (\d+)$/m.exec(r.out);
  assert.ok(answered, r.out);
  console.log(`page answers a probe after its script started: ${answered[1] === 'true' ? 'yes' : 'no'} (${answered[2]} resume)`);
  assert.equal(answered[1], 'true');
  r.done();
});
