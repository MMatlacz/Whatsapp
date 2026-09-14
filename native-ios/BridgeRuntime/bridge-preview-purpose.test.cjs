const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function bridgeFixture() {
    const posted = [];
    const previewCalls = [];
    const adapter = {
        connectionState: async () => 'ready',
        listChats: async () => [],
        loadMessages: async () => ({ messages: [], nextCursor: null }),
        sendText: async () => { throw new Error('unused'); },
        reply: async () => { throw new Error('unused'); },
        mediaPreview: async (request) => {
            previewCalls.push(request);
            return { mimeType: 'image/jpeg', data: Buffer.from('thumb').toString('base64'), width: 10, height: 10 };
        }
    };
    const context = {
        console,
        URL,
        setInterval: () => 0,
        globalThis: null,
        webkit: { messageHandlers: { whatsAppBridge: { postMessage: (value) => posted.push(JSON.parse(value)) } } },
        __waTranslatorRuntimeAdapter: adapter
    };
    context.globalThis = context;
    const source = fs.readFileSync(path.join(__dirname, '..', 'WhatsAppTranslator', 'WhatsAppBridge.js'), 'utf8');
    vm.runInNewContext(source, context);
    return { bridge: context.__waTranslatorBridge, posted, previewCalls };
}

async function flush() {
    await new Promise((resolve) => setImmediate(resolve));
}

test('bridge requires and forwards preview purpose', async () => {
    const { bridge, posted, previewCalls } = bridgeFixture();
    bridge.invoke({ version: 1, requestID: 'p1', kind: 'mediaPreview', payload: {
        chatID: 'chat@c.us', messageID: 'm1', previewPurpose: 'linkPreview', maxPixelSize: 320
    }});
    await flush();
    assert.equal(previewCalls.length, 1);
    assert.equal(previewCalls[0].chatID, 'chat@c.us');
    assert.equal(previewCalls[0].messageID, 'm1');
    assert.equal(previewCalls[0].purpose, 'linkPreview');
    assert.equal(previewCalls[0].maxPixelSize, 320);
    assert.equal(posted[0].type, 'response');
    assert.equal(posted[0].envelope.kind, 'mediaPreview');
});

test('bridge rejects missing or unknown preview purpose before adapter invocation', async () => {
    const { bridge, posted, previewCalls } = bridgeFixture();
    bridge.invoke({ version: 1, requestID: 'p1', kind: 'mediaPreview', payload: {
        chatID: 'chat@c.us', messageID: 'm1', maxPixelSize: 320
    }});
    bridge.invoke({ version: 1, requestID: 'p2', kind: 'mediaPreview', payload: {
        chatID: 'chat@c.us', messageID: 'm1', previewPurpose: 'videoDownload', maxPixelSize: 320
    }});
    await flush();
    assert.equal(previewCalls.length, 0);
    assert.equal(posted.length, 2);
    assert.ok(posted.every((message) => message.type === 'failure' && message.code === 'invalid-request'));
});
