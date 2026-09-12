/* Application-owned adapter for the pinned WA-JS public API. No raw stores cross the bridge. */
(() => {
    'use strict';
    const createAdapter = (wpp) => {
        const id = (value) => typeof value === 'string' ? value : value?._serialized;
        const requiredID = (value) => {
            const result = id(value);
            if (!result) throw new Error('missing-runtime-identifier');
            return result;
        };
        const message = (raw) => {
            const key = raw.id;
            if (typeof key?.fromMe !== 'boolean') throw new Error('invalid-message-direction');
            if (!Number.isFinite(raw.t) || raw.t < 0) throw new Error('invalid-message-time');
            return {
                id: requiredID(key), chatID: requiredID(key.remote),
                senderID: id(raw.author) || id(raw.from) || null,
                timestampMilliseconds: Math.trunc(raw.t * 1000),
                body: typeof raw.body === 'string' ? raw.body : (raw.caption ?? null),
                fromMe: key.fromMe, quote: null, media: null
            };
        };
        const chat = (raw) => ({
            id: requiredID(raw.id), title: raw.formattedTitle || raw.name || 'Chat',
            isGroup: requiredID(raw.id).endsWith('@g.us'),
            unreadCount: Math.max(0, Number.isInteger(raw.unreadCount) ? raw.unreadCount : 0),
            lastMessageTimestampMilliseconds: Number.isFinite(raw.t) ? Math.trunc(raw.t * 1000) : null
        });
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
        const send = async ({ chatID, text, messageID }) => {
            requireReady();
            if (!text?.trim()) throw new Error('empty-message');
            // Do not create contacts, generate link previews, mention people or mark chats read implicitly.
            const result = await wpp.chat.sendTextMessage(chatID, text, {
                createChat: false, detectMentioned: false, markIsRead: false,
                linkPreview: false, waitForAck: true,
                ...(messageID ? { quotedMsg: messageID } : {})
            });
            // A successful invocation alone is not a sent message. Resolve the accepted message by stable ID.
            const accepted = message(await wpp.chat.getMessageById(requiredID(result.id)));
            if (accepted.chatID !== chatID || !accepted.fromMe) throw new Error('unexpected-send-result');
            return accepted;
        };
        return {
            connectionState: async () => state(),
            listChats: async () => {
                requireReady();
                return (await wpp.chat.list()).map(chat);
            },
            loadMessages: async ({ chatID, cursor, limit }) => {
                requireReady();
                if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('invalid-limit');
                if (cursor && !cursor.beforeMessageID) throw new Error('unsupported-timestamp-cursor');
                const rows = await wpp.chat.getMessages(chatID, {
                    count: limit, direction: 'before', ...(cursor ? { id: cursor.beforeMessageID } : {})
                });
                const messages = rows.map(message).sort((a, b) =>
                    a.timestampMilliseconds - b.timestampMilliseconds || a.id.localeCompare(b.id));
                if (messages.some((row) => row.chatID !== chatID)) throw new Error('cross-chat-history');
                const first = messages[0];
                return { messages, nextCursor: messages.length === limit && first ? {
                    beforeMessageID: first.id, beforeTimestampMilliseconds: first.timestampMilliseconds
                } : null };
            },
            sendText: send,
            reply: send,
            subscribe: (emit) => {
                const listeners = [];
                const on = (name, callback) => {
                    const safe = (value) => {
                        try { callback(value); } catch {
                            emit({ kind: 'disconnected', payload: { reason: 'runtime-event-invalid' } });
                        }
                    };
                    wpp.on(name, safe);
                    listeners.push([name, safe]);
                };
                on('chat.new_message', (raw) => emit({ kind: 'message', payload: message(raw) }));
                on('chat.new_chat', (raw) => emit({ kind: 'chatUpdate', payload: chat(raw) }));
                const emitReadyIfUsable = () => {
                    if (state() === 'ready') emit({ kind: 'ready', payload: {} });
                };
                on('conn.main_ready', emitReadyIfUsable);
                on('conn.online', (online) => {
                    if (online) emitReadyIfUsable();
                    else emit({ kind: 'disconnected', payload: { reason: 'offline' } });
                });
                on('conn.require_auth', () => emit({ kind: 'disconnected', payload: { reason: 'authentication-required' } }));
                return () => listeners.forEach(([name, callback]) => wpp.off(name, callback));
            }
        };
    };
    if (typeof module !== 'undefined' && module.exports) module.exports = { createAdapter };
    else if (globalThis.WPP) globalThis.__waTranslatorRuntimeAdapter = createAdapter(globalThis.WPP);
})();
