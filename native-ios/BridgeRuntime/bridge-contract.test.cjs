'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const bridgePath = path.resolve(__dirname, '../WhatsAppTranslator/WhatsAppBridge.js');

const baseMessage = (content, body = null) => ({
    id: 'm1', chatID: 'chat-1', senderID: null,
    timestampMilliseconds: 1, body, fromMe: false,
    deliveryState: null, quote: null, media: null, linkPreview: null,
    content
});

const adapterWithMessage = (message) => ({
    connectionState: async () => 'ready',
    listChats: async () => [],
    loadMessages: async () => ({ messages: [message], nextCursor: null }),
    sendText: async () => message,
    reply: async () => message,
    mediaPreview: async () => { throw new Error('unused'); }
});

const settle = () => new Promise((resolve) => setImmediate(resolve));
test('bridge canonicalizes semantic content and rejects oversized special fields', async () => {
    const posted = [];
    const originalSetInterval = globalThis.setInterval;
    globalThis.setInterval = () => 0;
    globalThis.webkit = { messageHandlers: { whatsAppBridge: {
        postMessage: (value) => posted.push(JSON.parse(value))
    } } };
    globalThis.__waTranslatorRuntimeAdapter = adapterWithMessage(baseMessage({
        kind: 'contact', contacts: [{ displayName: 'Ada', vCard: 'BEGIN:VCARD\nEND:VCARD' }]
    }));
    delete require.cache[bridgePath];
    require(bridgePath);
    globalThis.setInterval = originalSetInterval;

    globalThis.__waTranslatorBridge.invoke({
        version: 1, requestID: 'good', kind: 'loadMessages',
        payload: { chatID: 'chat-1', cursor: null, limit: 1 }
    });
    await settle();

    const good = posted.find((item) => item.requestID === 'good');
    assert.equal(good.type, 'response');
    assert.deepEqual(good.envelope.payload.messages[0].content, {
        kind: 'contact', contacts: [{ displayName: 'Ada', vCard: 'BEGIN:VCARD\nEND:VCARD' }]
    });
    globalThis.__waTranslatorRuntimeAdapter = adapterWithMessage(baseMessage({
        kind: 'contact', contacts: [{ displayName: 'Ada', vCard: 'x'.repeat(4097) }]
    }));
    globalThis.__waTranslatorBridge.invoke({
        version: 1, requestID: 'oversized', kind: 'loadMessages',
        payload: { chatID: 'chat-1', cursor: null, limit: 1 }
    });
    await settle();

    const oversized = posted.find((item) => item.requestID === 'oversized');
    assert.equal(oversized.type, 'failure');
    assert.equal(oversized.code, 'invalid-adapter-payload');

    globalThis.__waTranslatorRuntimeAdapter = adapterWithMessage(baseMessage({
        kind: 'system', system: { type: 'notification', text: 'joined' }
    }, 'raw-system-body'));
    globalThis.__waTranslatorBridge.invoke({
        version: 1, requestID: 'raw-body', kind: 'loadMessages',
        payload: { chatID: 'chat-1', cursor: null, limit: 1 }
    });
    await settle();
    const leaked = posted.find((item) => item.requestID === 'raw-body');
    assert.equal(leaked.type, 'failure');
    assert.equal(leaked.code, 'invalid-adapter-payload');
});
