const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createAdapter } = require('./adapter.js');

function fixture() {
    const calls = [];
    const raw = { id: { _serialized: 'message-1', remote: { _serialized: 'test@c.us' }, fromMe: true },
        t: 100, body: 'Test', from: { _serialized: 'self@c.us' } };
    const wpp = {
        isReady: true,
        conn: { isRegistered: () => true, isAuthenticated: () => true,
            isMainReady: () => true, isOnline: () => true },
        chat: {
            list: async () => [{ id: { _serialized: 'test@c.us' }, name: 'Test', unreadCount: 2, t: 100 }],
            getMessages: async (...args) => { calls.push(args); return [raw]; },
            sendTextMessage: async (...args) => { calls.push(args); return { id: 'message-1' }; },
            getMessageById: async (...args) => { calls.push(['getMessageById', ...args]); return raw; }
        },
        on: (...args) => calls.push(args), off: (...args) => calls.push(args)
    };
    return { adapter: createAdapter(wpp), wpp, raw, calls };
}
test('maps chat and message values without leaking raw runtime objects', async () => {
    const { adapter } = fixture();
    assert.equal((await adapter.listChats())[0].title, 'Test');
    const page = await adapter.loadMessages({ chatID: 'test@c.us', limit: 1 });
    assert.equal(page.messages[0].timestampMilliseconds, 100000);
    assert.equal(page.nextCursor.beforeMessageID, 'message-1');
    assert.equal(page.messages[0].media, null);
});
test('does not read the throwing quoted-message getter for ordinary messages', async () => {
    const { adapter, raw } = fixture();
    Object.defineProperty(raw, 'quotedMsg', {
        configurable: true,
        get() { throw new Error('message_not_have_a_reply'); }
    });
    const page = await adapter.loadMessages({ chatID: 'test@c.us', limit: 1 });
    assert.equal(page.messages[0].quote, null);
    await adapter.sendText({ chatID: 'test@c.us', text: 'Test' });
});
test('preserves each chat unread count when mapping a list', async () => {
    const { adapter, wpp } = fixture();
    wpp.chat.list = async () => [
        { id: { _serialized: 'first@c.us' }, name: 'First', unreadCount: 7, t: 100 },
        { id: { _serialized: 'second@c.us' }, name: 'Second', unreadCount: 2, t: 99 }
    ];
    const chats = await adapter.listChats();
    assert.deepEqual(chats.map(({ id, unreadCount }) => ({ id, unreadCount })), [
        { id: 'first@c.us', unreadCount: 7 },
        { id: 'second@c.us', unreadCount: 2 }
    ]);
});
test('keeps the requested chat ID stable across the public phone/LID mapping', async () => {
    const { adapter, wpp, raw } = fixture();
    raw.id.remote = { _serialized: '987654@lid' };
    wpp.contact = {
        getPnLidEntry: async (value) => {
            const id = typeof value === 'string' ? value : value?._serialized;
            return id === '987654@lid'
                ? { lid: { _serialized: '987654@lid' }, phoneNumber: { _serialized: '491234@c.us' } }
                : { phoneNumber: { _serialized: '491234@c.us' }, lid: { _serialized: '987654@lid' } };
        }
    };
    const page = await adapter.loadMessages({ chatID: '491234@c.us', limit: 1 });
    assert.equal(page.messages[0].chatID, '491234@c.us');
});
test('retries transient phone/LID alias resolution without returning a partial page', async () => {
    const { adapter, wpp, raw } = fixture();
    raw.id.remote = { _serialized: '491234@c.us' };
    const lidRow = {
        ...raw,
        id: { _serialized: 'message-lid', remote: { _serialized: '987654@lid' }, fromMe: false },
        t: 99,
        from: { _serialized: '987654@lid' }
    };
    wpp.chat.getMessages = async () => [raw, lidRow];
    let attempts = 0;
    wpp.contact = {
        getPnLidEntry: async (value) => {
            attempts += 1;
            if (attempts <= 2) throw new Error('temporary-alias-failure');
            const valueID = typeof value === 'string' ? value : value?._serialized;
            return valueID === '987654@lid'
                ? { lid: { _serialized: '987654@lid' }, phoneNumber: { _serialized: '491234@c.us' } }
                : { phoneNumber: { _serialized: '491234@c.us' }, lid: { _serialized: '987654@lid' } };
        }
    };
    await assert.rejects(
        adapter.loadMessages({ chatID: '491234@c.us', limit: 2 }),
        (error) => error?.code === 'chat-identity-unresolved'
    );
    const page = await adapter.loadMessages({ chatID: '491234@c.us', limit: 2 });
    assert.deepEqual(page.messages.map((message) => message.id), ['message-lid', 'message-1']);
    assert.ok(page.messages.every((message) => message.chatID === '491234@c.us'));
    assert.equal(page.nextCursor.beforeMessageID, 'message-lid');
    assert.equal(attempts, 4);
});
test('treats unavailable phone/LID resolver as retryable unknown identity', async () => {
    const { adapter, wpp, raw } = fixture();
    raw.id.remote = { _serialized: '987654@lid' };
    wpp.contact = {};
    await assert.rejects(
        adapter.loadMessages({ chatID: '491234@c.us', limit: 1 }),
        (error) => error?.code === 'chat-identity-unresolved'
            && error?.reason === 'alias-resolver-unavailable'
    );
});
test('isolates malformed history rows and advances with the raw page boundary', async () => {
    const { adapter, wpp, raw } = fixture();
    const malformed = {
        id: { _serialized: 'message-bad', remote: { _serialized: 'test@c.us' } },
        t: 50,
        body: 'not safely hydrated yet'
    };
    wpp.chat.getMessages = async () => [raw, malformed];
    const page = await adapter.loadMessages({ chatID: 'test@c.us', limit: 2 });
    assert.deepEqual(page.messages.map((message) => message.id), ['message-1']);
    assert.equal(page.nextCursor.beforeMessageID, 'message-bad');
    assert.equal(page.nextCursor.beforeTimestampMilliseconds, 50000);
});
test('drops isolated cross-chat history rows but rejects a page that is entirely cross-chat', async () => {
    const { adapter, wpp, raw } = fixture();
    const foreign = {
        id: { _serialized: 'foreign-1', remote: { _serialized: 'other@c.us' }, fromMe: false },
        t: 50,
        body: 'foreign',
        from: { _serialized: 'other@c.us' }
    };
    wpp.chat.getMessages = async () => [raw, foreign];
    const mixed = await adapter.loadMessages({ chatID: 'test@c.us', limit: 2 });
    assert.deepEqual(mixed.messages.map((message) => message.id), ['message-1']);
    assert.equal(mixed.nextCursor.beforeMessageID, 'foreign-1');
    wpp.chat.getMessages = async () => [foreign];
    await assert.rejects(adapter.loadMessages({ chatID: 'test@c.us', limit: 1 }), /cross-chat-history/);
});
test('rejects timestamps that cannot be represented safely in the native wire format', async () => {
    const { adapter, raw } = fixture();
    raw.t = Number.MAX_SAFE_INTEGER;
    await assert.rejects(adapter.loadMessages({ chatID: 'test@c.us', limit: 1 }), /invalid-message-time/);
});
test('registered reconnect is not mistaken for missing pairing', async () => {
    const { adapter, wpp } = fixture();
    wpp.conn.isAuthenticated = () => false;
    assert.equal(await adapter.connectionState(), 'connecting');
    wpp.conn.isRegistered = () => false;
    assert.equal(await adapter.connectionState(), 'authenticating');
});
test('edited messages retain identity and reject cross-chat event payloads', () => {
    const { adapter, raw, calls } = fixture();
    const events = [];
    adapter.subscribe((event) => events.push(event));
    const edited = calls.find(([name]) => name === 'chat.msg_edited')[1];
    raw.body = 'Corrected text';
    edited({ chat: { _serialized: 'test@c.us' }, id: 'message-1', msg: raw });
    assert.equal(events[0].kind, 'messageUpdate');
    assert.equal(events[0].payload.id, 'message-1');
    assert.equal(events[0].payload.body, 'Corrected text');
    edited({ chat: { _serialized: 'other@c.us' }, id: 'message-1', msg: raw });
    assert.equal(events[1].kind, 'disconnected');
});
test('maps quote and safe media metadata without copying thumbnail bodies or media secrets', async () => {
    const { adapter, raw } = fixture();
    Object.assign(raw, { type: 'image', body: 'thumbnail-payload', caption: 'Photo caption',
        mimetype: 'image/jpeg', size: 512, width: 100, height: 80,
        mediaKey: 'fixture-private-key', clientUrl: 'https://example.invalid/private',
        quotedMsg: { id: { _serialized: 'quote-1' }, type: 'chat', body: 'Original quote' } });
    const { messages: [mapped] } = await adapter.loadMessages({ chatID: 'test@c.us', limit: 10 });
    assert.equal(mapped.body, 'Photo caption');
    assert.equal(mapped.quote.body, 'Original quote');
    assert.equal(mapped.media.kind, 'image');
    assert.equal(mapped.media.sizeBytes, 512);
    assert.equal(mapped.media.width, 100);
    assert.ok(!JSON.stringify(mapped).includes('fixture-private-key'));
    assert.ok(!JSON.stringify(mapped).includes('thumbnail-payload'));
    raw.isViewOnce = true;
    const page = await adapter.loadMessages({ chatID: 'test@c.us', limit: 10 });
    assert.equal(page.messages[0].body, null);
});
test('maps WhatsApp link preview metadata without embedding thumbnail bytes in history', async () => {
    const { adapter, raw } = fixture();
    raw.body = 'Watch https://example.com/video';
    raw.linkPreview = {
        matchedText: 'https://example.com/video',
        canonicalUrl: 'https://example.com/video',
        title: 'Example video',
        description: 'Preview from WhatsApp',
        thumbnail: Buffer.from('small-thumbnail').toString('base64')
    };
    const page = await adapter.loadMessages({ chatID: 'test@c.us', limit: 1 });
    assert.deepEqual(page.messages[0].linkPreview, {
        matchedText: 'https://example.com/video',
        canonicalURL: 'https://example.com/video',
        title: 'Example video',
        description: 'Preview from WhatsApp'
    });
    assert.ok(!JSON.stringify(page.messages[0]).includes(raw.linkPreview.thumbnail));
    const preview = await adapter.mediaPreview({
        chatID: 'test@c.us', messageID: 'message-1', maxPixelSize: 320
    });
    assert.equal(preview.data, raw.linkPreview.thumbnail);
    assert.equal(preview.mimeType, 'image/jpeg');
});
test('refuses view-once media previews before download', async () => {
    const { adapter, wpp, raw } = fixture();
    let downloads = 0;
    Object.assign(raw, { type: 'image', mimetype: 'image/jpeg', isViewOnce: true });
    wpp.chat.downloadMedia = async () => {
        downloads += 1;
        return new Blob(['secret'], { type: 'image/jpeg' });
    };
    await assert.rejects(
        adapter.mediaPreview({ chatID: 'test@c.us', messageID: 'message-1', maxPixelSize: 768 }),
        /view-once-media/
    );
    assert.equal(downloads, 0);
    const page = await adapter.loadMessages({ chatID: 'test@c.us', limit: 1 });
    assert.equal(page.messages[0].media.isViewOnce, true);
});
test('online events do not announce ready before authentication and synchronization', () => {
    const { adapter, wpp, calls } = fixture();
    const events = [];
    const unsubscribe = adapter.subscribe((event) => events.push(event));
    const online = calls.find(([name]) => name === 'conn.online')[1];
    wpp.conn.isAuthenticated = () => false;
    online(true);
    assert.equal(events.length, 0);
    wpp.conn.isAuthenticated = () => true;
    wpp.conn.isMainReady = () => false;
    online(true);
    assert.equal(events.length, 0);
    wpp.conn.isMainReady = () => true;
    online(true);
    assert.equal(events[0].kind, 'ready');
    online(false);
    assert.equal(events[1].kind, 'disconnected');
    unsubscribe();
});
test('send disables implicit read, mentions and contact creation; reply uses quote', async () => {
    const { adapter, calls } = fixture();
    await adapter.reply({ chatID: 'test@c.us', text: 'Test', messageID: 'quote-1' });
    assert.equal(calls[0][2].quotedMsg, 'quote-1');
    assert.equal(calls[0][2].markIsRead, false);
    assert.equal(calls[0][2].detectMentioned, false);
    assert.equal(calls[0][2].createChat, false);
});
test('send confirmation can arrive after the send without retrying the send', async () => {
    const { adapter, wpp, calls, raw } = fixture();
    let reads = 0;
    wpp.chat.getMessageById = async () => {
        reads += 1;
        return reads < 2 ? undefined : raw;
    };
    await adapter.sendText({ chatID: 'test@c.us', text: 'Test' });
    assert.equal(reads, 2);
    assert.equal(calls.filter(([chatID]) => chatID === 'test@c.us').length, 1);
});
test('send does not accept a result below the SENT acknowledgement', async () => {
    const { adapter, wpp, calls } = fixture();
    wpp.chat.sendTextMessage = async (...args) => {
        calls.push(args);
        return { id: 'message-1', ack: 0 };
    };
    await assert.rejects(adapter.sendText({ chatID: 'test@c.us', text: 'Test' }), /send-not-accepted/);
    assert.equal(calls.filter(([name]) => name === 'getMessageById').length, 0);
});
test('maps observed ACK states and keeps malformed message events non-fatal', async () => {
    const { adapter, raw, calls } = fixture();
    raw.ack = 2;
    const page = await adapter.loadMessages({ chatID: 'test@c.us', limit: 1 });
    assert.equal(page.messages[0].deliveryState, 'delivered');

    const events = [];
    adapter.subscribe((event) => events.push(event));
    const incoming = calls.find(([name]) => name === 'chat.new_message')[1];
    incoming({ id: {}, t: 100 });
    assert.deepEqual(events, []);

    const ackChanged = calls.find(([name]) => name === 'chat.msg_ack_change')[1];
    ackChanged({ ack: 3, chat: { _serialized: 'test@c.us' }, ids: [raw.id] });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(events[0].kind, 'messageUpdate');
    assert.equal(events[0].payload.deliveryState, 'read');
});
test('rejects cross-chat history, invalid limits and unready sends', async () => {
    const { adapter, wpp } = fixture();
    await assert.rejects(adapter.loadMessages({ chatID: 'other@c.us', limit: 10 }), /cross-chat/);
    await assert.rejects(adapter.loadMessages({ chatID: 'test@c.us', limit: 0 }), /invalid-limit/);
    wpp.conn.isOnline = () => false;
    await assert.rejects(adapter.sendText({ chatID: 'test@c.us', text: 'Test' }), /not-ready/);
});
