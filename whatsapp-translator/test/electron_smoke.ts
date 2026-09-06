// Real Electron, preload and renderer; synthetic gateway and translation only.
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

// Env must be set before the src imports below: tsc emits requires in source
// order, and gateway/history read WA_DATA_DIR at load time.
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'wa-electron-'));
process.env.WA_DATA_DIR = temporary;

import { app, BrowserWindow, ipcMain } from 'electron';
import * as gateway from '../src/gateway';
import * as translator from '../src/translator';

app.setPath('userData', path.join(temporary, 'electron'));

let callbacks: { onMsgCb: (msg: unknown) => void } | null = null;
let rejectSend = false;
let rejectTranslation = false;
let sequence = 0;
let releaseMedia: ((value: string | null) => void) | undefined;
let delayTranslation: Promise<string> | null = null;
const media = new Promise<string | null>((resolve) => { releaseMedia = resolve; });
const A = 'synthetic-a@g.us';
const B = 'synthetic-b@g.us';
for (let i = 0; i < 135; i++) gateway.remember({
  key: { id: 'a-' + String(i).padStart(3, '0'), remoteJid: A },
  messageTimestamp: 100 + Math.floor(i / 3),
  message: { conversation: 'Synthetic message ' + i },
});
gateway.remember({ key: { id: 'b-1', remoteJid: B }, messageTimestamp: 1,
  message: { conversation: 'Synthetic B' } });
interface GatewayStub {
  init: (value: unknown) => void;
  isReady: () => boolean;
  getGroups: () => Promise<Array<{ id: string; name: string }>>;
  toMessageDTO: (raw: unknown) => Promise<Record<string, unknown>>;
  mediaDataUrl: (raw: unknown) => Promise<string | null>;
  sendText: (chatId: string, text: string) => Promise<{ key: { id: string; remoteJid?: string; fromMe?: boolean }; messageTimestamp?: unknown; message?: { conversation?: string } }>;
  replyTo: (id: string, text: string) => Promise<unknown>;
}
const stub = gateway as unknown as GatewayStub;
const translatorStub = translator as unknown as { translateChain: typeof translator.translateChain };

stub.init = ((value: { onMsgCb: (msg: unknown) => void }) => { callbacks = value; }) as (value: unknown) => void;
stub.isReady = (() => true);
stub.getGroups = (async () => [{ id: A, name: 'Synthetic A' }, { id: B, name: 'Synthetic B' }]);
stub.toMessageDTO = (async (raw: unknown) => {
  const value = raw as { key: { id: string; remoteJid?: string; fromMe?: boolean }; messageTimestamp?: unknown; message?: { conversation?: string; imageMessage?: unknown } };
  return {
    id: value.key.id, chatId: value.key.remoteJid,
    fromMe: !!value.key.fromMe, name: 'Synthetic', timestamp: Number(value.messageTimestamp) * 1000,
    body: value.message?.conversation || 'Synthetic image', hasMedia: !!value.message?.imageMessage,
    mediaType: value.message?.imageMessage ? 'imageMessage' : '',
  };
});
stub.mediaDataUrl = (() => media);
stub.sendText = (async (chatId: string, text: string) => {
  if (rejectSend) throw new Error('Synthetic delivery failure');
  const raw = { key: { id: 'sent-' + (++sequence), remoteJid: chatId, fromMe: true },
    messageTimestamp: 200 + sequence, message: { conversation: text } };
  gateway.remember(raw);
  callbacks?.onMsgCb(raw); // Echo before IPC completes must not duplicate the row.
  return raw;
});
stub.replyTo = (async (id: string, text: string) => {
  const remoteJid = gateway.recentGet(id)?.key?.remoteJid;
  if (!remoteJid) throw new Error('unknown message id');
  return stub.sendText(remoteJid, text);
});
translatorStub.translateChain = (async () => {
  if (delayTranslation) return delayTranslation;
  if (rejectTranslation) throw new Error('Synthetic translation failure');
  return 'Syntetyczne tłumaczenie';
});
require('../main');

const deadline = setTimeout(() => { console.error('Electron smoke timed out'); app.exit(1); }, 30000);
app.whenReady().then(async () => {
  const win = BrowserWindow.getAllWindows()[0];
  if (win.webContents.isLoading()) await new Promise((resolve) => (win.webContents.once as any)('did-finish-load', resolve));
  const run = (code: string) => win.webContents.executeJavaScript(code);
  const wait = async (code: string) => {
    for (let i = 0; i < 100; i++) {
      if (await run(code)) return;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    throw new Error('Timed out: ' + code);
  };
  const select = (id: string) => run(`selectGroup({id:${JSON.stringify(id)},name:'Synthetic'})`);
  try {
    await wait("document.querySelectorAll('.group').length === 2");
    await select(A);
    assert.equal(await run('state.messages.size'), 60);
    await run("$('#messages').scrollTop = 100; window.anchor = $('#messages').firstElementChild.dataset.id; window.offset = $('#messages').firstElementChild.getBoundingClientRect().top; loadOlderMessages()");
    assert.equal(await run('state.messages.size'), 120);
    assert.ok(await run("Math.abs(document.querySelector('[data-id=\"'+window.anchor+'\"]').getBoundingClientRect().top-window.offset)<2"));
    await run('loadOlderMessages()');
    assert.equal(await run('state.messages.size'), 135);
    assert.equal(await run('state.history.hasMore'), false);

    // Delay first A history across A -> B -> A; only the newest visit wins.
    await run("window.originalPage = getMessagesPage; window.historyCalls = 0; getMessagesPage = (...args) => ++window.historyCalls === 1 ? new Promise(r => window.releaseHistory = r) : window.originalPage(...args); window.oldSelection = selectGroup({id:'synthetic-a@g.us',name:'old'}); void 0");
    await wait('!!window.releaseHistory');
    await select(B);
    await select(A);
    await run("window.releaseHistory({messages:[{id:'stale',chatId:'synthetic-a@g.us',body:'stale'}]}); window.oldSelection");
    assert.equal(await run("state.messages.has('stale')"), false);
    await run('getMessagesPage = window.originalPage; void 0');

    // Delayed translation and edit across visits cannot mutate the current view.
    await run("window.before = state.selectionVersion; window.m = state.messages.get('a-134')");
    await run("runTranslation(window.m, 'translate')");
    assert.equal(await run("state.messages.get('a-134').translation"), 'Syntetyczne tłumaczenie');
    let releaseTranslation: ((value: string) => void) | undefined;
    delayTranslation = new Promise<string>((resolve) => { releaseTranslation = resolve; });
    await run("window.lateTranslation = runTranslation(state.messages.get('a-134'),'retranslate'); void 0");
    await wait('state.translating.size === 1');
    await select(B);
    await select(A);
    releaseTranslation!('Old visit translation');
    await run('window.lateTranslation');
    assert.equal(await run("state.messages.get('a-134').translation"), 'Syntetyczne tłumaczenie');
    delayTranslation = null;
    // Delay edit IPC while switching twice. The persisted edit may be saved,
    // but its late response must not mutate the newly selected view.
    ipcMain.removeHandler('wa:editTranslation');
    let releaseEdit: (() => void) | undefined;
    let editStarted = false;
    ipcMain.handle('wa:editTranslation', async (_event, id, text) => {
      editStarted = true;
      await new Promise<void>((resolve) => { releaseEdit = resolve; });
      return { id, translation: text, edited: true };
    });
    await run("startEdit(document.querySelector('[data-id=\"a-134\"]'),state.messages.get('a-134')); document.querySelector('.edit-box').value='Old visit edit'; document.querySelector('.edit-box').parentNode.querySelector('button').click()");
    for (let i = 0; !editStarted && i < 100; i++) await new Promise((r) => setTimeout(r, 10));
    assert.ok(editStarted);
    await select(B);
    await select(A);
    const currentTranslation = await run("state.messages.get('a-134').translation");
    releaseEdit!();
    await new Promise((resolve) => setTimeout(resolve, 30));
    assert.equal(await run("state.messages.get('a-134').translation"), currentTranslation);
    ipcMain.removeHandler('wa:editTranslation');
    ipcMain.handle('wa:editTranslation', (_event, id, text) => {
      const cache = (require('../src/cache') as { default: typeof import('../src/cache').default }).default;
      const previous = cache.getTranslation(id);
      cache.setTranslation(id, previous!.original, text, { edited: true });
      return { id, translation: text, edited: true };
    });
    await run("startEdit(document.querySelector('[data-id=\"a-134\"]'), state.messages.get('a-134')); document.querySelector('.edit-box').value='Poprawione'; document.querySelector('.edit-box').parentNode.querySelector('button').click()");
    await wait("state.messages.get('a-134').translation === 'Poprawione'");

    // Failed correction retains its comment and the previous translation.
    rejectTranslation = true;
    await run("startRetranslate(document.querySelector('[data-id=\"a-134\"]'),state.messages.get('a-134')); document.querySelector('.retranslate-box textarea').value='Synthetic correction'; document.querySelector('.retranslate-box button').click()");
    await wait("!!state.messages.get('a-134').error && !state.translating.size");
    assert.equal(await run("document.querySelector('.retranslate-box textarea').value"), 'Synthetic correction');
    assert.equal(await run("state.messages.get('a-134').translation"), 'Poprawione');
    rejectTranslation = false;
    await run("document.querySelector('.retranslate-box button').click()");
    await wait("!document.querySelector('.retranslate-box')");

    // Failed sends and replies retain input, then retry once with a deduped echo.
    rejectSend = true;
    await run("$('#compose-input').value='Synthetic outgoing'; $('#compose').requestSubmit()");
    await wait('!state.sending.size');
    assert.equal(await run("$('#compose-input').value"), 'Synthetic outgoing');
    rejectSend = false;
    await run("$('#compose').requestSubmit(); $('#compose').requestSubmit()");
    await wait("state.messages.has('sent-1') && !state.sending.size");
    assert.equal(sequence, 1);
    assert.equal(await run("document.querySelectorAll('[data-id=\"sent-1\"]').length"), 1);
    assert.equal(gateway.recentGet('sent-1')!.message.conversation, 'Synthetic outgoing');
    rejectSend = true;
    await run("startReply(document.querySelector('[data-id=\"a-134\"]'),state.messages.get('a-134')); document.querySelector('.reply-box textarea').value='Synthetic reply'; document.querySelector('.reply-box button').click()");
    await wait("!document.querySelector('.reply-box button').disabled");
    await run('renderMessages()');
    assert.equal(await run("document.querySelector('.reply-box textarea').value"), 'Synthetic reply');
    rejectSend = false;
    await run("document.querySelector('.reply-box button').click()");
    await wait("state.messages.has('sent-2') && !document.querySelector('.reply-box')");
    await run("startReply(document.querySelector('[data-id=\"a-134\"]'),state.messages.get('a-134')); document.querySelector('.reply-box button:last-child').click()");
    assert.equal(await run("!!document.querySelector('.reply-box')"), false);

    // Live media arrives asynchronously and retains the manual translation.
    const image = { key: { id: 'image-1', remoteJid: A }, messageTimestamp: 300,
      message: { imageMessage: {} } };
    gateway.remember(image);
    callbacks?.onMsgCb(image);
    await wait("state.messages.has('image-1')");
    await run("runTranslation(state.messages.get('image-1'),'translate')");
    releaseMedia!('data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7');
    await wait("!!document.querySelector('[data-id=\"image-1\"] img.msg-media')");
    assert.equal(await run("state.messages.get('image-1').translation"), 'Syntetyczne tłumaczenie');
    await select(B);
    callbacks?.onMsgCb(image);
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.equal(await run("state.messages.has('image-1')"), false);
    console.log('Electron smoke OK: pagination, history/translation/edit A-B-A races, correction recovery, send/reply retry, echo dedupe, live media');
    clearTimeout(deadline);
    win.destroy();
    fs.rmSync(temporary, { recursive: true, force: true });
    app.exit(0);
  } catch (err) {
    console.error(err);
    clearTimeout(deadline);
    app.exit(1);
  }
});
