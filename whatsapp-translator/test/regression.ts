import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import * as vm from 'node:vm';
import { createRequire } from 'node:module';

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'wa-regression-'));
process.env.WA_DATA_DIR = temporary;
process.env.KILO_AUTOSTART = '0';

import { maskNames, restoreNames } from '../src/translator';
import cache from '../src/cache';
import * as history from '../src/history';

// The regression harness runs the compiled CJS output (dist/) in an isolated
// vm with a stub socket. Compiled CJS writes exports.foo, so the sandbox needs
// an `exports` alias pointing at the same object as module.exports.
function evaluate(file: string, overrides: Record<string, unknown>, extra = '') {
  const filename = path.resolve(__dirname, '..', file);
  const localRequire = createRequire(filename) as (id: string) => unknown;
  const mod = { exports: {} as unknown };
  const sandbox = {
    require: (id: string) => (id in overrides ? overrides[id] : localRequire(id)),
    module: mod,
    exports: mod.exports,
    __dirname: path.dirname(filename),
    process, console, Buffer, setTimeout, clearTimeout, AbortController,
  };
  vm.runInNewContext(fs.readFileSync(filename, 'utf8') + '\n' + extra, sandbox as Record<string, unknown>, { filename });
  return mod.exports as Record<string, any>;
}
const deferred = () => {
  let resolve!: (value?: unknown) => void;
  const promise = new Promise<unknown>((r) => { resolve = r; });
  return { promise, resolve };
};

(async () => {
  const values = ['李', 'Łukasz', 'Élodie', '@Łukasz.suffix', '@用户', '@Иван'];
  const fields = [values.join(' '), 'E\u0301lodie ŁUKASZ @用户', '{{P1}}'];
  const masked = maskNames(fields, values.slice(0, 3));
  for (const value of values) assert.ok(!masked.texts.join(' ').includes(value));
  assert.equal(masked.texts[2], '{{P1}}', 'literal placeholder must not alias an identity');
  assert.equal(restoreNames(masked.texts[0], masked.map), fields[0]);
  assert.equal(restoreNames(masked.texts[1], masked.map), 'Élodie Łukasz @用户');
  // Exercise the real send/reply code with only the socket replaced.
  let failSend = false;
  let sent = 0;
  const gateway = evaluate('src/gateway.js', {}, `
    sock = { sendMessage: async (chatId, content) => {
      if (testSocket.fail()) throw new Error('synthetic delivery failure');
      return testSocket.sent(chatId, content);
    }};
    module.exports.setTestSocket = value => { testSocket = value; };
    let testSocket;
  `);
  gateway.setTestSocket({ fail: () => failSend, sent: (chatId: string, content: { text: string }) => ({
    key: { id: 'out-' + (++sent), remoteJid: chatId }, message: { conversation: content.text }, messageTimestamp: 2,
  }) });
  const out = await gateway.sendText('a@g.us', 'synthetic outgoing');
  assert.equal(history.get(out.key!.id)!.key!.fromMe, true);
  const sizeBeforeEcho = fs.statSync(path.join(temporary, 'history.jsonl')).size;
  gateway.remember(out);
  assert.equal(fs.statSync(path.join(temporary, 'history.jsonl')).size, sizeBeforeEcho);
  const reply = await gateway.replyTo(out.key.id, 'synthetic reply');
  assert.equal(history.get(reply.key.id)!.message.conversation, 'synthetic reply');
  failSend = true;
  await assert.rejects(gateway.sendText('a@g.us', 'failed'), /delivery failure/);
  assert.equal(sent, 2);

  // Real main-process handlers: newer translation/edit owns the cache.
  const handlers = new Map<string, (...args: unknown[]) => unknown>();
  const jobs: Array<{ promise: Promise<unknown>; resolve: (value?: unknown) => void; opts?: unknown }> = [];
  const media = deferred();
  const raw = { key: { id: 'target', remoteJid: 'a@g.us' }, message: { conversation: 'target' }, messageTimestamp: 3 };
  gateway.remember(raw);
  gateway.init = (() => {}) as typeof gateway.init;
  gateway.toMessageDTO = (async (value: { key: { id: string; remoteJid?: string; fromMe?: boolean }; message: { conversation?: string }; messageTimestamp?: unknown }) => ({
    id: value.key.id, chatId: value.key.remoteJid, body: value.message.conversation,
    fromMe: !!value.key.fromMe, timestamp: Number(value.messageTimestamp) * 1000, name: 'Synthetic',
    hasMedia: true, mediaType: 'imageMessage',
  })) as typeof gateway.toMessageDTO;
  gateway.mediaDataUrl = (() => media.promise) as typeof gateway.mediaDataUrl;
  const main = evaluate('main.js', {
    electron: { app: { whenReady: () => ({ then() {} }), on() {} },
      ipcMain: { handle: (name: string, handler: (...args: unknown[]) => unknown) => handlers.set(name, handler) } },
    './src/gateway': gateway,
    './src/translator': { translateChain: (_text: string, opts: unknown) => { const job = deferred(); jobs.push({ ...job, opts }); return job.promise; } },
  }, 'module.exports = { translateMessage, loadMessagePage, contextFor };');
  const older = main.translateMessage('target', { uiToken: 'old' });
  await new Promise(setImmediate);
  const newer = main.translateMessage('target', { uiToken: 'new', force: true, comment: 'new correction' });
  await new Promise(setImmediate);
  assert.equal(jobs.length, 2);
  jobs[1].resolve('new translation');
  await newer;
  jobs[0].resolve('stale translation');
  await older;
  assert.equal(cache.getTranslation('target')!.translation, 'new translation');
  const pendingEdit = main.translateMessage('target', { uiToken: 'edit-race', force: true });
  await new Promise(setImmediate);
  handlers.get('wa:editTranslation')!(null, 'target', 'manual edit');
  jobs[2].resolve('late translation');
  await pendingEdit;
  assert.equal(cache.getTranslation('target')!.translation, 'manual edit');
  // Media is unresolved: history and translations must still finish.
  const page = await main.loadMessagePage('a@g.us', 60, null);
  assert.ok(page.messages.some((message: { id: string }) => message.id === 'target'));
  assert.ok(main.contextFor({ id: 'target', chatId: 'a@g.us' }).bodies.includes('synthetic outgoing'));
  media.resolve(null);
  console.log('regression OK: privacy, persistence/echo, cache races, outgoing context, nonblocking media');
})().then(() => fs.rmSync(temporary, { recursive: true, force: true })).catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
