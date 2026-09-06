// WA Gateway — Baileys on the personal account (design: wa-gateway module).
// Socket-based: QR pairing, group list, message receive (text/media/quotes/
// timestamps/sender names + photos), send as typed, replies. Session under
// data/session. Baileys is ESM-only, so it is loaded lazily via import().

import * as path from 'node:path';
import * as qrcode from 'qrcode';
import * as history from './history';
import type { MessageDTO, GroupInfo } from './types';

// Baileys protobuf message shapes; only the documented fields below are read.
interface RawMessage {
  key?: { id?: string; remoteJid?: string; fromMe?: boolean; participant?: string };
  message?: any;
  messageTimestamp?: unknown;
  pushName?: string;
}

const SESSION_DIR = path.join(__dirname, '..', '..', 'data', 'session');
const GROUP_SUFFIX = '@g.us';
const HISTORY_WAIT_MS = 45_000;

let B: any = null;
let sock: any = null;
let ready = false;
let starting = false;
let onQr: ((url: string) => void) | null = null;
let onReady: (() => void) | null = null;
let onMessage: ((msg: RawMessage) => void) | null = null;
let onHistory: ((info: Record<string, unknown>) => void) | null = null;
let historyTimer: ReturnType<typeof setTimeout> | null = null;
let historyPending = false;
let resolveHistory = () => {};
let historyReady: Promise<void> = Promise.resolve();

// ponytail: in-memory message map for replies; persistent history lives in history.jsonl
const recent = new Map<string, RawMessage>();
const profileCache = new Map<string, { name: string; photo: string | null; photoLoaded: boolean }>();

function isGroupMessage(msg: RawMessage): boolean {
  return Boolean(msg?.key?.remoteJid?.endsWith(GROUP_SUFFIX));
}

export function cursorOf(msg: RawMessage): { timestamp: number; id: string } | null {
  if (!msg?.key?.id) return null;
  return { timestamp: history.timestampOf(msg), id: msg.key.id };
}

export interface Cursor {
  timestamp: number;
  id: string;
}

export interface RawPageResult {
  messages: RawMessage[];
  hasMore: boolean;
  cursor: Cursor | null;
}

function compareToCursor(msg: RawMessage, cursor: Cursor | null): number {
  const messageTimestamp = history.timestampOf(msg);
  const cursorTimestamp = Number(cursor?.timestamp) || 0;
  if (messageTimestamp !== cursorTimestamp) return messageTimestamp - cursorTimestamp;
  return String(msg.key?.id || '').localeCompare(String(cursor?.id || ''));
}

function messageFingerprint(msg: RawMessage): string | null {
  try {
    return JSON.stringify({
      remoteJid: msg.key?.remoteJid,
      fromMe: msg.key?.fromMe,
      timestamp: history.timestampOf(msg),
      message: msg.message || null,
    });
  } catch {
    return null;
  }
}

export function remember(msg: RawMessage, persist = true): void {
  if (!msg?.key?.id) return;
  const previous = recent.get(msg.key.id);
  const unchanged = previous && messageFingerprint(previous) === messageFingerprint(msg);
  recent.set(msg.key.id, msg);
  if (recent.size > 2000) recent.delete(recent.keys().next().value as string);
  if (persist && !unchanged) {
    try {
      history.upsert(msg);
    } catch (err) {
      console.error('history write failed:', err);
    }
  }
}

function rememberMany(messages: RawMessage[]): void {
  const valid = messages.filter((msg) => msg?.key?.id);
  for (const msg of valid) remember(msg, false);
  try {
    history.upsertMany(valid);
  } catch (err) {
    console.error('history write failed:', err);
  }
}

function beginHistorySync(): void {
  if (historyPending) return;
  historyPending = true;
  historyReady = new Promise((resolve) => {
    resolveHistory = () => {
      if (!historyPending) return;
      historyPending = false;
      if (historyTimer) clearTimeout(historyTimer);
      historyTimer = null;
      resolve();
    };
  });
  historyTimer = setTimeout(resolveHistory, HISTORY_WAIT_MS);
}

function historySyncFinished(syncType: unknown, status: string): boolean {
  const types = B?.proto?.HistorySync?.HistorySyncType || {};
  // INITIAL_BOOTSTRAP only starts the sync; RECENT/FULL completion means the
  // messages needed for contextual translation have arrived.
  return status === 'paused' ||
    (status === 'complete' && syncType !== types.INITIAL_BOOTSTRAP);
}

function rememberContacts(contacts: Array<{ id?: string; name?: string; notify?: string; verifiedName?: string }>): void {
  for (const contact of contacts || []) {
    if (!contact?.id) continue;
    const old = profileCache.get(contact.id) || { name: '?', photo: null, photoLoaded: false };
    old.name = contact.name || contact.notify || contact.verifiedName || old.name;
    profileCache.set(contact.id, old);
  }
}

function unwrapContent(message: any): any {
  let content = message || {};
  for (let i = 0; i < 5; i += 1) {
    const wrapper = ['ephemeralMessage', 'viewOnceMessage', 'viewOnceMessageV2', 'viewOnceMessageV2Extension', 'documentWithCaptionMessage', 'editedMessage']
      .find((key) => content[key]?.message);
    if (!wrapper) break;
    content = content[wrapper].message;
  }
  return content;
}

function bodyOf(m: RawMessage): string {
  const msg = unwrapContent(m.message);
  return (
    msg.conversation ||
    msg.extendedTextMessage?.text ||
    msg.imageMessage?.caption ||
    msg.videoMessage?.caption ||
    msg.documentMessage?.caption ||
    ''
  );
}

function mediaTypeOf(m: RawMessage): string | null {
  const msg = unwrapContent(m.message);
  return ['imageMessage', 'videoMessage', 'stickerMessage', 'audioMessage', 'documentMessage']
    .find((type) => msg[type]) || null;
}

function contextInfoOf(m: RawMessage): any {
  const msg = unwrapContent(m.message);
  for (const type of ['extendedTextMessage', 'imageMessage', 'videoMessage', 'audioMessage', 'documentMessage', 'stickerMessage']) {
    if (msg[type]?.contextInfo) return msg[type].contextInfo;
  }
  return null;
}

function quotedBodyOf(m: RawMessage): string | null {
  const quoted = contextInfoOf(m)?.quotedMessage;
  return quoted ? bodyOf({ message: quoted }) || '[media]' : null;
}

function mediaMimeTypeOf(m: RawMessage, type: string): string {
  const media = unwrapContent(m.message)[type];
  return media?.mimetype || 'application/octet-stream';
}

async function startSocket(): Promise<void> {
  if (starting) return;
  starting = true;
  beginHistorySync();
  try {
    const { useMultiFileAuthState, makeWASocket, fetchLatestBaileysVersion, Browsers } = B;
    const auth = await useMultiFileAuthState(SESSION_DIR);
    const { version } = await fetchLatestBaileysVersion();
    sock = makeWASocket({
      auth: auth.state,
      version,
      // WhatsApp currently rejects WIN32/DARWIN Desktop sub-platforms with 428
      // before emitting a QR. Ubuntu/Chrome keeps WEB_BROWSER and still requests
      // full history through syncFullHistory.
      browser: Browsers.ubuntu('Chrome'),
      syncFullHistory: true,
      shouldSyncHistoryMessage: () => true,
      markOnlineOnConnect: false,
      printQRInTerminal: false,
    });
    sock.ev.on('creds.update', auth.saveCreds);
    sock.ev.on('messaging-history.set', ({ messages = [], contacts = [] }: { messages?: RawMessage[]; contacts?: unknown[] }) => {
      rememberContacts(contacts as never);
      const groups = messages.filter(isGroupMessage);
      rememberMany(groups);
      if (groups.length && onHistory) {
        onHistory({
          groupIds: [...new Set(groups.map((msg) => msg.key?.remoteJid as string))],
          count: groups.length,
        });
      }
    });
    sock.ev.on('messaging-history.status', ({ syncType, status, explicit }: { syncType: unknown; status: string; explicit?: unknown }) => {
      const complete = historySyncFinished(syncType, status);
      if (complete) resolveHistory();
      if (onHistory) onHistory({ groupIds: [], count: 0, status, explicit, complete });
    });
    sock.ev.on('connection.update', async ({ connection, qr }: { connection?: string; qr?: unknown }) => {
      if (qr) {
        const url = await qrcode.toDataURL(qr as never).catch(() => null);
        if (url && onQr) onQr(url);
      }
      if (connection === 'open') {
        ready = true;
        if (onReady) onReady();
      }
      if (connection === 'close') {
        ready = false;
        // ponytail: restart every unexpected close; add reason-specific handling if needed
        setTimeout(startSocket, 3000);
      }
    });
    sock.ev.on('messages.upsert', ({ messages, type }: { messages: RawMessage[]; type: string }) => {
      if (type !== 'notify') return;
      for (const msg of messages) {
        if (!isGroupMessage(msg)) continue;
        remember(msg);
        if (onMessage) onMessage(msg);
      }
    });
  } finally {
    starting = false;
  }
}

export function init(options: {
  onQrCb: (url: string) => void;
  onReadyCb: () => void;
  onMsgCb: (msg: RawMessage) => void;
  onHistoryCb: (info: Record<string, unknown>) => void;
}): void {
  onQr = options.onQrCb;
  onReady = options.onReadyCb;
  onMessage = options.onMsgCb;
  onHistory = options.onHistoryCb;
  import('baileys')
    .then((mod) => {
      B = mod;
      return startSocket();
    })
    .catch(console.error);
}

export function isReady(): boolean {
  return ready;
}

export async function waitForHistory(): Promise<void> {
  return historyReady;
}

export async function getGroups(): Promise<GroupInfo[]> {
  const groups = await sock.groupFetchAllParticipating();
  const groupList = Object.values(groups) as Array<{ id: string; subject?: string; participants?: unknown[] }>;
  for (const group of groupList) rememberContacts((group.participants || []) as never);
  return groupList
    .map((group) => ({ id: group.id, name: group.subject || group.id }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

async function profileOf(jid: string): Promise<{ name: string; photo: string | null }> {
  const entry = profileCache.get(jid) || { name: '?', photo: null, photoLoaded: false };
  profileCache.set(jid, entry);
  if (!entry.photoLoaded) {
    entry.photoLoaded = true;
    try {
      entry.photo = (await sock.profilePictureUrl(jid, 'image')) || null;
    } catch {}
  }
  return entry;
}

export async function toMessageDTO(msg: RawMessage): Promise<MessageDTO> {
  const senderJid = msg.key?.participant || msg.key?.remoteJid;
  const profile = await profileOf(senderJid || '');
  if (msg.pushName && profile.name === '?') profile.name = msg.pushName;
  const mediaType = mediaTypeOf(msg);
  return {
    id: msg.key?.id as string,
    chatId: msg.key?.remoteJid as string,
    body: bodyOf(msg),
    from: senderJid,
    fromMe: Boolean(msg.key?.fromMe),
    name: msg.pushName || profile.name || '?',
    photo: profile.photo,
    timestamp: history.timestampOf(msg) * 1000,
    hasMedia: Boolean(mediaType),
    mediaType: mediaType || '',
    quoted: quotedBodyOf(msg),
  };
}

export async function mediaDataUrl(msg: RawMessage): Promise<string | null> {
  const type = mediaTypeOf(msg);
  if (!type) return null;
  try {
    const buffer = await B.downloadMediaMessage(msg, 'buffer', {}, {
      logger: sock.logger,
      reuploadRequest: sock.updateMediaMessage,
    });
    if (buffer) {
      return 'data:' + mediaMimeTypeOf(msg, type) + ';base64,' + Buffer.from(buffer).toString('base64');
    }
  } catch {}
  return null;
}

export async function getMessages(groupId: string, limit = 50): Promise<RawMessage[]> {
  const page = await getMessagesPage(groupId, limit);
  return page.messages;
}

export async function getMessagesPage(groupId: string, limit = 50, before: Cursor | null = null): Promise<RawPageResult> {
  const count = Math.max(1, Number(limit) || 50);
  const stored = history.forChat(groupId);
  const byId = new Map<string, RawMessage>(stored.map((msg) => [msg.key?.id as string, msg as RawMessage]));
  for (const msg of recent.values()) {
    if (msg.key?.remoteJid === groupId) byId.set(msg.key?.id as string, msg);
  }
  const all = [...byId.values()]
    .sort((a, b) =>
      history.timestampOf(a) - history.timestampOf(b) ||
      String(a.key?.id || '').localeCompare(String(b.key?.id || ''))
    );
  const filtered = before
    ? all.filter((msg) => compareToCursor(msg, before) < 0)
    : all;
  const messages = filtered.slice(-count);
  return {
    messages,
    hasMore: filtered.length > messages.length,
    cursor: messages.length ? cursorOf(messages[0]) : before,
  };
}

export async function sendText(chatId: string, text: string): Promise<RawMessage> {
  const sent = await sock.sendMessage(chatId, { text });
  if (sent?.key?.id) {
    sent.key.remoteJid ||= chatId;
    sent.key.fromMe = true;
    if (!sent.message) sent.message = { conversation: text };
    remember(sent);
  }
  return sent;
}

export async function replyTo(messageId: string, text: string): Promise<RawMessage> {
  const msg = recent.get(messageId) || (history.get(messageId) as RawMessage | null);
  if (!msg) throw new Error('message not in history');
  const sent = await sock.sendMessage(msg.key?.remoteJid, { text }, { quoted: msg });
  if (sent?.key?.id) {
    sent.key.remoteJid ||= msg.key?.remoteJid;
    sent.key.fromMe = true;
    if (!sent.message) sent.message = { conversation: text };
    remember(sent);
  }
  return sent;
}

export function recentGet(id: string): RawMessage | null {
  return recent.get(id) || (history.get(id) as RawMessage | null);
}