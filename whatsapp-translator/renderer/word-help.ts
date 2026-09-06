// A single anchored popover; all provider text is rendered through textContent.
import type { VocabularyResult, WordMeaning, PhraseMeaning } from '../src/vocabulary';

export interface WordHelpMessage {
  id: string;
  chatId?: string;
  body: string;
  translation?: string | null;
  edited?: boolean;
}

export interface WordHelpApi {
  getMessage: (id: string) => WordHelpMessage | undefined;
  getScope: () => string;
  request: (id: string, chatId: string) => Promise<VocabularyResult>;
  markKnown: (word: string) => void;
  isKnown: (word: string) => boolean;
}

export function createWordHelp(api: WordHelpApi) {
  const panel = document.createElement('div');
  panel.id = 'word-help';
  panel.className = 'word-help hidden';
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-label', 'Word and phrase meanings');
  panel.setAttribute('aria-live', 'polite');
  document.body.append(panel);
  const cache = new Map<string, VocabularyResult>();
  const pending = new Map<string, Promise<VocabularyResult>>();
  let active: { el: HTMLElement; message: WordHelpMessage; key: string } | null = null;
  let sequence = 0;
  let epoch = 0;
  let timer: number | undefined;

  function close(): void {
    if (timer !== undefined) window.clearTimeout(timer);
    sequence++;
    active?.el.removeAttribute('aria-describedby');
    active = null;
    panel.classList.add('hidden');
    document.querySelectorAll('.phrase-active').forEach((el) => el.classList.remove('phrase-active'));
  }
  function signature(message: WordHelpMessage): string {
    return JSON.stringify([epoch, api.getScope(), message.id, message.body, message.translation, message.edited]);
  }
  function position(el: HTMLElement): void {
    const rect = el.getBoundingClientRect();
    const width = panel.offsetWidth;
    const height = panel.offsetHeight;
    panel.style.left = Math.max(8, Math.min(window.innerWidth - width - 8, rect.left)) + 'px';
    panel.style.top = Math.max(8, rect.bottom + height + 8 < window.innerHeight
      ? rect.bottom + 6 : rect.top - height - 6) + 'px';
  }
  function append(tag: keyof HTMLElementTagNameMap, text: string, className?: string): HTMLElement {
    const el = document.createElement(tag);
    el.textContent = text;
    if (className) el.className = className;
    panel.append(el);
    return el;
  }
  function render(result: VocabularyResult, current: { el: HTMLElement; message: WordHelpMessage; key: string }): void {
    panel.replaceChildren();
    const id = Number(current.el.dataset.token);
    const word: WordMeaning | undefined = result.words.find((w) => w.id === id);
    const phrase: PhraseMeaning | undefined = result.phrases.find((p) => p.start <= id && p.end >= id);
    const tokens = result.tokens;
    if (phrase) {
      append('strong', current.message.body.slice(tokens[phrase.start].start, tokens[phrase.end].end));
      append('div', phrase.meaning, 'phrase-meaning');
      const messageEl = current.el.closest('.msg');
      messageEl?.querySelectorAll('.word').forEach((el) => {
        const tokenId = Number((el as HTMLElement).dataset.token);
        if (tokenId >= phrase.start && tokenId <= phrase.end) el.classList.add('phrase-active');
      });
      append('div', 'Słowo w tym wyrażeniu', 'word-help-label');
    }
    append('div', (current.el.dataset.word || '') + ' — ' + (word?.meaning || 'Znaczenie niedostępne'));
    const known = append('button', api.isKnown(current.el.dataset.word || '') ? 'Oznacz jako nieznane' : 'Znam to słowo') as HTMLButtonElement;
    known.type = 'button';
    known.onclick = () => { api.markKnown(current.el.dataset.word || ''); close(); };
    const dismiss = append('button', 'Zamknij') as HTMLButtonElement;
    dismiss.type = 'button';
    dismiss.onclick = close;
    position(current.el);
  }
  async function open(el: HTMLElement, retry = false): Promise<void> {
    if (timer !== undefined) window.clearTimeout(timer);
    const message = api.getMessage(el.closest('.msg')?.getAttribute('data-id') || '');
    if (!message || !el.isConnected) return;
    close();
    const token = ++sequence;
    const key = signature(message);
    const current = { el, message, key };
    active = current;
    el.setAttribute('aria-describedby', panel.id);
    panel.classList.remove('hidden');
    panel.replaceChildren();
    if (retry) cache.delete(key);
    if (cache.has(key)) { render(cache.get(key) as VocabularyResult, current); return; }
    append('strong', el.dataset.word || '');
    append('div', 'Ładowanie znaczeń…');
    position(el);
    try {
      if (!pending.has(key)) {
        const job = api.request(message.id, message.chatId || '');
        pending.set(key, job);
        job.finally(() => { if (pending.get(key) === job) pending.delete(key); }).catch(() => {});
      }
      const result = await pending.get(key) as VocabularyResult;
      const fresh = api.getMessage(message.id);
      if (!fresh || signature(fresh) !== key) return;
      cache.set(key, result);
      if (cache.size > 100) cache.delete(cache.keys().next().value as string);
      if (token !== sequence || !el.isConnected) return;
      render(result, current);
    } catch (error) {
      if (token !== sequence || !el.isConnected) return;
      panel.replaceChildren();
      append('div', (error as Error).message || String(error), 'word-help-error');
      const retryButton = append('button', 'Spróbuj ponownie') as HTMLButtonElement;
      retryButton.type = 'button';
      retryButton.onclick = () => { void open(el, true); };
      position(el);
    }
  }
  const messages = document.querySelector('#messages') as HTMLElement;
  messages.addEventListener('pointerover', (event) => {
    const el = (event.target as HTMLElement).closest('.word') as HTMLElement | null;
    if (!el || event.pointerType === 'touch' || el === active?.el) return;
    if (timer !== undefined) window.clearTimeout(timer);
    timer = window.setTimeout(() => { void open(el); }, 220);
  });
  messages.addEventListener('pointerout', (event) => {
    if ((event.target as HTMLElement).closest('.word') && !panel.contains(event.relatedTarget as Node)) {
      if (timer !== undefined) window.clearTimeout(timer);
      timer = window.setTimeout(close, 160);
    }
  });
  panel.addEventListener('pointerenter', () => { if (timer !== undefined) window.clearTimeout(timer); });
  panel.addEventListener('pointerleave', (event) => {
    if (event.relatedTarget !== active?.el && !panel.contains(document.activeElement)) close();
  });
  messages.addEventListener('focusin', (event) => {
    const el = (event.target as HTMLElement).closest('.word') as HTMLElement | null;
    if (el) void open(el);
  });
  document.addEventListener('focusin', (event) => {
    if (active && event.target !== active.el && !panel.contains(event.target as Node)) close();
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') close();
  });
  document.addEventListener('pointerdown', (event) => {
    if (!(event.target as HTMLElement).closest('.word') && !panel.contains(event.target as Node)) close();
  });
  messages.addEventListener('scroll', close);
  window.addEventListener('resize', close);
  return {
    open: (el: HTMLElement) => open(el),
    close,
    reset(): void { epoch++; cache.clear(); close(); },
  };
}