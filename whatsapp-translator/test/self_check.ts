import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

process.env.WA_DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'wa-test-'));
// Do not spawn the user's installed Kilo CLI during the deterministic unit run.
process.env.KILO_API_KEY = '';
process.env.KILO_KEY = '';
process.env.KILO_AUTOSTART = '0';

import cache from '../src/cache';
import * as history from '../src/history';
import type { HistoryMessage } from '../src/history';
import { buildPrompt, maskNames } from '../src/translator';
import { build as buildExport } from '../src/export';
import * as gateway from '../src/gateway';

function translation(id: string) {
  const entry = cache.getTranslation(id);
  assert.ok(entry, 'missing translation entry');
  return entry as NonNullable<typeof entry>;
}

// --- history: survives a module reload and preserves media bytes ---
const historyMessage: HistoryMessage = {
  key: { id: 'history-1', remoteJid: 'group@g.us' },
  message: { imageMessage: { mediaKey: new Uint8Array([1, 2, 3]) } },
  messageTimestamp: 1,
};
history.upsert(historyMessage);
assert.strictEqual(history.forChat('group@g.us', 10)[0].key!.id, 'history-1');
delete require.cache[require.resolve('../src/history')];
const reloadedHistory = require('../src/history') as typeof history;
assert.deepStrictEqual([...reloadedHistory.forChat('group@g.us', 10)[0].message.imageMessage.mediaKey], [1, 2, 3]);

// --- cache: set/get, retranslate overwrites an edit (adjudicated) ---
cache.setTranslation('m1', 'Halo dunia', 'Witaj świecie', {});
assert.strictEqual(translation('m1').translation!, 'Witaj świecie');
assert.strictEqual(translation('m1').edited, false);

cache.setTranslation('m1', 'Halo dunia', 'Hej świecie', { edited: true });
assert.strictEqual(translation('m1').edited, true);

cache.setTranslation('m1', 'Halo dunia', 'Cześć świecie', {}); // retranslate
assert.strictEqual(translation('m1').translation!, 'Cześć świecie');
assert.strictEqual(translation('m1').edited, false);

// --- known words: dedupe + remove ---
cache.addKnownWord('Halo');
cache.addKnownWord('halo');
assert.deepStrictEqual(cache.knownWords(), ['Halo']);
cache.removeKnownWord('Halo');
assert.deepStrictEqual(cache.knownWords(), []);

// --- export: unfamiliar words exclude known + stopwords ---
cache.addKnownWord('dunia');
cache.addKnownWord('halo');
cache.setTranslation('m1', 'Halo dunia yang indah', 'Witaj świecie, który jest piękny', {});
cache.setTranslation('m2', 'Halo dunia', 'Witaj świecie', {});
const data = buildExport(cache);
assert.strictEqual(data.sentences.length, 2);
assert.ok(data.words.some((w: { word: string }) => w.word === 'indah'));
assert.ok(!data.words.some((w: { word: string }) => ['dunia', 'yang', 'halo'].includes(w.word)));
assert.ok(data.words.every((w: { count: number }) => w.count >= 1));

// --- prompt: carries context + known words + comment ---
const prompt = buildPrompt('Halo dunia', {
  context: ['Apa kabar?', 'Baik baik saja', 'Related quoted message:\n- Besok?'],
  knownWords: ['dunia'],
  comment: 'formal tone',
});
assert.ok(prompt.includes('Apa kabar?'));
assert.ok(prompt.includes('Baik baik saja'));
assert.ok(prompt.includes('Related quoted message'));
assert.ok(prompt.includes('dunia'));
assert.ok(prompt.includes('formal tone'));

// --- privacy: names + handles masked, placeholders in prompt ---
const masked = maskNames(['Halo Budi, @6281234'], ['Budi']);
assert.ok(masked.texts[0].includes('{{P1}}'));
assert.ok(!masked.texts[0].includes('Budi'));
assert.ok(!masked.texts[0].includes('@6281234'));
assert.ok(Object.values(masked.map).includes('Budi'));
const maskedPrompt = buildPrompt(masked.texts[0], { hasPlaceholders: true });
assert.ok(maskedPrompt.includes('keep them exactly as they are'));

// --- privacy: Unicode names and all provider-bound prompt fields use the same map ---
const unicodeMasked = maskNames(['Halo Łukasz, @contoh', 'ŁUKASZ'], ['Łukasz']);
assert.ok(unicodeMasked.texts.every((text) => !text.includes('Łukasz') && !text.includes('ŁUKASZ')));
assert.strictEqual(unicodeMasked.texts[0].match(/\{\{P\d+\}\}/g)![0], unicodeMasked.texts[1]);

// --- gateway: cursor pages include outgoing messages and do not skip same-chat history ---
for (const [id, timestamp, fromMe] of [
  ['page-1', 1, false],
  ['page-2', 2, true],
  ['page-3', 3, false],
] as Array<[string, number, boolean]>) {
  gateway.remember({
    key: { id, remoteJid: 'page-group@g.us', fromMe },
    message: { conversation: id },
    messageTimestamp: timestamp,
  });
}

// Provider behavior is covered in free_translation.js with bounded routing.
(async () => {
  const firstPage = await gateway.getMessagesPage('page-group@g.us', 2);
  assert.deepStrictEqual(firstPage.messages.map((msg) => msg.key!.id), ['page-2', 'page-3']);
  assert.strictEqual(firstPage.hasMore, true);
  const olderPage = await gateway.getMessagesPage('page-group@g.us', 2, firstPage.cursor);
  assert.deepStrictEqual(olderPage.messages.map((msg) => msg.key!.id), ['page-1']);
  assert.strictEqual(olderPage.hasMore, false);
  fs.rmSync(process.env.WA_DATA_DIR as string, { recursive: true, force: true });
  console.log('self-check OK');
})().catch((err) => { console.error(err); process.exitCode = 1; });
