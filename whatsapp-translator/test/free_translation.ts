import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';

process.env.WA_DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'wa-free-test-'));
process.env.OPENROUTER_API_KEY = 'synthetic-test-key';

import { createRouter, MODELS } from '../src/free-router';
import type { Router } from '../src/free-router';
import { translateChain } from '../src/translator';
import { generateVocabulary, validateVocabulary, cacheKey as vocabularyCacheKey } from '../src/vocabulary';
import { tokenize } from '../src/tokens';
import cache from '../src/cache';

const response = (content: string, finish = 'stop') => ({ ok: true,
  json: async () => ({ choices: [{ finish_reason: finish, message: { content } }] }) });
const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const abortingFetch = (_url: string, options: RequestInit) => new Promise((_resolve, reject) => {
  options.signal?.addEventListener('abort', () => reject(options.signal?.reason), { once: true });
});

(async () => {
  const calls: Array<{ model?: string; messages: Array<{ content: string }>; provider?: unknown }> = [];
  const router = createRouter({ getKey: () => 'synthetic', fetchImpl: async (_url, options) => {
    const body = JSON.parse(String(options.body)) as { provider?: { max_price?: unknown }; messages?: Array<{ content: string }>; model?: string };
    calls.push(body as never);
    assert.deepEqual(body.provider?.max_price, { prompt: 0, completion: 0 });
    if (calls.length === 1) return { ok: false, status: 429, headers: { get: () => '60' } };
    return response('Dobrze');
  } });
  assert.equal((await router.request('synthetic')).value, 'Dobrze');
  assert.equal(calls.length, 2);
  await router.request('synthetic');
  assert.equal(calls.length, 3, 'cooling-down primary is skipped');
  assert.equal(calls[2].model, MODELS[1]);
  await assert.rejects(router.request('synthetic', { models: ['paid/model'] }), /approved free/);
  await assert.rejects(router.request('x'.repeat(24001)), /nothing was truncated/);
  assert.equal(calls.length, 3);
  await assert.rejects(createRouter({ getKey: () => '' }).request('synthetic'), /key is required/);

  let attempts = 0;
  const invalid = createRouter({ getKey: () => 'synthetic', fetchImpl: async () => { attempts++; return response('partial', 'length'); } });
  await assert.rejects(invalid.request('synthetic'), /Incomplete/);
  assert.equal(attempts, 2);
  attempts = 0;
  await assert.rejects(createRouter({ getKey: () => 'synthetic', fetchImpl: async () => {
    attempts++; return { ok: false, status: 401 };
  } }).request('synthetic'), /401/);
  assert.equal(attempts, 1);

  const timed = createRouter({ getKey: () => 'synthetic', attemptMs: 15, totalMs: 80, fetchImpl: abortingFetch });
  const start = Date.now();
  await assert.rejects(timed.request('synthetic'), /timeout/);
  assert.ok(Date.now() - start < 250, 'timeouts bound waiting');
  const controller = new AbortController();
  const cancelled = timed.request('synthetic', { signal: controller.signal });
  controller.abort();
  await assert.rejects(cancelled, /cancelled/);
  const queued = createRouter({ getKey: () => 'synthetic', attemptMs: 200, totalMs: 20, concurrency: 1, fetchImpl: abortingFetch });
  const queuedResults = await Promise.allSettled([queued.request('first'), queued.request('second')]);
  assert.ok(queuedResults.every((value) => value.status === 'rejected' && /deadline/.test(String(value.reason))));
  let active = 0;
  let maxActive = 0;
  const limited: Router = createRouter({ getKey: () => 'synthetic', concurrency: 2, fetchImpl: async () => {
    maxActive = Math.max(maxActive, ++active); await wait(10); active--; return response('ok');
  } });
  await Promise.all(Array.from({ length: 6 }, () => limited.request('synthetic')));
  assert.equal(maxActive, 2);

  const source = 'Élodie, anak-anak bisa, bisa! @用户 👋';
  const tokens = tokenize(source);
  assert.deepEqual(tokens.map((token) => token.text), ['Élodie', 'anak-anak', 'bisa', 'bisa', '@用户']);
  tokens.forEach((token) => assert.equal(source.slice(token.start, token.end), token.text));
  const valid = { words: tokens.map((token) => ({ id: token.id, meaning: 'znaczenie' })),
    phrases: [{ start: 1, end: 2, meaning: 'krótkie' }, { start: 1, end: 3, meaning: 'dłuższe' }] };
  assert.equal(validateVocabulary(JSON.stringify(valid), tokens).phrases[0].end, 3);
  for (const invalidValue of [
    { ...valid, words: valid.words.slice(1) },
    { ...valid, words: [...valid.words.slice(1), valid.words[1]] },
    { ...valid, phrases: [{ start: 2, end: 99, meaning: 'bad' }] },
    { ...valid, phrases: [{ start: 3, end: 1, meaning: 'bad' }] },
    { ...valid, words: valid.words.map((word) => ({ ...word, meaning: 'x'.repeat(301) })) },
  ]) assert.throws(() => validateVocabulary(JSON.stringify(invalidValue), tokens), /Invalid|cover/);
  assert.throws(() => validateVocabulary('```json\n{}\n```', tokens), /not JSON/);
  assert.notEqual(vocabularyCacheKey({ body: 'one', revision: 1 }), vocabularyCacheKey({ body: 'one', revision: 2 }));
  assert.notEqual(vocabularyCacheKey({ body: 'one', context: ['A'] }), vocabularyCacheKey({ body: 'one', context: ['B'] }));
  assert.notEqual(vocabularyCacheKey({ body: 'one', translation: 'A' }), vocabularyCacheKey({ body: 'one', translation: 'B' }));

  const realFetch = global.fetch;
  let networkCalls = 0;
  const seen: string[] = [];
  global.fetch = (async (_url, options) => {
    networkCalls++;
    const body = JSON.parse(String(options?.body)) as { messages: Array<{ content: string }> };
    const prompt = body.messages[0].content;
    seen.push(prompt);
    for (const privateValue of ['Élodie', 'Łukasz', '@用户', '李', 'Santoso']) assert.ok(!prompt.includes(privateValue));
    if (prompt.startsWith('Explain Indonesian')) {
      const payload = JSON.parse(prompt.split('\n').at(-1) as string) as { tokens: Array<{ id: number }> };
      return response(JSON.stringify({ words: payload.tokens.map((token) => ({ id: token.id, meaning: 'znaczenie' })), phrases: [] }));
    }
    return response('{{P1}} — gotowe');
  }) as typeof fetch;
  assert.equal(await translateChain('Élodie', { names: ['Élodie'], context: ['Élodie'], knownWords: ['hello'], comment: 'Élodie' }), 'Élodie — gotowe');
  assert.ok(!seen[0].includes('Keep these words untranslated'));
  await translateChain('Élodie', { names: ['Élodie'], learningMode: true, knownWords: ['hello'] });
  assert.ok(seen[1].includes('Keep these words untranslated'));
  const meanings = await generateVocabulary({ body: 'Élodie Łukasz @用户 李 Agus Santoso bisa',
    translation: 'Élodie Łukasz @用户 李 Agus Santoso mogą', context: ['Élodie'], names: ['Élodie', 'Łukasz', '李', 'Agus Santoso'] });
  assert.equal(meanings.words[0].meaning, 'nazwa własna');
  assert.equal(meanings.words.at(-1)!.meaning, 'znaczenie');
  assert.equal(meanings.words.length, meanings.tokens.length);
  const beforeLong = networkCalls;
  await assert.rejects(generateVocabulary({ body: 'word '.repeat(161) }), /160 words/);
  assert.equal(networkCalls, beforeLong);
  cache.setVocabulary('test', meanings);
  assert.deepEqual(cache.getVocabulary('test'), meanings);
  delete require.cache[require.resolve('../src/cache')];
  const reloadedCache = (require('../src/cache') as { default: typeof cache }).default;
  assert.deepEqual(reloadedCache.getVocabulary('test'), meanings);
  global.fetch = realFetch;
  fs.rmSync(process.env.WA_DATA_DIR as string, { recursive: true, force: true });
  console.log('free translation OK: free-only route, deadlines, cancellation, cooldown, concurrency, Unicode, spans, privacy, cache');
})().catch((error) => { console.error(error); process.exitCode = 1; });
