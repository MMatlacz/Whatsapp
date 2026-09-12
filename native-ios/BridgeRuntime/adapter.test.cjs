const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createAdapter } = require('./adapter.js');

function fixture() {
    const calls = [];
    const raw = { id: { _serialized: 'message-1', remote: { _serialized: 'test@c.us' }, fromMe: true },
        t: 100, body: 'Test', from: { _serialized: 'self@c.us' } };
    const wpp = {
        isReady: true,
        conn: { isAuthenticated: () => true, isMainReady: () => true, isOnline: () => true },
        chat: {
            list: async () => [{ id: { _serialized: 'test@c.us' }, name: 'Test', unreadCount: 2, t: 100 }],
            getMessages: async (...args) => { calls.push(args); return [raw]; },
            sendTextMessage: async (...args) => { calls.push(args); return { id: 'message-1' }; },
            getMessageById: async () => raw
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
test('send disables implicit read, mentions and contact creation; reply uses quote', async () => {
    const { adapter, calls } = fixture();
    await adapter.reply({ chatID: 'test@c.us', text: 'Test', messageID: 'quote-1' });
    assert.equal(calls[0][2].quotedMsg, 'quote-1');
    assert.equal(calls[0][2].markIsRead, false);
    assert.equal(calls[0][2].detectMentioned, false);
    assert.equal(calls[0][2].createChat, false);
});
test('rejects cross-chat history, invalid limits and unready sends', async () => {
    const { adapter, wpp } = fixture();
    await assert.rejects(adapter.loadMessages({ chatID: 'other@c.us', limit: 10 }), /cross-chat/);
    await assert.rejects(adapter.loadMessages({ chatID: 'test@c.us', limit: 0 }), /invalid-limit/);
    wpp.conn.isOnline = () => false;
    await assert.rejects(adapter.sendText({ chatID: 'test@c.us', text: 'Test' }), /not-ready/);
});
