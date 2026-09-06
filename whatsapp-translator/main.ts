// Electron main: window, IPC handlers, contextual translation orchestration.

import { app, BrowserWindow, ipcMain } from 'electron';
import * as path from 'node:path';
import * as gateway from './src/gateway';
import cache from './src/cache';
import { translateChain } from './src/translator';
import * as vocabulary from './src/vocabulary';
import * as translationLog from './src/translation-log';
import * as exporter from './src/export';
import type { MessageDTO, GroupInfo } from './src/types';

let win: BrowserWindow | null = null;

function createWindow(): void {
  win = new BrowserWindow({
    width: 1240,
    height: 820,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));
}

function send(channel: string, payload?: unknown): void {
  if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
}

// ponytail: per-chat rolling context — contextual translation + privacy name list
interface ContextItem {
  id: string;
  body: string;
  name?: string;
  timestamp?: number;
  order: number;
}

const contextByChat = new Map<string, ContextItem[]>(); // chatId -> [{ id, body, name, timestamp, order }]
const TRANSLATION_CONTEXT_MESSAGES = 8;
let contextOrder = 0;

export function contextFor(dto: MessageDTO): { bodies: string[]; names: string[] } {
  const ctx = contextByChat.get(dto.chatId) || [];
  const target = ctx.find((item) => item.id === dto.id);
  const recent = ctx
    .filter((item) => {
      if (item.id === dto.id) return false;
      if (!target) return item.order < contextOrder;
      if (!item.timestamp || !target.timestamp) return item.order < target.order;
      return item.timestamp < target.timestamp ||
        (item.timestamp === target.timestamp && item.order < target.order);
    })
    .sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0) || a.order - b.order)
    .slice(-TRANSLATION_CONTEXT_MESSAGES);
  const bodies = recent.map((item) => item.body);
  if (dto.quoted) bodies.push('Related quoted message:\n- ' + dto.quoted);
  return {
    bodies,
    names: [...new Set([dto.name, ...recent.map((item) => item.name)].filter(Boolean))] as string[],
  };
}

function pushContext(dto: MessageDTO): void {
  if (!dto.chatId || !dto.body) return;
  let ctx = contextByChat.get(dto.chatId);
  if (!ctx) {
    ctx = [];
    contextByChat.set(dto.chatId, ctx);
  }
  const existing = ctx.find((item) => item.id === dto.id);
  if (existing) {
    Object.assign(existing, { body: dto.body, name: dto.name, timestamp: dto.timestamp });
  } else {
    ctx.push({ id: dto.id, body: dto.body, name: dto.name, timestamp: dto.timestamp, order: ++contextOrder });
  }
  while (ctx.length > 200) ctx.shift();
}

export interface TranslateCall {
  comment?: string;
  force?: boolean;
  mode?: string;
  requestId?: string;
  isLatest?: () => boolean;
  signal?: AbortSignal;
}

// Translate (or reuse cache) for one message DTO.
// force=true = retranslate; per design, retranslation overwrites an edited translation.
export async function translateAndCache(dto: MessageDTO, options: TranslateCall = {}): Promise<MessageDTO> {
  const { comment = '', force = false, mode = 'translate', requestId, isLatest = () => true, signal } = options;
  const eventFields = { requestId, messageId: dto.id, chatId: dto.chatId || null, mode };
  if (dto.fromMe) {
    translationLog.write('translation_skipped', { ...eventFields, reason: 'outgoing_message' });
    pushContext(dto);
    return { ...dto, translation: null, edited: false };
  }
  const existing = cache.getTranslation(dto.id);
  if (existing && !force) {
    translationLog.write('translation_cache_hit', {
      ...eventFields,
      output: translationLog.textMeta(existing.translation),
      edited: Boolean(existing.edited),
    });
    pushContext(dto);
    return { ...dto, translation: existing.translation, edited: existing.edited };
  }
  if (!dto.body) {
    translationLog.write('translation_skipped', { ...eventFields, reason: 'empty_message' });
    return { ...dto, translation: null };
  }
  const ctx = contextFor(dto);
  try {
    const translation = await translateChain(dto.body, {
      knownWords: cache.knownWords(),
      context: ctx.bodies,
      names: ctx.names, // privacy: masked to placeholders, restored after
      comment,
      previousTranslation: force ? existing?.translation : '',
      requestId,
      messageId: dto.id,
      mode,
      signal,
      learningMode: process.env.WA_LEARNING_MODE === '1',
    });
    if (!isLatest()) return cached(dto);
    cache.setTranslation(dto.id, dto.body, translation, { comment });
    translationLog.write('translation_cache_written', {
      ...eventFields,
      output: translationLog.textMeta(translation),
      replaced: Boolean(existing),
    });
    pushContext(dto);
    return { ...dto, translation, edited: false };
  } catch (err) {
    translationLog.error(requestId as string, err, { ...eventFields, phase: 'translation_chain' });
    pushContext(dto);
    return { ...cached(dto), error: String((err as Error | undefined)?.message || err) };
  }
}

interface PendingJob {
  job: Promise<MessageDTO>;
  uiToken: string | null;
  controller: AbortController;
}

const pending = new Map<string, PendingJob>();
const revisions = new Map<string, symbol>();

function cached(dto: MessageDTO): MessageDTO {
  if (dto.fromMe) return { ...dto, translation: null, edited: false };
  const existing = cache.getTranslation(dto.id);
  return existing
    ? { ...dto, translation: existing.translation, edited: existing.edited }
    : { ...dto, translation: null, edited: false };
}

async function handleNewMessage(raw: unknown): Promise<MessageDTO> {
  const dto = await gateway.toMessageDTO(raw as never);
  pushContext(dto);
  send('wa:message', cached(dto));
  loadMedia(dto, raw);
  return cached(dto);
}

function loadMedia(dto: MessageDTO, raw: unknown): void {
  if (!dto.hasMedia) return;
  // Send only media fields: a delayed download cannot roll back an edit.
  gateway.mediaDataUrl(raw as never).then((mediaUrl) => {
    if (mediaUrl) send('wa:message', { id: dto.id, chatId: dto.chatId,
      hasMedia: true, mediaType: dto.mediaType, mediaUrl });
  }).catch((err) => console.error('media load failed:', err));
}

export async function translateMessage(messageId: string, options: {
  comment?: string; force?: boolean; uiToken?: string | null;
} = {}): Promise<MessageDTO> {
  const { comment = '', force = false, uiToken = null } = options;
  const mode = force ? 'retranslate' : 'translate';
  const requestId = translationLog.request({
    messageId,
    mode,
    comment: translationLog.textMeta(comment),
  });
  const previous = pending.get(messageId);
  if (previous && previous.uiToken === uiToken) {
    translationLog.write('translation_coalesced', { requestId, messageId, mode });
    const result = await previous.job;
    return uiToken ? { ...result, uiToken } : result;
  }
  previous?.controller.abort();
  const controller = new AbortController();
  const revision = Symbol(messageId);
  revisions.set(messageId, revision);
  const isLatest = () => revisions.get(messageId) === revision;
  const job = (async (): Promise<MessageDTO> => {
    try {
      const raw = gateway.recentGet(messageId);
      if (!raw) throw new Error('message not in history');
      const dto = await gateway.toMessageDTO(raw);
      translationLog.write('translation_message', {
        requestId,
        messageId,
        mode,
        chatId: dto.chatId || null,
        fromMe: Boolean(dto.fromMe),
        input: translationLog.textMeta(dto.body),
      });
      pushContext(dto);
      const withT = await translateAndCache(dto, { comment, force, mode, requestId, isLatest, signal: controller.signal });
      translationLog.write('translation_finished', {
        requestId,
        messageId,
        mode,
        status: withT.error ? 'error' : (withT.translation ? 'success' : 'skipped'),
        error: withT.error || undefined,
      });
      const result = uiToken ? { ...withT, uiToken } : withT;
      if (isLatest()) send('wa:translation', result);
      return result;
    } catch (err) {
      translationLog.error(requestId, err, { messageId, mode, phase: 'request' });
      throw err;
    }
  })();
  pending.set(messageId, { job, uiToken, controller });
  try {
    return await job;
  } finally {
    if (pending.get(messageId)?.job === job) pending.delete(messageId);
    if (isLatest()) revisions.delete(messageId);
  }
}

ipcMain.handle('wa:getState', () => ({ ready: gateway.isReady() }));
ipcMain.handle('wa:getGroups', () => gateway.getGroups());
export async function loadMessagePage(groupId: string, limit: number, before: unknown): Promise<{
  messages: MessageDTO[]; hasMore: boolean; cursor: unknown;
}> {
  const visibleLimit = Math.max(1, Number(limit) || 50);
  // Show persisted messages immediately; a later history event refreshes the view.
  // Do not block the chat on the initial full-history sync.
  const page = await gateway.getMessagesPage(
    groupId,
    visibleLimit + TRANSLATION_CONTEXT_MESSAGES,
    before as never
  );
  const raws = page.messages;
  const out: MessageDTO[] = [];
  for (const raw of raws) {
    const dto = await gateway.toMessageDTO(raw);
    pushContext(dto);
    out.push(cached(dto));
    loadMedia(dto, raw);
  }
  const visible = out.slice(-visibleLimit);
  const visibleRaw = raws.slice(-visibleLimit)[0] || null;
  return {
    messages: visible,
    // The extra context records are intentionally hidden from the UI. They
    // still count as older records that can be paged into view.
    hasMore: Boolean(page.hasMore || raws.length > visible.length),
    cursor: visibleRaw ? gateway.cursorOf(visibleRaw) : page.cursor,
  };
}
ipcMain.handle('wa:getMessagesPage', (_e, groupId: string, limit: number, before: unknown) =>
  loadMessagePage(groupId, limit, before)
);
ipcMain.handle('wa:getMessages', async (_e, groupId: string, limit: number) =>
  (await loadMessagePage(groupId, limit, null)).messages
);
ipcMain.handle('wa:translate', (_e, messageId: string, uiToken: string) => translateMessage(messageId, { uiToken }));
ipcMain.handle('wa:cancelTranslation', (_e, messageId: string, uiToken: string) => {
  const job = pending.get(messageId);
  if (job?.uiToken === uiToken) {
    revisions.set(messageId, Symbol('cancelled'));
    job.controller.abort();
  }
});

interface VocabularyInputShape {
  body: string;
  translation: string;
  revision: number;
  context: string[];
  names: string[];
  learningMode: boolean;
}

const pendingVocabulary = new Map<string, Promise<unknown>>();
async function vocabularyInput(messageId: string, chatId: string): Promise<VocabularyInputShape> {
  const raw = gateway.recentGet(messageId);
  if (!raw || (raw as { key?: { remoteJid?: string } }).key?.remoteJid !== chatId) {
    throw new Error('Message is not in this chat');
  }
  const dto = await gateway.toMessageDTO(raw);
  const current = cache.getTranslation(messageId);
  const context = contextFor(dto);
  return { body: dto.body, translation: current?.translation || '', revision: current?.revision || 0,
    context: context.bodies, names: context.names, learningMode: process.env.WA_LEARNING_MODE === '1' };
}
ipcMain.handle('wa:vocabulary', async (_e, messageId: string, chatId: string) => {
  const input = await vocabularyInput(messageId, chatId);
  const key = vocabulary.cacheKey(input);
  const existing = cache.getVocabulary(key);
  if (existing) return { key, ...existing };
  if (pendingVocabulary.has(key)) return pendingVocabulary.get(key);
  const job = (async () => {
    const result = await vocabulary.generateVocabulary(input);
    if (vocabulary.cacheKey(await vocabularyInput(messageId, chatId)) !== key) {
      throw new Error('Message changed; request its meanings again');
    }
    cache.setVocabulary(key, result);
    return { key, ...result };
  })();
  pendingVocabulary.set(key, job);
  try { return await job; } finally { pendingVocabulary.delete(key); }
});
ipcMain.handle('wa:send', async (_e, groupId: string, text: string) => {
  const raw = await gateway.sendText(groupId, text);
  if (!raw?.key?.id) throw new Error('Message was not accepted; please retry.');
  return handleNewMessage(raw);
});
ipcMain.handle('wa:reply', async (_e, messageId: string, text: string) => {
  const raw = await gateway.replyTo(messageId, text);
  if (!raw?.key?.id) throw new Error('Reply was not accepted; please retry.');
  return handleNewMessage(raw);
});
ipcMain.handle('wa:retranslate', (_e, messageId: string, comment: string, uiToken: string) =>
  translateMessage(messageId, { comment: comment || '', force: true, uiToken })
);
ipcMain.handle('wa:editTranslation', (_e, messageId: string, text: string) => {
  const existing = cache.getTranslation(messageId);
  if (!existing) throw new Error('no cached translation');
  revisions.set(messageId, Symbol('edit'));
  pending.get(messageId)?.controller.abort();
  cache.setTranslation(messageId, existing.original, text, { edited: true });
  translationLog.write('translation_edited', {
    messageId,
    input: translationLog.textMeta(existing.original),
    output: translationLog.textMeta(text),
  });
  return { id: messageId, translation: text, edited: true };
});
ipcMain.handle('wa:knownWords', () => cache.knownWords());
ipcMain.handle('wa:addKnownWord', (_e, word: string) => {
  cache.addKnownWord(word);
  return cache.knownWords();
});
ipcMain.handle('wa:removeKnownWord', (_e, word: string) => {
  cache.removeKnownWord(word);
  return cache.knownWords();
});
ipcMain.handle('wa:export', () => exporter.run(cache));

gateway.init({
  onQrCb: (qrDataUrl: string) => send('wa:qr', qrDataUrl),
  onReadyCb: () => {
    send('wa:ready');
    gateway.getGroups().then((groups: GroupInfo[]) => send('wa:groups', groups)).catch(() => {});
  },
  onMsgCb: (raw) => handleNewMessage(raw).catch(console.error),
  onHistoryCb: (info) => send('wa:history', info),
});

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});