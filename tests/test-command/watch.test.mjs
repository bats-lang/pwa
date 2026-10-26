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
exports.chromium = new BrowserType();
`;
const PLAYWRIGHT_TEST = `
exports.test = { info() { if (process.env.NO_INFO) throw new Error('outside a test'); return { testId: 't1', titlePath: ['a.spec.js', 'the test'], project: { name: 'desktop' }, timeout: Number(process.env.TEST_TIMEOUT) }; } };
`;
// the driver launches, waits for an evidence file (or ends after WAIT_MS), and says what launch returned
const DRIVER = `
const { EventEmitter } = require('events');
const fs = require('fs');
const mode = process.env.MODE;
const session = Object.assign(new EventEmitter(), {
  send: async (method) => {
    if (method === 'Debugger.pause' && mode === 'frames') setImmediate(() => session.emit('Debugger.paused', { reason: 'other', callFrames: [{ functionName: 'loop', url: 'http://x/a.js', location: { scriptId: '1', lineNumber: 3, columnNumber: 4 } }] }));
    if (method === 'Profiler.stop') return { profile: { nodes: [{ callFrame: { functionName: 'busy', url: 'u', lineNumber: 0, columnNumber: 0 }, hitCount: 9 }, { callFrame: { functionName: 'idle', url: 'u', lineNumber: 1, columnNumber: 0 }, hitCount: 1 }] } };
    return {};
  },
});
const page = Object.assign(new EventEmitter(), {
  isClosed: () => false, url: () => 'http://x/',
  evaluate: () => (process.env.ANSWERS ? Promise.resolve(1) : new Promise(() => {})),
  context: () => ({ newCDPSession: async () => { if (mode === 'no-session') throw new Error('no session for you'); return session; } }),
});
const browser = Object.assign(new EventEmitter(), {
  browserType: () => (mode === 'bad-browser' ? null : { name: () => 'chromium' }),
  contexts: () => [{ pages: () => [page] }],
});
globalThis.__browser = browser;
(async () => {
  const launched = await require('playwright-core').chromium.launch();
  console.log('launched ' + (launched === browser));
  const dir = process.env.PWA_TEST_EVIDENCE_DIR;
  const end = Date.now() + Number(process.env.WAIT_MS);
  while (Date.now() < end) {
    let found = false;
    try { found = fs.readdirSync(dir).length > 0; } catch (e) { /* not made yet */ }
    if (found) break;
    await new Promise((r) => setTimeout(r, 200));
  }
  await new Promise((r) => setTimeout(r, 300));
  process.exit(0);
})();
`;

function play(env, { withCore = true, withTest = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'pwa-watch-'));
  mkdirSync(join(root, 'node_modules', 'playwright-core'), { recursive: true });
  mkdirSync(join(root, 'node_modules', '@playwright', 'test'), { recursive: true });
  if (withCore) writeFileSync(join(root, 'node_modules', 'playwright-core', 'index.js'), CORE);
  if (withTest) writeFileSync(join(root, 'node_modules', '@playwright', 'test', 'index.js'), PLAYWRIGHT_TEST);
  writeFileSync(join(root, 'driver.cjs'), DRIVER);
  const evidence = join(root, 'evidence');
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['--require', WATCH, 'driver.cjs'], {
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

test('no playwright-core: the preload says nothing and changes nothing', async () => {
  const r = await play({ MODE: 'frames', WAIT_MS: '500', NO_INFO: '1' }, { withCore: false });
  assert.notEqual(r.code, 0); // the driver itself needs playwright-core; the preload must not have failed first
  assert.doesNotMatch(r.err, /gen-pwa test/);
  assert.match(r.err, /Cannot find module 'playwright-core'/);
  r.done();
});

test('no evidence directory in the environment: launch is not wrapped', async () => {
  const r = await play({ MODE: 'frames', PWA_TEST_EVIDENCE_DIR: '', WAIT_MS: '7000' });
  assert.match(r.out, /launched true/);
  assert.equal(r.files.length, 0);
  assert.doesNotMatch(r.err, /gen-pwa test/);
  r.done();
});
