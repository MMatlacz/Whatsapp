/* Application-owned adapter for the pinned WA-JS public API. No raw stores cross the bridge. */
(() => {
    'use strict';
    const createAdapter = (wpp) => {
        const id = (value) => {
            if (typeof value === 'string') return value;
            const serialized = value?._serialized;
            return typeof serialized === 'string' ? serialized : null;
        };
        const requiredID = (value) => {
            const result = id(value);
            if (!result || !result.trim()) throw new Error('missing-runtime-identifier');
            return result;
        };
        const read = (value, property) => {
            try { return value?.[property]; } catch { return undefined; }
        };
        const text = (value) => typeof value === 'string' ? value : null;
        const nonnegativeInteger = (value) => Number.isSafeInteger(value) && value >= 0 ? value : null;
        const mediaKinds = { image: 'image', video: 'video', audio: 'audio', ptt: 'audio',
            document: 'document', sticker: 'sticker' };
        const deliveryState = (ack) => {
            if (!Number.isInteger(ack)) return null;
            if (ack < 0) return 'failed';
            if (ack === 0) return 'pending';
            if (ack === 1) return 'sent';
            if (ack === 2) return 'delivered';
            if (ack === 3) return 'read';
            if (ack >= 4) return 'played';
            return null;
        };
        const body = (raw) => read(raw, 'isViewOnce') ? null
            : mediaKinds[read(raw, 'type')] ? text(read(raw, 'caption')) : text(read(raw, 'body'));
        const timestampMilliseconds = (seconds) => {
            if (!Number.isFinite(seconds) || seconds < 0) throw new Error('invalid-message-time');
            const milliseconds = Math.trunc(seconds * 1000);
            if (!Number.isSafeInteger(milliseconds)) throw new Error('invalid-message-time');
            return milliseconds;
        };
        const rawMessageChatID = (raw) => id(read(read(raw, 'id'), 'remote'))
            || id(read(raw, 'chatId')) || id(read(raw, 'chatID'))
            || (read(read(raw, 'id'), 'fromMe') ? id(read(raw, 'to')) : id(read(raw, 'from')));
        const chatAliasCache = new Map();
        const chatAliases = async (chatID) => {
            if (chatAliasCache.has(chatID)) return chatAliasCache.get(chatID);
            const pending = (async () => {
                const aliases = new Set([chatID]);
                const resolve = wpp.contact?.getPnLidEntry;
                if (typeof resolve !== 'function') return aliases;
                try {
                    const entry = await resolve(chatID);
                    for (const key of ['lid', 'phoneNumber']) {
                        const alias = id(entry?.[key]);
                        if (alias) aliases.add(alias);
                    }
                } catch { /* Some broadcast/group IDs have no phone/LID mapping. */ }
                return aliases;
            })();
            chatAliasCache.set(chatID, pending);
            if (chatAliasCache.size > 256) chatAliasCache.delete(chatAliasCache.keys().next().value);
            return pending;
        };
        const equivalentChatID = async (actual, expected) => {
            if (!actual || !expected) return false;
            if (actual === expected) return true;
            const [actualAliases, expectedAliases] = await Promise.all([
                chatAliases(actual), chatAliases(expected)
            ]);
            for (const alias of actualAliases) if (expectedAliases.has(alias)) return true;
            return false;
        };
        const message = (raw) => {
            const key = read(raw, 'id');
            const fromMe = read(key, 'fromMe');
            if (typeof fromMe !== 'boolean') throw new Error('invalid-message-direction');
            // WA-JS exposes quotedMsg as a throwing getter when a message has
            // no reply. Read it defensively so ordinary messages still cross
            // the bridge and only an actual quote is mapped.
            const quoted = read(raw, 'quotedMsg');
            const quoteID = id(read(raw, 'quotedMsgId')) || id(read(raw, 'quotedMsgKey')) || id(read(quoted, 'id'));
            const kind = mediaKinds[read(raw, 'type')];
            return {
                id: requiredID(key), chatID: requiredID(rawMessageChatID(raw)),
                senderID: id(read(raw, 'author')) || id(read(raw, 'from')) || null,
                timestampMilliseconds: timestampMilliseconds(read(raw, 't')),
                body: body(raw), fromMe,
                deliveryState: deliveryState(read(raw, 'ack')),
                quote: quoteID ? { messageID: quoteID,
                    senderID: id(read(raw, 'quotedParticipant')) || id(read(quoted, 'author')) || null,
                    body: quoted ? body(quoted) : null } : null,
                media: kind ? { kind, mimeType: text(read(raw, 'mimetype')),
                    filename: read(raw, 'isViewOnce') ? null : text(read(raw, 'filename')),
                    sizeBytes: nonnegativeInteger(read(raw, 'size')),
                    durationMilliseconds: nonnegativeInteger(
                        Number.isFinite(read(raw, 'duration')) ? Math.trunc(read(raw, 'duration') * 1000) : null),
                    width: nonnegativeInteger(read(raw, 'width')), height: nonnegativeInteger(read(raw, 'height')) } : null
            };
        };
        const chat = (raw, unreadCount) => {
            const chatID = requiredID(read(raw, 'id'));
            const title = text(read(raw, 'formattedTitle')) || text(read(raw, 'name')) || 'Chat';
            const count = unreadCount === undefined ? read(raw, 'unreadCount') : unreadCount;
            return {
            id: chatID, title,
            isGroup: chatID.endsWith('@g.us'),
            unreadCount: Math.max(0, Number.isInteger(count) ? count : 0),
            lastMessageTimestampMilliseconds: Number.isFinite(read(raw, 't')) && read(raw, 't') >= 0
                ? timestampMilliseconds(read(raw, 't')) : null
            };
        };
        const state = () => {
            if (!wpp?.isReady) return 'connecting';
            if (!wpp.conn.isAuthenticated()) {
                return wpp.conn.isRegistered() ? 'connecting' : 'authenticating';
            }
            if (!wpp.conn.isMainReady()) return 'syncing';
            return wpp.conn.isOnline() ? 'ready' : 'disconnected';
        };
        const requireReady = () => {
            if (state() !== 'ready') throw new Error('transport-not-ready');
        };
        const confirmSentMessage = async (result, chatID) => {
            const messageID = requiredID(result?.id);
            // waitForAck waits for SENT, but retain a bounded read-after-write window
            // because the message model can become visible a tick later. This never
            // retries the send itself and therefore cannot duplicate an uncertain send.
            for (let attempt = 0; attempt < 4; attempt += 1) {
                let raw;
                try {
                    raw = await wpp.chat.getMessageById(messageID);
                } catch (error) {
                    if (attempt === 3) throw error;
                }
                if (raw) {
                    const actualChatID = rawMessageChatID(raw);
                    if (!await equivalentChatID(actualChatID, chatID)) {
                        throw new Error('unexpected-send-result');
                    }
                    const accepted = message(raw);
                    accepted.chatID = chatID;
                    if (!accepted.deliveryState) accepted.deliveryState = deliveryState(read(result, 'ack'));
                    if (!accepted.fromMe) throw new Error('unexpected-send-result');
                    return accepted;
                }
                if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, 50 * (attempt + 1)));
            }
            throw new Error('send-confirmation-unavailable');
        };
        const send = async ({ chatID, text, messageID }) => {
            requireReady();
            if (!text?.trim()) throw new Error('empty-message');
            // Do not create contacts, generate link previews, mention people or mark chats read implicitly.
            const result = await wpp.chat.sendTextMessage(chatID, text, {
                createChat: false, detectMentioned: false, markIsRead: false,
                linkPreview: false, waitForAck: true,
                ...(messageID ? { quotedMsg: messageID } : {})
            });
            if (result?.ack !== undefined && (!Number.isInteger(result.ack) || result.ack < 1)) {
                throw new Error('send-not-accepted');
            }
            return confirmSentMessage(result, chatID);
        };
        return {
            connectionState: async () => state(),
            listChats: async () => {
                requireReady();
                return (await wpp.chat.list()).map((raw) => chat(raw));
            },
            loadMessages: async ({ chatID, cursor, limit }) => {
                requireReady();
                if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('invalid-limit');
                if (cursor && !cursor.beforeMessageID) throw new Error('unsupported-timestamp-cursor');
                const rows = await wpp.chat.getMessages(chatID, {
                    count: limit, direction: 'before', ...(cursor ? { id: cursor.beforeMessageID } : {})
                });
                const messages = (await Promise.all(rows.map(async (raw) => {
                    const actualChatID = rawMessageChatID(raw);
                    if (!await equivalentChatID(actualChatID, chatID)) throw new Error('cross-chat-history');
                    const mapped = message(raw);
                    // WhatsApp can expose the same one-to-one thread through
                    // both its phone-number and LID WIDs. Keep the requested
                    // native chat ID stable after the public mapping check.
                    mapped.chatID = chatID;
                    return mapped;
                }))).sort((a, b) =>
                    a.timestampMilliseconds - b.timestampMilliseconds || a.id.localeCompare(b.id));
                const first = messages[0];
                return { messages, nextCursor: messages.length === limit && first ? {
                    beforeMessageID: first.id, beforeTimestampMilliseconds: first.timestampMilliseconds
                } : null };
            },
            sendText: send,
            reply: send,
            subscribe: (emit) => {
                const listeners = [];
                const on = (name, callback, { fatal = true } = {}) => {
                    const safe = (value) => {
                        try {
                            const result = callback(value);
                            if (result && typeof result.catch === 'function') {
                                result.catch(() => {
                                    if (fatal) emit({ kind: 'disconnected', payload: { reason: 'runtime-event-invalid' } });
                                });
                            }
                        } catch {
                            if (fatal) emit({ kind: 'disconnected', payload: { reason: 'runtime-event-invalid' } });
                        }
                    };
                    wpp.on(name, safe);
                    listeners.push([name, safe]);
                };
                // Individual message rows can briefly be incomplete while
                // WhatsApp hydrates them. Drop that row and keep the session
                // alive; a later history read reconciles it.
                on('chat.new_message', (raw) => emit({ kind: 'message', payload: message(raw) }), { fatal: false });
                on('chat.msg_edited', (event) => {
                    const updated = message(event.msg);
                    if (updated.chatID !== requiredID(event.chat)) throw new Error('cross-chat-edit');
                    emit({ kind: 'messageUpdate', payload: updated });
                });
                on('chat.new_chat', (raw) => emit({ kind: 'chatUpdate', payload: chat(raw) }), { fatal: false });
                on('chat.unread_count_changed', (event) => {
                    if (!event || typeof event !== 'object') throw new Error('invalid-unread-event');
                    const unreadCount = event.unreadCount;
                    if (!Number.isSafeInteger(unreadCount) || unreadCount < 0) throw new Error('invalid-unread-count');
                    emit({ kind: 'chatUpdate', payload: chat(event.chat, unreadCount) });
                }, { fatal: false });
                on('chat.msg_ack_change', async (event) => {
                    if (!event || typeof event !== 'object') throw new Error('invalid-ack-event');
                    const ack = event.ack;
                    const chatID = requiredID(event.chat);
                    const ids = Array.isArray(event.ids) ? event.ids : [];
                    if (!Number.isInteger(ack) || ack < -7 || ack > 5 || ids.length > 100) {
                        throw new Error('invalid-ack-event');
                    }
                    await Promise.allSettled(ids.map(async (key) => {
                        const raw = await wpp.chat.getMessageById(key);
                        if (!raw) return;
                        const actualChatID = rawMessageChatID(raw);
                        if (!await equivalentChatID(actualChatID, chatID)) return;
                        const updated = message(raw);
                        updated.chatID = chatID;
                        updated.deliveryState = deliveryState(ack);
                        emit({ kind: 'messageUpdate', payload: updated });
                    }));
                }, { fatal: false });
                const emitReadyIfUsable = () => {
                    if (state() === 'ready') emit({ kind: 'ready', payload: {} });
                };
                on('conn.main_ready', emitReadyIfUsable);
                on('conn.authenticated', emitReadyIfUsable);
                on('conn.online', (online) => {
                    if (online) emitReadyIfUsable();
                    else emit({ kind: 'disconnected', payload: { reason: 'offline' } });
                });
                on('conn.require_auth', () => emit({ kind: 'disconnected', payload: { reason: 'authentication-required' } }));
                on('conn.logout', () => emit({ kind: 'disconnected', payload: { reason: 'logged-out' } }));
                on('conn.needs_update', () => emit({ kind: 'disconnected', payload: { reason: 'update-required' } }));
                return () => listeners.forEach(([name, callback]) => wpp.off(name, callback));
            }
        };
    };
    if (typeof module !== 'undefined' && module.exports) module.exports = { createAdapter };
    else if (globalThis.WPP) globalThis.__waTranslatorRuntimeAdapter = createAdapter(globalThis.WPP);
})();
