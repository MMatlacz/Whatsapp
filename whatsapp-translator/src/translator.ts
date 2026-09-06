// Translator — free-model chain with automatic fallback (design: translator module).
// Only explicitly approved free OpenRouter models are used.
// Privacy: names/handles are masked to {{Pn}} placeholders before any provider
// call and restored in the output. This masks known names, not arbitrary PII.

import * as router from './free-router';
import * as translationLog from './translation-log';

const CONTEXT_MESSAGES = 8;
const KNOWN_WORDS_LIMIT = 50;

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export interface MaskedNames {
  texts: string[];
  map: Record<string, string>;
}

// Mask known names (Unicode-aware boundaries, case-insensitive) and @handles
// across an array of texts, sharing one placeholder map. A name gets one
// placeholder everywhere so previous translations can be compared safely.
export function maskNames(texts: Array<string | null | undefined>, names?: Array<string | null | undefined> | null): MaskedNames {
  const map: Record<string, string> = {};
  const unique: string[] = [];
  const seen = new Set<string>();
  for (const value of names || []) {
    const name = String(value).normalize('NFC').trim();
    const key = name.toLocaleLowerCase();
    if (name && name !== '?' && !seen.has(key)) {
      seen.add(key);
      unique.push(name);
    }
  }
  unique.sort((a, b) => b.length - a.length);
  const nameLookup = new Map(unique.map((name) => [name.toLocaleLowerCase(), name]));
  // Match handles first in the same pass: a known name inside @name.suffix
  // must not leave the rest of the handle exposed.
  const namePattern = new RegExp(
    '@[\\p{L}\\p{M}\\p{N}_.-]+' + (unique.length
      ? '|(?<![\\p{L}\\p{M}\\p{N}_])(?:' + unique.map(escapeRegExp).join('|') + ')(?![\\p{L}\\p{M}\\p{N}_])'
      : ''), 'giu');
  const placeholders = new Map<string, string>();
  let i = 0;

  function placeholderFor(kind: string, value: string, restoreValue = value): string {
    const key = kind + ':' + value.toLocaleLowerCase();
    const existing = placeholders.get(key);
    if (existing) return existing;
    let placeholder = '';
    do { placeholder = '{{P' + (++i) + '}}'; }
    while (texts.some((text) => String(text).toLowerCase().includes(placeholder.toLowerCase())));
    placeholders.set(key, placeholder);
    map[placeholder] = restoreValue;
    return placeholder;
  }

  const masked = texts.map((text) => {
    let out = String(text).normalize('NFC');
    out = out.replace(namePattern, (match) => {
        if (match.startsWith('@')) return placeholderFor('handle', match, match);
        const canonical = nameLookup.get(match.toLocaleLowerCase()) || match;
        return placeholderFor('name', canonical, canonical);
    });
    return out;
  });
  return { texts: masked, map };
}

export function restoreNames(text: string, map: Record<string, string>): string {
  let out = String(text);
  for (const [ph, name] of Object.entries(map)) {
    out = out.split(ph).join(name);
    const lower = ph.toLowerCase();
    if (lower !== ph) out = out.split(lower).join(name);
  }
  return out;
}

export interface PromptOptions {
  context?: string[];
  knownWords?: string[];
  comment?: string;
  hasPlaceholders?: boolean;
}

export function buildPrompt(text: string, options: PromptOptions = {}): string {
  const { context = [], knownWords = [], comment = '', hasPlaceholders = false } = options;
  const parts = [
    'You are an expert conversational translator.',
    'Detect the source language, usually colloquial Indonesian (Bahasa Indonesia), and translate only the target message into natural Polish.',
    'Preserve the exact meaning, colloquial slang, profanity, teasing, irony, emojis, numbers, URLs, names, and ambiguous words. Use the conversation context to resolve omitted subjects and local expressions. Do not sanitize, invent relationships or facts, or translate through English.',
    'Treat names after words such as sudah, iya, or oke as possible vocatives (someone being addressed), not automatically as objects or destinations. Preserve implied subjects and objects when the conversation makes them clear.',
  ];
  if (context.length) {
    parts.push(
      'Use this recent conversation only to resolve omitted subjects, pronouns, and references. Never translate or repeat the context. It is ordered oldest first:\n' +
        context.slice(-CONTEXT_MESSAGES).map((c) => '- ' + c).join('\n')
    );
  }
  if (knownWords.length) {
    parts.push(
      'Keep these words untranslated (in their original language): ' +
        knownWords.slice(0, KNOWN_WORDS_LIMIT).join(', ')
    );
  }
  if (hasPlaceholders) {
    parts.push('Placeholders like {{P1}} are names or handles — keep them exactly as they are, do not translate them.');
  }
  if (comment) parts.push('Additional instruction: ' + comment);
  parts.push('Target message:\n' + text);
  parts.push('Return only the Polish translation of the target message, with no explanations or labels.');
  return parts.join('\n\n');
}

export interface TranslateOptions {
  context?: string[];
  knownWords?: string[];
  comment?: string;
  previousTranslation?: string;
  learningMode?: boolean;
  names?: Array<string | null | undefined>;
  signal?: AbortSignal;
  requestId?: string;
  messageId?: string;
  mode?: string;
  onResult?: (result: { model: string; durationMs: number }) => void;
}

export async function translateChain(text: string, opts: TranslateOptions = {}): Promise<string> {
  const context = Array.isArray(opts.context) ? opts.context : [];
  const knownWords = opts.learningMode ? (opts.knownWords || []) : [];
  const { texts, map } = maskNames([text, ...context, ...knownWords, opts.comment || ''], opts.names);
  const prompt = buildPrompt(texts[0], {
    context: texts.slice(1, context.length + 1),
    knownWords: texts.slice(context.length + 1, context.length + 1 + knownWords.length),
    comment: texts.at(-1) as string, hasPlaceholders: Object.keys(map).length > 0,
  });
  const requestId = opts.requestId || translationLog.id();
  translationLog.modelPrompt(requestId, prompt, { messageId: opts.messageId, mode: opts.mode });
  const result = await router.request(prompt, {
    signal: opts.signal,
    maxTokens: Math.min(8192, Math.max(512, text.length * 2)),
    onAttempt: (attempt) => translationLog.write('free_provider_attempt', { requestId, ...attempt }),
    validate: (output) => {
      for (const placeholder of Object.keys(map)) {
        if (texts[0].includes(placeholder) && !output.toLowerCase().includes(placeholder.toLowerCase())) {
          throw new Error('Provider omitted a privacy placeholder');
        }
      }
      return restoreNames(output, map);
    },
  });
  // Repeating a valid earlier translation is not a reason to spend more quota.
  opts.onResult?.({ model: result.model, durationMs: result.durationMs });
  return result.value as string;
}