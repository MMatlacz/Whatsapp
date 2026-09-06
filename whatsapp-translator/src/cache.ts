import * as fs from 'node:fs';
import * as path from 'node:path';
import type { Token } from './tokens';
import type { VocabularyEntry } from './vocabulary';

// ponytail: single JSON-file store; swap for SQLite only if writes get heavy

export interface TranslationEntry {
  original: string;
  translation?: string;
  comment?: string;
  edited: boolean;
  revision: number;
  [extra: string]: unknown;
}

interface Store {
  translations: Record<string, TranslationEntry>;
  knownWords: string[];
  vocabulary?: Record<string, VocabularyEntry>;
}

// Read lazily so tests that set WA_DATA_DIR after import order still isolate.
function dataDir(): string {
  return process.env.WA_DATA_DIR || path.join(__dirname, '..', '..', 'data');
}
const CACHE_FILE = () => path.join(dataDir(), 'cache.json');

function load(): Store {
  try {
    return JSON.parse(fs.readFileSync(CACHE_FILE(), 'utf8')) as Store;
  } catch {
    return { translations: {}, knownWords: [] };
  }
}

let store: Store = load();

function save(): void {
  fs.mkdirSync(dataDir(), { recursive: true });
  fs.writeFileSync(CACHE_FILE(), JSON.stringify(store, null, 2));
}

export const cache = {
  getTranslation(id: string): TranslationEntry | null {
    return store.translations[id] || null;
  },

  // retranslate overwrites a manually edited translation (adjudicated, per message)
  setTranslation(id: string, original: string, translation: string, extra: Record<string, unknown> = {}): void {
    const revision = (store.translations[id]?.revision || 0) + 1;
    store.translations[id] = {
      original,
      translation,
      comment: '',
      edited: false,
      ...extra,
      revision,
    };
    save();
  },

  getVocabulary(key: string): VocabularyEntry | null {
    return store.vocabulary?.[key] || null;
  },

  setVocabulary(key: string, result: VocabularyEntry): void {
    store.vocabulary ||= {};
    store.vocabulary[key] = result;
    // Bound the persistent learning cache without deleting translations.
    const keys = Object.keys(store.vocabulary);
    for (const old of keys.slice(0, Math.max(0, keys.length - 500))) delete store.vocabulary[old];
    save();
  },

  knownWords(): string[] {
    return store.knownWords;
  },

  addKnownWord(word: string): void {
    const lower = word.toLowerCase();
    if (!store.knownWords.some((w) => w.toLowerCase() === lower)) {
      store.knownWords.push(word);
      save();
    }
  },

  removeKnownWord(word: string): void {
    const lower = word.toLowerCase();
    store.knownWords = store.knownWords.filter((w) => w.toLowerCase() !== lower);
    save();
  },

  allTranslations(): Record<string, TranslationEntry> {
    return store.translations;
  },
};

export default cache;