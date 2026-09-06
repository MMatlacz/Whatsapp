(() => {
    'use strict';

    const BRIDGE_VERSION = 1;
    const MESSAGE_HANDLER = 'whatsAppBridge';
    const GLOBAL_BRIDGE = '__waTranslatorBridge';
    const GLOBAL_ADAPTER = '__waTranslatorRuntimeAdapter';
    const VALID_STATES = new Set(['disconnected', 'connecting', 'authenticating', 'syncing', 'ready']);
    const VALID_MEDIA_KINDS = new Set(['image', 'video', 'audio', 'document', 'sticker', 'other']);

    if (globalThis[GLOBAL_BRIDGE]?.version === BRIDGE_VERSION) {
        return;
    }

    class BridgeError extends Error {
        constructor(code, message) {
            super(message);
            this.code = code;
        }
    }

    const requireNonEmptyString = (value, field) => {
        if (typeof value !== 'string' || value.length === 0) {
            throw new BridgeError('invalid-adapter-payload', field);
        }
        return value;
    };

    const optionalString = (value, field) => {
        if (value === null || value === undefined) return null;
        if (typeof value !== 'string') {
            throw new BridgeError('invalid-adapter-payload', field);
        }
        return value;
    };

    const optionalIdentifier = (value, field) => {
        if (value === null || value === undefined) return null;
        return requireNonEmptyString(value, field);
    };

    const nonNegativeInteger = (value, field) => {
        if (!Number.isSafeInteger(value) || value < 0) {
            throw new BridgeError('invalid-adapter-payload', field);
        }
        return value;
    };

    const optionalNonNegativeInteger = (value, field) => {
        if (value === null || value === undefined) return null;
        return nonNegativeInteger(value, field);
    };

    const postWireMessage = (message) => {
        const handler = globalThis.webkit?.messageHandlers?.[MESSAGE_HANDLER];
        if (!handler || typeof handler.postMessage !== 'function') {
            return false;
        }
        handler.postMessage(JSON.stringify(message));
        return true;
    };

    const response = (requestID, kind, payload) => postWireMessage({
        bridgeVersion: BRIDGE_VERSION,
        type: 'response',
        requestID,
        envelope: {
            version: BRIDGE_VERSION,
            kind,
            payload
        }
    });

    const failure = (requestID, code, message) => postWireMessage({
        bridgeVersion: BRIDGE_VERSION,
        type: 'failure',
        ...(requestID ? { requestID } : {}),
        code,
        message: String(message || code).slice(0, 500)
    });

    const event = (kind, payload) => postWireMessage({
        bridgeVersion: BRIDGE_VERSION,
        type: 'event',
        envelope: {
            version: BRIDGE_VERSION,
            kind,
            payload
        }
    });

    const normalizeQuote = (value) => {
        if (value === null || value === undefined) return null;
        if (typeof value !== 'object') {
            throw new BridgeError('invalid-adapter-payload', 'quote');
        }
        return {
            messageID: requireNonEmptyString(value.messageID, 'quote.messageID'),
            senderID: optionalIdentifier(value.senderID, 'quote.senderID'),
            body: optionalString(value.body, 'quote.body')
        };
    };

    const normalizeMedia = (value) => {
        if (value === null || value === undefined) return null;
        if (typeof value !== 'object' || !VALID_MEDIA_KINDS.has(value.kind)) {
            throw new BridgeError('invalid-adapter-payload', 'media.kind');
        }
        return {
            kind: value.kind,
            mimeType: optionalString(value.mimeType, 'media.mimeType'),
            filename: optionalString(value.filename, 'media.filename'),
            sizeBytes: optionalNonNegativeInteger(value.sizeBytes, 'media.sizeBytes'),
            durationMilliseconds: optionalNonNegativeInteger(
                value.durationMilliseconds,
                'media.durationMilliseconds'
            ),
            width: optionalNonNegativeInteger(value.width, 'media.width'),
            height: optionalNonNegativeInteger(value.height, 'media.height')
        };
    };

    const normalizeMessage = (value) => {
        if (!value || typeof value !== 'object') {
            throw new BridgeError('invalid-adapter-payload', 'message');
        }
        return {
            id: requireNonEmptyString(value.id, 'message.id'),
            chatID: requireNonEmptyString(value.chatID, 'message.chatID'),
            senderID: optionalIdentifier(value.senderID, 'message.senderID'),
            timestampMilliseconds: nonNegativeInteger(
                value.timestampMilliseconds,
                'message.timestampMilliseconds'
            ),
            body: optionalString(value.body, 'message.body'),
            fromMe: Boolean(value.fromMe),
            quote: normalizeQuote(value.quote),
            media: normalizeMedia(value.media)
        };
    };

    const normalizeChat = (value) => {
        if (!value || typeof value !== 'object') {
            throw new BridgeError('invalid-adapter-payload', 'chat');
        }
        return {
            id: requireNonEmptyString(value.id, 'chat.id'),
            title: typeof value.title === 'string' ? value.title : '',
            isGroup: Boolean(value.isGroup),
            unreadCount: nonNegativeInteger(value.unreadCount ?? 0, 'chat.unreadCount'),
            lastMessageTimestampMilliseconds: optionalNonNegativeInteger(
                value.lastMessageTimestampMilliseconds,
                'chat.lastMessageTimestampMilliseconds'
            )
        };
    };

    const normalizeCursor = (value) => {
        if (value === null || value === undefined) return null;
        if (typeof value !== 'object') {
            throw new BridgeError('invalid-adapter-payload', 'cursor');
        }
        const beforeMessageID = optionalIdentifier(value.beforeMessageID, 'cursor.beforeMessageID');
        const beforeTimestampMilliseconds = optionalNonNegativeInteger(
            value.beforeTimestampMilliseconds,
            'cursor.beforeTimestampMilliseconds'
        );
        if (beforeMessageID === null && beforeTimestampMilliseconds === null) {
            throw new BridgeError('invalid-adapter-payload', 'cursor');
        }
        return { beforeMessageID, beforeTimestampMilliseconds };
    };

    const normalizePage = (value) => {
        if (!value || typeof value !== 'object' || !Array.isArray(value.messages)) {
            throw new BridgeError('invalid-adapter-payload', 'messagePage');
        }
        return {
            messages: value.messages.map(normalizeMessage),
            nextCursor: normalizeCursor(value.nextCursor)
        };
    };

    const validateAdapter = (adapter) => {
        if (!adapter || typeof adapter !== 'object') return null;
        const methods = ['connectionState', 'listChats', 'loadMessages', 'sendText', 'reply'];
        return methods.every((name) => typeof adapter[name] === 'function') ? adapter : null;
    };

    const resolveAdapter = () => {
        const explicit = validateAdapter(globalThis[GLOBAL_ADAPTER]);
        if (explicit) return explicit;

        // Runtime experiments may expose a narrowly wrapped Store adapter here.
        // Raw WhatsApp Store/module objects are deliberately never exported to Swift.
        const storeAdapter = validateAdapter(globalThis.Store?.__waTranslatorAdapter);
        return storeAdapter || null;
    };

    const requireAdapter = () => {
        const adapter = resolveAdapter();
        if (!adapter) {
            throw new BridgeError(
                'adapter-unavailable',
                'WhatsApp runtime adapter is not available on this page version.'
            );
        }
        return adapter;
    };

    const validateRequest = (request) => {
        if (!request || typeof request !== 'object') {
            throw new BridgeError('invalid-request', 'request');
        }
        if (request.version !== BRIDGE_VERSION) {
            throw new BridgeError('unsupported-version', String(request.version));
        }
        requireNonEmptyString(request.requestID, 'requestID');
        requireNonEmptyString(request.kind, 'kind');
        if (!request.payload || typeof request.payload !== 'object') {
            throw new BridgeError('invalid-request', 'payload');
        }
        return request;
    };

    const requiredPayloadIdentifier = (payload, field) =>
        requireNonEmptyString(payload[field], `payload.${field}`);

    const requiredPayloadText = (payload) => {
        const text = requireNonEmptyString(payload.text, 'payload.text');
        if (text.trim().length === 0) {
            throw new BridgeError('invalid-request', 'payload.text');
        }
        return text;
    };

    const handleRequest = async (rawRequest) => {
        const request = validateRequest(rawRequest);
        const adapter = requireAdapter();
        const payload = request.payload;

        switch (request.kind) {
        case 'connectionState': {
            const state = await adapter.connectionState();
            if (!VALID_STATES.has(state)) {
                throw new BridgeError('invalid-adapter-payload', 'connectionState');
            }
            response(request.requestID, 'connectionState', { state });
            return;
        }
        case 'listChats': {
            const chats = await adapter.listChats();
            if (!Array.isArray(chats)) {
                throw new BridgeError('invalid-adapter-payload', 'chats');
            }
            response(request.requestID, 'listChats', { chats: chats.map(normalizeChat) });
            return;
        }
        case 'loadMessages': {
            const chatID = requiredPayloadIdentifier(payload, 'chatID');
            const limit = nonNegativeInteger(payload.limit, 'payload.limit');
            if (limit < 1 || limit > 100) {
                throw new BridgeError('invalid-request', 'payload.limit');
            }
            const page = await adapter.loadMessages({
                chatID,
                cursor: normalizeCursor(payload.cursor),
                limit
            });
            response(request.requestID, 'loadMessages', normalizePage(page));
            return;
        }
        case 'sendText': {
            const chatID = requiredPayloadIdentifier(payload, 'chatID');
            const text = requiredPayloadText(payload);
            const message = await adapter.sendText({ chatID, text });
            response(request.requestID, 'sendText', { message: normalizeMessage(message) });
            return;
        }
        case 'reply': {
            const chatID = requiredPayloadIdentifier(payload, 'chatID');
            const messageID = requiredPayloadIdentifier(payload, 'messageID');
            const text = requiredPayloadText(payload);
            const message = await adapter.reply({ chatID, messageID, text });
            response(request.requestID, 'reply', { message: normalizeMessage(message) });
            return;
        }
        default:
            throw new BridgeError('unsupported-request', request.kind);
        }
    };

    const normalizeAndEmitAdapterEvent = (rawEvent) => {
        if (!rawEvent || typeof rawEvent !== 'object' || typeof rawEvent.kind !== 'string') {
            throw new BridgeError('invalid-adapter-payload', 'event');
        }

        switch (rawEvent.kind) {
        case 'ready':
            event('ready', {});
            break;
        case 'message':
            event('message', normalizeMessage(rawEvent.payload));
            break;
        case 'messageUpdate':
            event('messageUpdate', normalizeMessage(rawEvent.payload));
            break;
        case 'chatUpdate':
            event('chatUpdate', normalizeChat(rawEvent.payload));
            break;
        case 'disconnected':
            event('disconnected', {
                reason: optionalString(rawEvent.payload?.reason, 'disconnected.reason')
            });
            break;
        case 'historySync': {
            const payload = rawEvent.payload;
            if (!payload || typeof payload !== 'object' || !Array.isArray(payload.messages)) {
                throw new BridgeError('invalid-adapter-payload', 'historySync');
            }
            const chatID = requireNonEmptyString(payload.chatID, 'historySync.chatID');
            const messages = payload.messages.map(normalizeMessage);
            if (messages.some((message) => message.chatID !== chatID)) {
                throw new BridgeError('invalid-adapter-payload', 'historySync.chatID');
            }
            event('historySync', {
                chatID,
                messages,
                nextCursor: normalizeCursor(payload.nextCursor)
            });
            break;
        }
        default:
            throw new BridgeError('unsupported-event', rawEvent.kind);
        }
    };

    let subscribedAdapter = null;
    let unsubscribeAdapter = null;

    const refreshSubscription = () => {
        const adapter = resolveAdapter();
        if (adapter === subscribedAdapter) return;

        if (typeof unsubscribeAdapter === 'function') {
            try { unsubscribeAdapter(); } catch { /* best effort */ }
        }
        subscribedAdapter = adapter;
        unsubscribeAdapter = null;

        if (!adapter || typeof adapter.subscribe !== 'function') return;
        try {
            const unsubscribe = adapter.subscribe((adapterEvent) => {
                try {
                    normalizeAndEmitAdapterEvent(adapterEvent);
                } catch (error) {
                    failure(null, error?.code || 'adapter-event-error', error?.message || String(error));
                }
            });
            unsubscribeAdapter = typeof unsubscribe === 'function' ? unsubscribe : null;
        } catch (error) {
            failure(null, error?.code || 'adapter-subscribe-error', error?.message || String(error));
        }
    };

    const invoke = (request) => {
        Promise.resolve()
            .then(() => handleRequest(request))
            .catch((error) => {
                const requestID = typeof request?.requestID === 'string' ? request.requestID : null;
                failure(requestID, error?.code || 'adapter-error', error?.message || String(error));
            });
        return true;
    };

    globalThis[GLOBAL_BRIDGE] = Object.freeze({
        version: BRIDGE_VERSION,
        invoke
    });

    refreshSubscription();
    globalThis.setInterval(refreshSubscription, 2000);
})();
