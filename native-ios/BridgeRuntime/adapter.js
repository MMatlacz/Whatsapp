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
        const boundedText = (value, maxLength) => {
            const result = text(value)?.trim();
            return result && result.length <= maxLength ? result : null;
        };
        const safeHTTPURL = (value) => {
            const raw = boundedText(value, 4096);
            if (!raw) return null;
            try {
                const parsed = new URL(raw);
                return parsed.protocol === 'https:' || parsed.protocol === 'http:' ? parsed.href : null;
            } catch { return null; }
        };
        const linkPreview = (raw) => {
            const preview = read(raw, 'linkPreview');
            const rawBody = body(raw);
            const bodyURL = typeof rawBody === 'string'
                ? rawBody.match(/https?:\/\/[^\s<>]+/i)?.[0] || null
                : null;
            const matchedText = boundedText(read(preview, 'matchedText'), 4096)
                || boundedText(read(raw, 'matchedText'), 4096)
                || safeHTTPURL(bodyURL);
            if (!matchedText) return null;
            return {
                matchedText,
                canonicalURL: safeHTTPURL(read(preview, 'canonicalUrl'))
                    || safeHTTPURL(read(raw, 'canonicalUrl'))
                    || safeHTTPURL(matchedText),
                title: boundedText(read(preview, 'title'), 512) || boundedText(read(raw, 'title'), 512),
                description: boundedText(read(preview, 'description'), 2048)
                    || boundedText(read(raw, 'description'), 2048)
            };
        };
        const semanticText = (value, maxLength, field, { required = false } = {}) => {
            if (value === null || value === undefined) {
                if (required) throw new Error(`missing-${field}`);
                return null;
            }
            if (typeof value !== 'string') throw new Error(`invalid-${field}`);
            const result = value.trim();
            if (result.length > maxLength || (required && result.length === 0)) {
                throw new Error(`invalid-${field}`);
            }
            return result || null;
        };
        const semanticType = (raw) => semanticText(read(raw, 'type'), 64, 'message-type')
            || (typeof read(raw, 'body') === 'string' ? 'chat' : 'unknown');
        const firstFinite = (...values) => values.find((value) => Number.isFinite(value));
        const semanticLocation = (raw) => {
            const nested = read(raw, 'location');
            const latitude = firstFinite(read(raw, 'lat'), read(raw, 'latitude'), read(nested, 'lat'), read(nested, 'latitude'));
            const longitude = firstFinite(read(raw, 'lng'), read(raw, 'longitude'), read(nested, 'lng'), read(nested, 'longitude'));
            if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
                !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
                throw new Error('invalid-location');
            }
            return {
                latitude, longitude,
                name: semanticText(read(raw, 'loc') ?? read(raw, 'name') ?? read(nested, 'name'), 512, 'location-name'),
                address: semanticText(read(raw, 'address') ?? read(nested, 'address'), 1024, 'location-address')
            };
        };
        const semanticContacts = (raw) => {
            const list = read(raw, 'vCards') ?? read(raw, 'vcards') ?? read(raw, 'vcardList');
            const values = Array.isArray(list) ? list : [read(raw, 'vcard') ?? read(raw, 'body')];
            if (values.length < 1 || values.length > 8) throw new Error('invalid-contact-count');
            return values.map((value) => {
                const objectValue = value && typeof value === 'object' ? value : null;
                const vCard = semanticText(
                    objectValue ? (read(objectValue, 'vCard') ?? read(objectValue, 'vcard') ?? read(objectValue, 'body')) : value,
                    4096, 'contact-vcard', { required: true }
                );
                const displayName = semanticText(
                    objectValue ? (read(objectValue, 'displayName') ?? read(objectValue, 'name')) : read(raw, 'formattedTitle'),
                    256, 'contact-name'
                );
                return { displayName, vCard };
            });
        };
        const semanticPoll = (raw) => {
            const question = semanticText(
                read(raw, 'pollName') ?? read(raw, 'pollQuestion') ?? read(raw, 'body'),
                2048, 'poll-question', { required: true }
            );
            const rawOptions = read(raw, 'pollOptions') ?? read(raw, 'options');
            if (!Array.isArray(rawOptions) || rawOptions.length < 1 || rawOptions.length > 20) {
                throw new Error('invalid-poll-options');
            }
            const options = rawOptions.map((option) => semanticText(
                typeof option === 'string' ? option : (read(option, 'name') ?? read(option, 'text') ?? read(option, 'body')),
                512, 'poll-option', { required: true }
            ));
            return { question, options };
        };
        const revokedTypes = new Set(['revoked', 'deleted']);
        const systemTypes = new Set(['notification', 'gp2', 'e2e_notification', 'call_log', 'protocol']);
        const contactTypes = new Set(['vcard', 'multi_vcard', 'contact_card']);
        const pollTypes = new Set(['poll', 'poll_creation']);
        const locationTypes = new Set(['location', 'live_location']);
        const semanticContent = (raw, preview) => {
            const rawType = semanticType(raw);
            if (mediaKinds[rawType]) return { kind: 'media' };
            if ((rawType === 'chat' || rawType === 'text') && preview) return { kind: 'linkPreview' };
            if (rawType === 'chat' || rawType === 'text') return { kind: 'text' };
            if (locationTypes.has(rawType)) return { kind: 'location', location: semanticLocation(raw) };
            if (contactTypes.has(rawType)) return { kind: 'contact', contacts: semanticContacts(raw) };
            if (pollTypes.has(rawType)) return { kind: 'poll', poll: semanticPoll(raw) };
            if (revokedTypes.has(rawType) || (rawType === 'protocol' && read(raw, 'isRevoked') === true)) {
                return { kind: 'revoked' };
            }
            if (systemTypes.has(rawType)) {
                return { kind: 'system', system: {
                    type: semanticText(rawType, 128, 'system-type', { required: true }),
                    text: semanticText(read(raw, 'body'), 2048, 'system-text')
                } };
            }
            return { kind: 'unsupported', rawType };
        };
        const inlineThumbnail = (value) => {
            const encoded = text(value);
            if (!encoded || encoded.length > 2_000_000) return null;
            const dataMatch = encoded.match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=\r\n]+)$/i);
            if (dataMatch) return { mimeType: dataMatch[1].toLowerCase(), data: dataMatch[2].replace(/\s/g, '') };
            const compact = encoded.replace(/\s/g, '');
            return /^[A-Za-z0-9+/]+={0,2}$/.test(compact) ? { mimeType: 'image/jpeg', data: compact } : null;
        };
        const blobToBase64 = async (blob) => {
            if (typeof FileReader !== 'function') throw new Error('preview-file-reader-unavailable');
            const dataURL = await new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = () => resolve(reader.result);
                reader.onerror = () => reject(reader.error || new Error('preview-read-failed'));
                reader.readAsDataURL(blob);
            });
            const result = inlineThumbnail(dataURL);
            if (!result) throw new Error('preview-encoding-failed');
            return result;
        };
        const downsampleImage = async (blob, maxPixelSize, preferredMimeType) => {
            if (!(blob instanceof Blob) || blob.size <= 0 || blob.size > 12 * 1024 * 1024) {
                throw new Error('preview-source-too-large');
            }
            if (typeof createImageBitmap !== 'function' || typeof document?.createElement !== 'function') {
                if (blob.size > 1_500_000 || !/^image\/(jpeg|png|webp)$/.test(blob.type)) {
                    throw new Error('preview-downsample-unavailable');
                }
                const encoded = await blobToBase64(blob);
                return { ...encoded, width: null, height: null };
            }
            const bitmap = await createImageBitmap(blob);
            try {
                const maximum = Math.max(bitmap.width, bitmap.height);
                if (!Number.isFinite(maximum) || maximum <= 0) throw new Error('preview-invalid-dimensions');
                const scale = Math.min(1, maxPixelSize / maximum);
                const width = Math.max(1, Math.round(bitmap.width * scale));
                const height = Math.max(1, Math.round(bitmap.height * scale));
                const canvas = document.createElement('canvas');
                canvas.width = width;
                canvas.height = height;
                const context = canvas.getContext('2d');
                if (!context) throw new Error('preview-canvas-unavailable');
                context.drawImage(bitmap, 0, 0, width, height);
                const output = await new Promise((resolve) =>
                    canvas.toBlob(resolve, preferredMimeType, preferredMimeType === 'image/jpeg' ? 0.82 : 0.88));
                if (!output || output.size <= 0 || output.size > 1_500_000) throw new Error('preview-output-too-large');
                const encoded = await blobToBase64(output);
                return { ...encoded, width, height };
            } finally {
                if (typeof bitmap.close === 'function') bitmap.close();
            }
        };
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
        const chatAliasInFlight = new Map();
        const CHAT_ALIAS_TTL_MS = 10 * 60 * 1000;
        const aliasKind = (chatID) => chatID?.endsWith('@c.us') ? 'phone'
            : chatID?.endsWith('@lid') ? 'lid' : 'other';
        const chatAliases = async (chatID) => {
            const now = Date.now();
            const cached = chatAliasCache.get(chatID);
            if (cached?.expiresAt > now) return { status: 'resolved', aliases: cached.aliases };
            if (cached) chatAliasCache.delete(chatID);
            if (chatAliasInFlight.has(chatID)) return chatAliasInFlight.get(chatID);

            const pending = (async () => {
                const aliases = new Set([chatID]);
                const resolve = wpp.contact?.getPnLidEntry;
                if (typeof resolve !== 'function') {
                    return { status: 'unknown', aliases, reason: 'alias-resolver-unavailable' };
                }
                try {
                    const entry = await resolve(chatID);
                    for (const key of ['lid', 'phoneNumber']) {
                        const alias = id(entry?.[key]);
                        if (alias) aliases.add(alias);
                    }
                    chatAliasCache.set(chatID, {
                        aliases,
                        expiresAt: Date.now() + CHAT_ALIAS_TTL_MS
                    });
                    if (chatAliasCache.size > 256) chatAliasCache.delete(chatAliasCache.keys().next().value);
                    return { status: 'resolved', aliases };
                } catch {
                    return { status: 'unknown', aliases, reason: 'alias-resolution-failed' };
                }
            })().finally(() => {
                chatAliasInFlight.delete(chatID);
            });
            chatAliasInFlight.set(chatID, pending);
            return pending;
        };
        const equivalentChatID = async (actual, expected) => {
            if (!actual || !expected) return { status: 'unknown', reason: 'missing-chat-identifier' };
            if (actual === expected) return { status: 'equal' };
            const actualKind = aliasKind(actual);
            const expectedKind = aliasKind(expected);
            if (actualKind === expectedKind || actualKind === 'other' || expectedKind === 'other') {
                return { status: 'different' };
            }
            const [actualResolution, expectedResolution] = await Promise.all([
                chatAliases(actual), chatAliases(expected)
            ]);
            for (const alias of actualResolution.aliases) {
                if (expectedResolution.aliases.has(alias)) return { status: 'equal' };
            }
            if (actualResolution.status === 'resolved' && expectedResolution.status === 'resolved') {
                return { status: 'different' };
            }
            return {
                status: 'unknown',
                reason: actualResolution.reason || expectedResolution.reason || 'alias-resolution-incomplete'
            };
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
            const quotedType = quoted ? semanticType(quoted) : null;
            const quotedBody = quoted && (mediaKinds[quotedType] || quotedType === 'chat' || quotedType === 'text')
                ? body(quoted) : null;
            const kind = mediaKinds[read(raw, 'type')];
            const preview = linkPreview(raw);
            const content = semanticContent(raw, preview);
            const mappedBody = ['text', 'media', 'linkPreview'].includes(content.kind) ? body(raw) : null;
            return {
                id: requiredID(key), chatID: requiredID(rawMessageChatID(raw)),
                senderID: id(read(raw, 'author')) || id(read(raw, 'from')) || null,
                timestampMilliseconds: timestampMilliseconds(read(raw, 't')),
                body: mappedBody, fromMe,
                deliveryState: deliveryState(read(raw, 'ack')),
                quote: quoteID ? { messageID: quoteID,
                    senderID: id(read(raw, 'quotedParticipant')) || id(read(quoted, 'author')) || null,
                    body: quotedBody } : null,
                media: kind ? { kind, mimeType: text(read(raw, 'mimetype')),
                    filename: read(raw, 'isViewOnce') ? null : text(read(raw, 'filename')),
                    sizeBytes: nonnegativeInteger(read(raw, 'size')),
                    durationMilliseconds: nonnegativeInteger(
                        Number.isFinite(read(raw, 'duration')) ? Math.trunc(read(raw, 'duration') * 1000) : null),
                    width: nonnegativeInteger(read(raw, 'width')), height: nonnegativeInteger(read(raw, 'height')),
                    isViewOnce: Boolean(read(raw, 'isViewOnce')) } : null,
                linkPreview: preview,
                content
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
                    const identity = await equivalentChatID(actualChatID, chatID);
                    if (identity.status !== 'equal') {
                        throw new Error(identity.status === 'unknown' ? 'chat-identity-unresolved' : 'unexpected-send-result');
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
        const mediaPreview = async ({ chatID, messageID, purpose, maxPixelSize }) => {
            requireReady();
            if (!Number.isInteger(maxPixelSize) || maxPixelSize < 64 || maxPixelSize > 1280) {
                throw new Error('invalid-preview-size');
            }
            if (purpose !== 'attachment' && purpose !== 'linkPreview') {
                throw new Error('invalid-preview-purpose');
            }
            const raw = await wpp.chat.getMessageById(messageID);
            if (!raw) throw new Error('preview-message-not-found');
            const actualChatID = rawMessageChatID(raw);
            const identity = await equivalentChatID(actualChatID, chatID);
            if (identity.status !== 'equal') {
                throw new Error(identity.status === 'unknown' ? 'chat-identity-unresolved' : 'cross-chat-media');
            }
            if (read(raw, 'isViewOnce') === true) throw new Error('view-once-media');

            if (purpose === 'linkPreview') {
                const preview = read(raw, 'linkPreview');
                const inline = inlineThumbnail(read(preview, 'thumbnail'));
                if (!inline) throw new Error('preview-unavailable');
                return { ...inline, width: null, height: null };
            }

            const kind = mediaKinds[read(raw, 'type')];
            const inline = inlineThumbnail(read(raw, 'thumbnailHQ'))
                || inlineThumbnail(read(raw, 'thumbnail'));
            if (inline) {
                return {
                    ...inline,
                    width: nonnegativeInteger(read(raw, 'thumbnailWidth')),
                    height: nonnegativeInteger(read(raw, 'thumbnailHeight'))
                };
            }

            // Conversation thumbnails must never trigger full video/audio/document downloads.
            if (kind !== 'image' && kind !== 'sticker') throw new Error('preview-unavailable');
            const blob = await wpp.chat.downloadMedia(messageID);
            return downsampleImage(blob, maxPixelSize, kind === 'sticker' ? 'image/webp' : 'image/jpeg');
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
                const rawBoundary = rows.reduce((oldest, raw) => {
                    const rawID = id(read(raw, 'id'));
                    const seconds = read(raw, 't');
                    if (!rawID || !Number.isFinite(seconds) || seconds < 0) return oldest;
                    let timestamp;
                    try { timestamp = timestampMilliseconds(seconds); } catch { return oldest; }
                    if (!oldest || timestamp < oldest.timestampMilliseconds ||
                        (timestamp === oldest.timestampMilliseconds && rawID.localeCompare(oldest.id) < 0)) {
                        return { id: rawID, timestampMilliseconds: timestamp };
                    }
                    return oldest;
                }, null);
                const mappedRows = await Promise.all(rows.map(async (raw) => {
                    try {
                        const actualChatID = rawMessageChatID(raw);
                        if (!actualChatID) return { status: 'malformed', error: new Error('invalid-message-chat') };
                        const identity = await equivalentChatID(actualChatID, chatID);
                        if (identity.status === 'unknown') {
                            return { status: 'unresolved', reason: identity.reason || 'chat-identity-unresolved' };
                        }
                        if (identity.status === 'different') return { status: 'cross-chat' };
                        const mapped = message(raw);
                        // WhatsApp can expose the same one-to-one thread through
                        // both its phone-number and LID WIDs. Keep the requested
                        // native chat ID stable after the public mapping check.
                        mapped.chatID = chatID;
                        return { status: 'mapped', message: mapped };
                    } catch (error) {
                        return { status: 'malformed', error };
                    }
                }));
                const unresolvedRows = mappedRows.filter((row) => row.status === 'unresolved');
                if (unresolvedRows.length > 0) {
                    const error = new Error('chat-identity-unresolved');
                    error.code = 'chat-identity-unresolved';
                    error.reason = unresolvedRows[0].reason;
                    throw error;
                }
                const crossChatCount = mappedRows.filter((row) => row.status === 'cross-chat').length;
                if (rows.length > 0 && crossChatCount === rows.length) throw new Error('cross-chat-history');
                const messages = mappedRows.filter((row) => row.status === 'mapped')
                    .map((row) => row.message)
                    .sort((a, b) => a.timestampMilliseconds - b.timestampMilliseconds || a.id.localeCompare(b.id));
                const malformedRows = mappedRows.filter((row) => row.status === 'malformed');
                if (rows.length > 0 && messages.length === 0 && crossChatCount === 0 && !rawBoundary &&
                    malformedRows.length === rows.length) {
                    throw malformedRows[0].error || new Error('invalid-history-page');
                }
                return { messages, nextCursor: rows.length === limit && rawBoundary ? {
                    beforeMessageID: rawBoundary.id,
                    beforeTimestampMilliseconds: rawBoundary.timestampMilliseconds
                } : null };
            },
            sendText: send,
            reply: send,
            mediaPreview,
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
                        const identity = await equivalentChatID(actualChatID, chatID);
                        if (identity.status !== 'equal') return;
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
