import * as fs from 'node:fs';
import * as path from 'node:path';

export interface HistoryMessage {
  key?: { id?: string; remoteJid?: string; fromMe?: boolean; participant?: string };
  message?: any;
  messageTimestamp?: unknown;
  pushName?: string;
}

// Read lazily so tests that set WA_DATA_DIR after import order still isolate.
function dataDir(): string {
  return process.env.WA_DATA_DIR || path.join(__dirname, '..', '..', 'data');
}
const HISTORY_FILE = () => path.join(dataDir(), 'history.jsonl');
const messages = new Map<string, HistoryMessage>();

function encode(value: unknown): unknown {
  if (value === null || value === undefined || typeof value !== 'object') {
    if (typeof value === 'bigint') return { __waBigInt: value.toString() };
    return value;
  }
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return { __waBuffer: Buffer.from(value).toString('base64') };
  }
  if (Array.isArray(value)) return value.map(encode);
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (item !== undefined && typeof item !== 'function') out[key] = encode(item);
  }
  return out;
}

function decode(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(decode);
  if (!value || typeof value !== 'object') return value;
  const record = value as Record<string, unknown>;
  if (typeof record.__waBuffer === 'string') return Buffer.from(record.__waBuffer, 'base64');
  if (typeof record.__waBigInt === 'string') return BigInt(record.__waBigInt);
  return Object.fromEntries(Object.entries(record).map(([key, item]) => [key, decode(item)]));
}

export function timestampOf(message: { messageTimestamp?: unknown } | null | undefined): number {
  const value = message && message.messageTimestamp;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return Number(value) || 0;
  if (value && typeof (value as { toNumber?: unknown }).toNumber === 'function') {
    return (value as { toNumber(): number }).toNumber();
  }
  const low = (value as { low?: number } | undefined)?.low;
  const high = (value as { high?: number } | undefined)?.high;
  if (low !== undefined && Number.isFinite(low) && high !== undefined && Number.isFinite(high)) {
    return low + high * 0x100000000;
  }
  return 0;
}

function load(): void {
  try {
    const lines = fs.readFileSync(HISTORY_FILE(), 'utf8').split('\n');
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const message = decode(JSON.parse(line)) as HistoryMessage;
        if (message?.key?.id) messages.set(message.key.id, message);
      } catch {}
    }
  } catch {}
}

function append(records: unknown[]): void {
  if (!records.length) return;
  fs.mkdirSync(dataDir(), { recursive: true });
  fs.appendFileSync(HISTORY_FILE(), records.map((message) => JSON.stringify(encode(message))).join('\n') + '\n');
}

export function upsert(message: HistoryMessage): void {
  const id = message?.key?.id;
  if (!id) return;
  messages.set(id, message);
  append([message]);
}

export function upsertMany(records: HistoryMessage[]): void {
  const valid = records.filter((message) => message?.key?.id);
  if (!valid.length) return;
  for (const message of valid) messages.set(message.key?.id as string, message);
  append(valid);
}

export function forChat(chatId: string, limit?: number): HistoryMessage[] {
  const found = [...messages.values()]
    .filter((message) => message.key?.remoteJid === chatId)
    .sort((a, b) => timestampOf(a) - timestampOf(b));
  return Number.isFinite(limit) && (limit as number) > 0
    ? found.slice(-(limit as number))
    : found;
}

export function get(id: string): HistoryMessage | null {
  return messages.get(id) || null;
}

export const size = (): number => messages.size;

load();