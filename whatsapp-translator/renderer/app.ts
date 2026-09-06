/* Renderer — group picker, chat view (manual contextual translation primary,
   original below), known-word marking, retranslate/edit, compose as-typed, export. */

import { tokenize } from '../src/tokens';
import { createWordHelp } from './word-help';
import type { MessageDTO, GroupInfo, PageResult } from '../src/types';

function $(sel: string): HTMLElement {
  return document.querySelector(sel) as HTMLElement;
}

interface UiState {
  groupId: string | null;
  messages: Map<string, MessageDTO>; // id -> dto
  translating: Map<string, string>; // chat/message key -> active UI request token
  knownWords: Set<string>;
  selectionVersion: number;
  requestSequence: number;
  historySequence: number;
  history: { hasMore: boolean; cursor: string | null; loading: boolean };
  inline: Map<string, { kind: 'edit' | 'retranslate' | 'reply'; box: HTMLElement }>;
  drafts: Map<string, string>;
  sending: Set<string>;
  operations: Map<string, string | number>;
}

const state: UiState = {
  groupId: null,
  messages: new Map(),
  translating: new Map(),
  knownWords: new Set(),
  selectionVersion: 0,
  requestSequence: 0,
  historySequence: 0,
  history: { hasMore: false, cursor: null, loading: false },
  inline: new Map(),
  drafts: new Map(),
  sending: new Set(),
  operations: new Map(),
};

const wordHelp = createWordHelp({ getMessage: (id) => state.messages.get(id),
  getScope: () => state.selectionVersion + ':' + state.historySequence,
  request: (id, chatId) => window.wa.vocabulary(id, chatId),
  markKnown: (word) => { void toggleWord(word); }, isKnown: (word) => state.knownWords.has(word.toLowerCase()) });

function translationKey(message: MessageDTO): string {
  return (message?.chatId || '') + '\u0000' + (message?.id || '');
}

function isCurrentSelection(version: number, groupId: string | null = state.groupId): boolean {
  return version === state.selectionVersion && state.groupId === groupId;
}

function normalizePage(result: PageResult | MessageDTO[]): PageResult {
  if (Array.isArray(result)) return { messages: result, hasMore: false, cursor: null };
  return {
    messages: Array.isArray(result?.messages) ? result.messages : [],
    hasMore: Boolean(result?.hasMore),
    cursor: result?.cursor || null,
  };
}

// The mocked-Electron smoke swaps window.getMessagesPage to delay a page; the
// app reads the global back at call time, keeping classic-script semantics.
function defaultGetMessagesPage(groupId: string, limit: number, before: string | null = null): Promise<PageResult | MessageDTO[]> {
  return typeof window.wa.getMessagesPage === 'function'
    ? window.wa.getMessagesPage(groupId, limit, before)
    : window.wa.getMessages(groupId, limit);
}
function getMessagesPage(groupId: string, limit: number, before: string | null = null): Promise<PageResult | MessageDTO[]> {
  const slot = (globalThis as { getMessagesPage?: typeof defaultGetMessagesPage }).getMessagesPage;
  return (slot || defaultGetMessagesPage)(groupId, limit, before);
}

function updateOlderButton(): void {
  const button = $('#load-older') as HTMLButtonElement;
  if (!button) return;
  button.disabled = state.history.loading;
  button.textContent = state.history.loading ? 'Loading older messages…' : 'Load older messages';
  button.classList.toggle('hidden', !state.history.hasMore && !state.history.loading);
}

function esc(s: string): string {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' } as Record<string, string>)[c]);
}

function wordSpans(text: string): string {
  const parts: string[] = [];
  let last = 0;
  for (const token of tokenize(text)) {
    if (token.start > last) parts.push(esc(text.slice(last, token.start)));
    const w = token.text;
    const known = state.knownWords.has(w.toLowerCase());
    parts.push(
      `<span class="word${known ? ' known' : ''}" data-word="${esc(w)}" data-token="${token.id}" tabindex="0" role="button" aria-label="${esc(w)}: meaning; Space marks known">${esc(w)}</span>`
    );
    last = token.end;
  }
  if (last < text.length) parts.push(esc(text.slice(last)));
  return parts.join('');
}

function timeOf(ts: number | undefined): string {
  if (!ts) return '';
  return new Date(ts).toLocaleTimeString('pl-PL', { hour: '2-digit', minute: '2-digit' });
}

function photoElement(html: string): HTMLElement {
  const holder = document.createElement('div');
  holder.innerHTML = html;
  return holder.firstChild as HTMLElement;
}

function renderMessage(m: MessageDTO): HTMLElement {
  const el = document.createElement('div');
  el.className = 'msg';
  el.dataset.id = m.id;

  const photo = m.photo ? `<img class="avatar" src="${esc(m.photo)}" />` : '<div class="avatar"></div>';

  let inner = `<div class="msg-head">${esc(m.name || '?')} · ${timeOf(m.timestamp)}</div>`;
  if (m.quoted) inner += `<div class="quoted">↪ ${esc(m.quoted)}</div>`;
  if (m.hasMedia && m.mediaUrl) {
    const isImage = (m.mediaType || '').startsWith('image');
    if (isImage) inner += `<img class="msg-media" src="${esc(m.mediaUrl)}" />`;
    else inner += `<div class="quoted">[media: ${esc(m.mediaType || '?')}]</div>`;
  }

  if (m.translation) {
    inner += `<div class="translation${m.edited ? ' edited' : ''}">${esc(m.translation)}</div>`;
  }

  if (m.body) {
    inner += `<div class="original">${wordSpans(m.body)}</div>`;
  }
  if (m.error) inner += `<div class="msg-error">${esc(m.error)}</div>`;

  const actions: string[] = [];
  if (!m.fromMe && m.body) {
    if (state.translating.has(translationKey(m))) {
      actions.push('<span class="translation-progress" role="status">Translating…</span>');
    } else if (m.translation) {
      actions.push('<button data-act="retranslate">↻ retranslate</button>');
      actions.push('<button data-act="edit">✎ edit</button>');
    } else {
      actions.push('<button data-act="translate">⇄ translate</button>');
    }
  }
  actions.push('<button data-act="reply">↪ reply</button>');
  inner += `<div class="msg-actions">${actions.join('')}</div>`;

  el.appendChild(photoElement(photo));
  const bubble = document.createElement('div');
  bubble.className = 'msg-body';
  bubble.innerHTML = inner;
  el.appendChild(bubble);
  const inline = state.inline.get(m.id);
  if (inline) {
    if (inline.kind === 'edit') bubble.querySelector('.translation')?.remove();
    bubble.appendChild(inline.box);
  }
  return el;
}

export function renderMessages(options: { scrollToBottom?: boolean } = {}): void {
  wordHelp.close();
  const box = $('#messages');
  box.innerHTML = '';
  const messages = [...state.messages.values()].sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));
  for (const m of messages) box.appendChild(renderMessage(m));
  if (options.scrollToBottom !== false) box.scrollTop = box.scrollHeight;
}

function mergeMessage(m: Partial<MessageDTO> & { id: string }, snapshot = false): MessageDTO | null {
  if (!m?.id) return null;
  const prev = state.messages.get(m.id);
  // merge: media/translation events carry partial DTOs
  const merged = { ...prev, ...m } as MessageDTO;
  if (snapshot && prev && 'translation' in prev) {
    for (const field of ['translation', 'edited', 'error'] as const) {
      (merged as unknown as Record<string, unknown>)[field] = (prev as unknown as Record<string, unknown>)[field];
    }
  }
  if (prev && (prev.body !== merged.body || prev.translation !== merged.translation)) wordHelp.reset();
  state.messages.set(m.id, merged);
  return merged;
}

function upsertMessage(m: Partial<MessageDTO> & { id: string }, options: { snapshot?: boolean } = {}): void {
  if (!m?.id || (state.groupId && m.chatId && m.chatId !== state.groupId)) return;
  const merged = mergeMessage(m, options.snapshot) as MessageDTO;
  const box = $('#messages');
  const existing = box.querySelector(`.msg[data-id="${CSS.escape(m.id)}"]`);
  if (existing) {
    if (existing.querySelector('[aria-describedby="word-help"]')) wordHelp.close();
    const fresh = renderMessage(state.messages.get(m.id) as MessageDTO);
    existing.replaceWith(fresh);
  } else {
    box.appendChild(renderMessage(state.messages.get(m.id) as MessageDTO));
    box.scrollTop = box.scrollHeight;
  }
}

function renderGroups(groups: GroupInfo[]): void {
  const box = $('#groups');
  box.innerHTML = '';
  for (const g of groups) {
    const el = document.createElement('div');
    el.className = 'group' + (g.id === state.groupId ? ' active' : '');
    el.setAttribute('role', 'button');
    el.tabIndex = 0;
    el.textContent = g.name;
    el.onclick = () => { void selectGroup(g); };
    el.onkeydown = (e) => {
      if (e.key === 'Enter' || e.key === ' ') void selectGroup(g);
    };
    box.appendChild(el);
  }
}

export async function selectGroup(g: GroupInfo): Promise<void> {
  wordHelp.reset();
  for (const [key, token] of state.translating) {
    window.wa.cancelTranslation(key.split('\u0000')[1], token).catch(() => {});
  }
  if (state.groupId) state.drafts.set(state.groupId, ($('#compose-input') as HTMLInputElement).value);
  const version = ++state.selectionVersion;
  const historyToken = ++state.historySequence;
  state.groupId = g.id;
  state.messages.clear();
  state.translating.clear();
  state.operations.clear();
  state.inline.clear();
  ($('#compose-input') as HTMLInputElement).value = state.drafts.get(g.id) || '';
  ($('#compose button') as HTMLButtonElement).disabled = state.sending.has(g.id);
  state.history = { hasMore: false, cursor: null, loading: false };
  updateOlderButton();
  renderMessages();
  const empty = $('#chat-empty');
  empty.textContent = 'Loading messages…';
  empty.classList.remove('hidden');
  $('#chat-header').classList.remove('hidden');
  $('#compose').classList.remove('hidden');
  $('#chat-title').textContent = g.name;
  try {
    const groups = await window.wa.getGroups();
    if (!isCurrentSelection(version, g.id)) return;
    renderGroups(groups);
    const page = normalizePage(await getMessagesPage(g.id, 60));
    if (!isCurrentSelection(version, g.id) || historyToken !== state.historySequence) return;
    state.history = { ...page, loading: false };
    updateOlderButton();
    for (const m of page.messages) mergeMessage(m, true);
    renderMessages();
    empty.textContent = state.messages.size ? 'Pick a group' : 'No stored messages yet — keep WhatsApp linked while history syncs.';
    empty.classList.toggle('hidden', state.messages.size > 0);
  } catch (err) {
    if (!isCurrentSelection(version, g.id)) return;
    empty.textContent = 'Could not load messages.';
    showToast(String((err as Error | undefined)?.message || err));
  }
}

export async function loadOlderMessages(): Promise<void> {
  if (!state.groupId || state.history.loading || !state.history.hasMore || !state.history.cursor) return;
  const version = state.selectionVersion;
  const groupId = state.groupId;
  const before = state.history.cursor;
  state.history.loading = true;
  updateOlderButton();
  const box = $('#messages');
  try {
    const page = normalizePage(await getMessagesPage(groupId, 60, before));
    if (!isCurrentSelection(version, groupId)) return;
    const oldTop = box.scrollTop;
    const oldHeight = box.scrollHeight;
    for (const m of page.messages) mergeMessage(m, true);
    state.history = { ...page, loading: false };
    renderMessages({ scrollToBottom: false });
    box.scrollTop = Math.max(0, box.scrollHeight - oldHeight + oldTop);
  } catch (err) {
    if (isCurrentSelection(version, groupId)) showToast(String((err as Error | undefined)?.message || err));
  } finally {
    if (isCurrentSelection(version, groupId)) {
      state.history.loading = false;
      updateOlderButton();
    }
  }
}

function renderKnownWords(): void {
  const box = $('#known-words');
  box.innerHTML = '';
  $('#known-count').textContent = state.knownWords.size ? '(' + state.knownWords.size + ')' : '';
  for (const w of state.knownWords) {
    const chip = document.createElement('span');
    chip.className = 'chip';
    chip.textContent = w;
    chip.title = 'remove';
    chip.onclick = async () => {
      state.knownWords = new Set(await window.wa.removeKnownWord(w));
      renderKnownWords();
      renderMessages();
    };
    box.appendChild(chip);
  }
}

async function toggleWord(word: string): Promise<void> {
  const lower = word.toLowerCase();
  if (state.knownWords.has(lower)) {
    state.knownWords = new Set(await window.wa.removeKnownWord(word));
  } else {
    state.knownWords = new Set(await window.wa.addKnownWord(word));
  }
  renderKnownWords();
  renderMessages();
  // New known words apply to the next manual translation; existing results stay put.
}

function showToast(text: string): void {
  const t = $('#toast');
  t.textContent = text;
  t.classList.remove('hidden');
  setTimeout(() => t.classList.add('hidden'), 4000);
}

// ---------- events ----------

export async function runTranslation(m: MessageDTO, act: 'translate' | 'retranslate', comment = ''): Promise<void> {
  wordHelp.reset();
  const version = state.selectionVersion;
  const groupId = state.groupId;
  const key = translationKey(m);
  if (state.translating.has(key)) return;
  const uiToken = version + ':' + (++state.requestSequence);
  state.translating.set(key, uiToken);
  state.operations.set(key, uiToken);
  upsertMessage({ id: m.id, chatId: groupId || undefined, error: null });
  try {
    const withT = act === 'retranslate'
      ? await window.wa.retranslate(m.id, comment, uiToken)
      : await window.wa.translate(m.id, uiToken);
    if (!isCurrentSelection(version, groupId) || state.translating.get(key) !== uiToken) return;
    if (state.operations.get(key) !== uiToken) return;
    mergeMessage(withT);
    if (!withT.error) state.inline.delete(m.id);
    upsertMessage({ id: m.id, chatId: groupId || undefined });
    if (withT.error) showToast(withT.error);
    else if (withT.translation) showToast(act === 'retranslate' ? 'Translation refreshed.' : 'Translation complete.');
  } catch (err) {
    if (isCurrentSelection(version, groupId) && state.operations.get(key) === uiToken) {
      upsertMessage({ id: m.id, chatId: groupId || undefined, error: String((err as Error | undefined)?.message || err) });
      showToast(String((err as Error | undefined)?.message || err));
    }
  } finally {
    if (state.translating.get(key) === uiToken) state.translating.delete(key);
    if (isCurrentSelection(version, groupId)) upsertMessage({ id: m.id, chatId: groupId || undefined });
  }
}

export function startRetranslate(msgEl: HTMLElement, m: MessageDTO): void {
  if (state.inline.has(m.id)) return;
  const bubble = msgEl.querySelector('.msg-body') as HTMLElement;
  if (bubble.querySelector('.retranslate-box')) return;
  const version = state.selectionVersion;
  const groupId = state.groupId;
  const box = document.createElement('div');
  box.className = 'retranslate-box';
  const comment = document.createElement('textarea');
  comment.placeholder = 'Optional correction or tone request';
  comment.setAttribute('aria-label', 'Retranslation comment');
  const actions = document.createElement('div');
  actions.className = 'edit-actions';
  const submit = document.createElement('button');
  submit.type = 'button';
  submit.textContent = 'Retranslate';
  const cancel = document.createElement('button');
  cancel.type = 'button';
  cancel.textContent = 'Cancel';
  actions.append(submit, cancel);
  box.append(comment, actions);
  state.inline.set(m.id, { kind: 'retranslate', box });
  bubble.appendChild(box);
  comment.focus();
  submit.onclick = async () => {
    submit.disabled = true;
    await runTranslation(m, 'retranslate', comment.value.trim());
    submit.disabled = false;
  };
  cancel.onclick = () => { state.inline.delete(m.id); renderMessages({ scrollToBottom: false }); };
}

export function startReply(msgEl: HTMLElement, m: MessageDTO): void {
  if (state.inline.has(m.id)) return;
  const bubble = msgEl.querySelector('.msg-body') as HTMLElement;
  if (bubble.querySelector('.reply-box')) return;
  const version = state.selectionVersion;
  const groupId = state.groupId;
  const box = document.createElement('div');
  box.className = 'reply-box';
  const input = document.createElement('textarea');
  input.placeholder = 'Reply text (sent as typed)';
  input.setAttribute('aria-label', 'Reply text');
  const actions = document.createElement('div');
  actions.className = 'edit-actions';
  const submit = document.createElement('button');
  submit.type = 'button';
  submit.textContent = 'Send reply';
  const cancel = document.createElement('button');
  cancel.type = 'button';
  cancel.textContent = 'Cancel';
  actions.append(submit, cancel);
  box.append(input, actions);
  state.inline.set(m.id, { kind: 'reply', box });
  bubble.appendChild(box);
  input.focus();
  submit.onclick = async () => {
    const text = input.value.trim();
    if (!text) return;
    submit.disabled = true;
    try {
      const sent = await window.wa.reply(m.id, text);
      if (isCurrentSelection(version, groupId)) {
        state.inline.delete(m.id);
        box.remove();
        if (sent?.id) upsertMessage(sent);
      }
    } catch (err) {
      submit.disabled = false;
      if (isCurrentSelection(version, groupId)) showToast(String((err as Error | undefined)?.message || err));
    }
  };
  cancel.onclick = () => { state.inline.delete(m.id); renderMessages({ scrollToBottom: false }); };
}

$('#messages').addEventListener('click', async (e) => {
  const wordEl = (e.target as HTMLElement).closest('.word') as HTMLElement | null;
  if (wordEl) {
    if (e.pointerType === 'touch') { void wordHelp.open(wordEl); return; }
    await toggleWord(wordEl.dataset.word || '');
    return;
  }
  const btn = (e.target as HTMLElement).closest('button[data-act]') as HTMLButtonElement | null;
  if (!btn) return;
  const msgEl = btn.closest('.msg') as HTMLElement | null;
  const id = msgEl?.dataset.id || '';
  const m = state.messages.get(id);
  if (!m) return;
  const act = btn.dataset.act;

  if (act === 'translate') {
    await runTranslation(m, 'translate');
  } else if (act === 'retranslate') {
    startRetranslate(msgEl as HTMLElement, m);
  } else if (act === 'edit') {
    startEdit(msgEl as HTMLElement, m);
  } else if (act === 'reply') {
    startReply(msgEl as HTMLElement, m);
  }
});

$('#messages').addEventListener('keydown', (event) => {
  const el = (event.target as HTMLElement).closest('.word') as HTMLElement | null;
  if (!el) return;
  if (event.key === 'Enter') { event.preventDefault(); void wordHelp.open(el); }
  if (event.key === ' ') { event.preventDefault(); void toggleWord(el.dataset.word || ''); }
});

export function startEdit(msgEl: HTMLElement, m: MessageDTO): void {
  wordHelp.reset();
  if (state.inline.has(m.id)) return;
  const bubble = msgEl.querySelector('.msg-body') as HTMLElement;
  const transEl = bubble.querySelector('.translation') as HTMLElement | null;
  if (!transEl || bubble.querySelector('.edit-box')) return;
  const version = state.selectionVersion;
  const groupId = state.groupId;
  const editor = document.createElement('textarea');
  editor.className = 'edit-box';
  editor.value = m.translation || '';
  const actions = document.createElement('div');
  actions.className = 'edit-actions';
  const save = document.createElement('button');
  save.textContent = 'Save';
  const cancel = document.createElement('button');
  cancel.textContent = 'Cancel';
  actions.append(save, cancel);
  const box = document.createElement('div');
  box.append(editor, actions);
  state.inline.set(m.id, { kind: 'edit', box });
  transEl.replaceWith(box);

  save.onclick = async () => {
    save.disabled = true;
    const key = translationKey(m);
    const token = ++state.requestSequence;
    state.operations.set(key, token);
    try {
      const res = await window.wa.editTranslation(m.id, editor.value);
      if (isCurrentSelection(version, groupId) && state.operations.get(key) === token && state.messages.has(m.id)) {
        state.inline.delete(m.id);
        mergeMessage({ ...res, id: m.id, chatId: m.chatId, error: null });        upsertMessage({ id: m.id, chatId: m.chatId });
      }
    } catch (err) {
      save.disabled = false;
      if (isCurrentSelection(version, groupId)) showToast(String((err as Error | undefined)?.message || err));
    }
  };
  cancel.onclick = () => {
    state.operations.delete(translationKey(m));
    state.inline.delete(m.id);
    renderMessages({ scrollToBottom: false });
  };
}

$('#compose').addEventListener('submit', async (e) => {
  e.preventDefault();
  const input = $('#compose-input') as HTMLInputElement;
  const text = input.value.trim();
  const groupId = state.groupId;
  const version = state.selectionVersion;
  if (!text || !groupId || state.sending.has(groupId)) return;
  state.sending.add(groupId);
  ($('#compose button') as HTMLButtonElement).disabled = true;
  const draft = input.value;
  state.drafts.set(groupId, draft);
  try {
    const sent = await window.wa.send(groupId, text); // sent as typed — no translation
    // Do not erase a newer draft entered while the request was in flight.
    if (isCurrentSelection(version, groupId)) {
      if (sent?.id) upsertMessage(sent);
      if (input.value === draft) { input.value = ''; state.drafts.delete(groupId); }
    } else if (state.groupId !== groupId && state.drafts.get(groupId) === draft) state.drafts.delete(groupId);
  } catch (err) {
    showToast(String((err as Error | undefined)?.message || err));
  } finally {
    state.sending.delete(groupId);
    if (state.groupId === groupId) ($('#compose button') as HTMLButtonElement).disabled = false;
  }
});

$('#load-older').addEventListener('click', () => { void loadOlderMessages(); });

$('#export-btn').addEventListener('click', async () => {
  const res = await window.wa.exportLearning();
  showToast('Exported ' + res.sentences + ' sentences, ' + res.words + ' words → ' + res.file);
});

window.wa.on('wa:qr', (qrDataUrl) => {
  ($('#qr-img') as HTMLImageElement).src = qrDataUrl as string;
  $('#qr-overlay').classList.remove('hidden');
});

window.wa.on('wa:ready', async () => {
  $('#qr-overlay').classList.add('hidden');
  const groups = await window.wa.getGroups();
  renderGroups(groups);
});

window.wa.on('wa:groups', (groups) => renderGroups(groups as GroupInfo[]));

window.wa.on('wa:message', (m) => {
  const dto = m as MessageDTO;
  if (state.groupId && dto.chatId === state.groupId) {
    if (dto.body && !state.messages.has(dto.id)) wordHelp.reset();
    upsertMessage(dto, { snapshot: true });
    $('#chat-empty').classList.add('hidden');
  }
});

window.wa.on('wa:translation', (m) => {
  const dto = m as MessageDTO;
  const key = translationKey(dto);
  if (
    state.groupId &&
    dto.chatId === state.groupId &&
    state.messages.has(dto.id) &&
    state.translating.get(key) === dto.uiToken
    && state.operations.get(key) === dto.uiToken
  ) {
    mergeMessage(dto);
    upsertMessage({ id: dto.id, chatId: dto.chatId } as MessageDTO);
  }
});

window.wa.on('wa:history', async (info) => {
  const groupId = state.groupId;
  const version = state.selectionVersion;
  const historyInfo = info as { complete?: boolean; groupIds?: string[] };
  if (!groupId || (!historyInfo.complete && !historyInfo.groupIds?.includes(groupId))) return;
  const historyToken = ++state.historySequence;
  try {
    const page = normalizePage(await getMessagesPage(groupId, 60));
    if (!isCurrentSelection(version, groupId) || historyToken !== state.historySequence) return;
    for (const m of page.messages) mergeMessage(m, true);
    // Keep a cursor for already loaded older pages. A history refresh only
    // appends newer records and must not make the older cursor jump forward.
    if (!state.history.cursor) state.history = { ...page, loading: false };
    else state.history.hasMore = state.history.hasMore || page.hasMore;
    updateOlderButton();
    renderMessages();
    $('#chat-empty').textContent = state.messages.size ? 'Pick a group' : 'No messages yet.';
    $('#chat-empty').classList.toggle('hidden', state.messages.size > 0);
  } catch (err) {
    if (isCurrentSelection(version, groupId)) showToast(String((err as Error | undefined)?.message || err));
  }
});

// ---------- boot ----------

(async function boot(): Promise<void> {
  state.knownWords = new Set(await window.wa.knownWords());
  renderKnownWords();
  const st = await window.wa.getState();
  if (st.ready) {
    renderGroups(await window.wa.getGroups());
  }
})();

// The mocked-Electron smoke drives these names from the window scope, exactly
// as they were script globals before bundling. getMessagesPage stays a live
// call-through so a smoke-side swap is honored by internal callers.
(globalThis as Record<string, unknown>).$ = $;
(globalThis as Record<string, unknown>).state = state;
(globalThis as Record<string, unknown>).getMessagesPage = defaultGetMessagesPage;
(globalThis as Record<string, unknown>).selectGroup = selectGroup;
(globalThis as Record<string, unknown>).loadOlderMessages = loadOlderMessages;
(globalThis as Record<string, unknown>).runTranslation = runTranslation;
(globalThis as Record<string, unknown>).renderMessages = renderMessages;
(globalThis as Record<string, unknown>).startEdit = startEdit;
(globalThis as Record<string, unknown>).startRetranslate = startRetranslate;
(globalThis as Record<string, unknown>).startReply = startReply;