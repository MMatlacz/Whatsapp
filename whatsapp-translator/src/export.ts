import * as fs from 'node:fs';
import * as path from 'node:path';
import type { TranslationEntry } from './cache';

// Export — language-learning exports: sentence pairs + unfamiliar-word list.
// Unfamiliar = words of the original that are NOT known words and not stopwords.

const STOPWORDS = new Set([
  // Indonesian
  'yang', 'dan', 'di', 'ke', 'dari', 'itu', 'ini', 'dengan', 'untuk', 'tidak',
  'ada', 'saya', 'aku', 'kamu', 'anda', 'kita', 'mereka', 'dia', 'akan', 'bisa',
  'sudah', 'juga', 'tapi', 'tetapi', 'karena', 'atau', 'saat', 'ketika', 'sebagai',
  'adalah', 'pada', 'dalam', 'oleh', 'jika', 'kalau', 'agar', 'supaya', 'saja',
  'lagi', 'masih', 'belum', 'harus', 'perlu', 'boleh', 'mau', 'ingin', 'sedang',
  'telah', 'hanya', 'semua', 'banyak', 'sangat', 'lebih', 'paling', 'ga', 'gak',
  // English
  'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'is', 'are', 'be', 'i', 'you',
  'it', 'we', 'they', 'this', 'that', 'not', 'with', 'for', 'on', 'at',
]);

export function wordsOf(text: string): string[] {
  return (text.toLowerCase().match(/[a-ząćęłńóśźż]+/g) || []);
}

export interface ExportData {
  sentences: Array<{ original: string; translation: string }>;
  words: Array<{ word: string; count: number }>;
}

interface CacheLike {
  allTranslations(): Record<string, TranslationEntry>;
  knownWords(): string[];
}

export function build(cache: CacheLike): ExportData {
  const translations = cache.allTranslations();
  const known = new Set(cache.knownWords().map((w) => w.toLowerCase()));
  const sentences: ExportData['sentences'] = [];
  const freq = new Map<string, number>();
  for (const entry of Object.values(translations)) {
    if (!entry.translation) continue;
    sentences.push({ original: entry.original, translation: entry.translation });
    for (const w of wordsOf(entry.original)) {
      if (w.length < 2 || known.has(w) || STOPWORDS.has(w)) continue;
      freq.set(w, (freq.get(w) || 0) + 1);
    }
  }
  const words = [...freq.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([word, count]) => ({ word, count }));
  return { sentences, words };
}

export function run(cache: CacheLike): { file: string; sentences: number; words: number } {
  const data = build(cache);
  const dir = path.join(__dirname, '..', '..', 'data', 'export');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'learning-' + new Date().toISOString().slice(0, 10) + '.json');
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
  return { file, sentences: data.sentences.length, words: data.words.length };
}