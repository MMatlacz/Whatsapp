import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';

// Translation logs are append-only so each attempt remains available even when
// a later retranslation replaces the cached result.
// Read lazily so tests that set WA_DATA_DIR after import order still isolate.
function dataDir(): string {
  return process.env.WA_DATA_DIR || path.join(__dirname, '..', '..', 'data');
}
const LOG_FILE = () => path.join(dataDir(), 'translation-log.jsonl');
const INCLUDE_CONTENT = process.env.WA_TRANSLATION_LOG_CONTENT === '1';

export function id(): string {
  return crypto.randomUUID();
}

function hash(value: unknown): string {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

export function textMeta(value: unknown): { chars: number; sha256: string; text?: string } {
  const text = String(value ?? '');
  const meta: { chars: number; sha256: string; text?: string } = { chars: text.length, sha256: hash(text) };
  if (INCLUDE_CONTENT) meta.text = text;
  return meta;
}

function safeError(err: unknown): string {
  return String((err as Error | undefined)?.message || err).slice(0, 1000);
}

export function write(event: string, fields: Record<string, unknown> = {}): Record<string, unknown> {
  const record = {
    timestamp: new Date().toISOString(),
    event,
    ...fields,
  };
  try {
    fs.mkdirSync(dataDir(), { recursive: true });
    fs.appendFileSync(LOG_FILE(), JSON.stringify(record) + '\n');
  } catch (err) {
    // Logging must never make a translation fail, but surface a write problem
    // in the process console so it can be diagnosed.
    console.error('translation log write failed:', safeError(err));
  }
  return record;
}

export function request(fields: Record<string, unknown> = {}): string {
  const requestId = (fields.requestId as string | undefined) || id();
  write('translation_requested', { requestId, ...fields });
  return requestId;
}

export function input(requestId: string, text: unknown, fields: Record<string, unknown> = {}): void {
  write('translation_input', { requestId, input: textMeta(text), ...fields });
}

// The prompt is already name/handle-masked by translator.ts. Keep its text in
// the local log so a retry can be audited without sending unmasked identities
// to a provider. This is intentionally separate from textMeta(), whose
// default remains hash-only for ordinary input/output records.
export function modelPrompt(requestId: string, prompt: string, fields: Record<string, unknown> = {}): void {
  write('model_prompt', { requestId, prompt: String(prompt), ...fields });
}

export function modelRequest(requestId: string, fields: Record<string, unknown> = {}): void {
  write('model_request', { requestId, ...fields });
}

export function providerStarted(requestId: string, provider: string, index: number, fields: Record<string, unknown> = {}): void {
  write('provider_attempt_started', { requestId, provider, index, ...fields });
}

export function providerFinished(requestId: string, provider: string, index: number, startedAt: number, fields: Record<string, unknown> = {}): void {
  write('provider_attempt_finished', {
    requestId,
    provider,
    index,
    durationMs: Math.max(0, Date.now() - startedAt),
    ...fields,
  });
}

export function output(requestId: string, text: unknown, fields: Record<string, unknown> = {}): void {
  write('translation_output', { requestId, output: textMeta(text), ...fields });
}

export function error(requestId: string, err: unknown, fields: Record<string, unknown> = {}): void {
  write('translation_error', { requestId, error: safeError(err), ...fields });
}

export function filePath(): string {
  return LOG_FILE();
}