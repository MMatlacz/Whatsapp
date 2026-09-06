import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

function readJson(file: string): Record<string, unknown> | null {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8')) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function fromAuthJson(provider: string): string {
  const auth = readJson(path.join(os.homedir(), '.pi', 'agent', 'auth.json'));
  const entry = auth?.[provider] as { key?: unknown } | undefined;
  const key = typeof entry?.key === 'string' ? entry.key.trim() : '';
  return key || '';
}

function fromProviderKeys(provider: string): string {
  const store = readJson(path.join(os.homedir(), '.pi', 'agent', 'provider-keys.json'));
  const entry = store?.[provider] as { keys?: unknown[]; activeKeyName?: unknown } | undefined;
  const keys = Array.isArray(entry?.keys) ? entry.keys : [];
  const selected = keys.find((item) => (item as { name?: unknown })?.name === entry?.activeKeyName) || keys[0];
  const key = typeof (selected as { apiKey?: unknown } | undefined)?.apiKey === 'string'
    ? (selected as { apiKey: string }).apiKey.trim()
    : '';
  return key || '';
}

export function readProviderKey(provider: string): string {
  return fromAuthJson(provider) || fromProviderKeys(provider) || '';
}