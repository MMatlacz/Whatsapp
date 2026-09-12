import Foundation

#if SWIFT_PACKAGE
import WhatsAppDomainCore
#endif

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

public enum SQLitePersistenceError: Error, Equatable, Sendable {
    case openFailed(String)
    case sqlite(code: Int32, message: String)
    case unsupportedSchemaVersion(Int32)
    case invalidArgument(String)
    case invalidStoredValue(String)
    case missingChat(WhatsAppChatID)
    case unsupportedTranslationMetadata
}

public final class SQLiteWhatsAppStore: @unchecked Sendable {
    public static let schemaVersion: Int32 = 2

    private let lock = NSLock()
    private var db: OpaquePointer?

    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw SQLitePersistenceError.openFailed(message)
        }

        db = handle
        do {
            try execute("PRAGMA foreign_keys = ON")
            _ = sqlite3_busy_timeout(handle, 5_000)
            try migrateIfNeeded()
        } catch {
            sqlite3_close(handle)
            db = nil
            throw error
        }
    }

    deinit {
        lock.lock()
        if let db {
            sqlite3_close(db)
        }
        db = nil
        lock.unlock()
    }

    public func currentSchemaVersion() throws -> Int32 {
        try locked { try pragmaUserVersion() }
    }

    /// Drafts deliberately do not require a cached chat row: offline composition
    /// must survive even when the chat list has not finished synchronizing.
    public func saveDraft(_ body: String, chatID: WhatsAppChatID) throws {
        try locked {
            let statement = try prepare("""
                INSERT INTO chat_drafts(chat_id, body) VALUES (?, ?)
                ON CONFLICT(chat_id) DO UPDATE SET body = excluded.body
                """)
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            try bindText(body, at: 2, to: statement)
            try stepDone(statement)
        }
    }

    public func drafts() throws -> [String: String] {
        try locked {
            let statement = try prepare("SELECT chat_id, body FROM chat_drafts")
            defer { sqlite3_finalize(statement) }
            var values: [String: String] = [:]
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return values }
                guard result == SQLITE_ROW else { throw sqliteError(code: result) }
                guard let chatID = columnText(statement, at: 0),
                      let body = columnText(statement, at: 1) else {
                    throw SQLitePersistenceError.invalidStoredValue("chat_drafts")
                }
                values[chatID] = body
            }
        }
    }

    public func upsert(chat: WhatsAppChat) throws {
        try locked {
            let sql = """
            INSERT INTO chats(id, title, kind, unread_count, last_message_at_ms)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                kind = excluded.kind,
                unread_count = excluded.unread_count,
                last_message_at_ms = excluded.last_message_at_ms
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            try bindText(chat.id.rawValue, at: 1, to: statement)
            try bindText(chat.title, at: 2, to: statement)
            try bindText(encode(chat.kind), at: 3, to: statement)
            try bindInt64(Int64(chat.unreadCount), at: 4, to: statement)
            try bindOptionalInt64(chat.lastMessageAt?.millisecondsSince1970, at: 5, to: statement)
            try stepDone(statement)
        }
    }

    public func chats() throws -> [WhatsAppChat] {
        try locked {
            let statement = try prepare("""
                SELECT id, title, kind, unread_count, last_message_at_ms FROM chats
                ORDER BY last_message_at_ms DESC, id
                """)
            defer { sqlite3_finalize(statement) }
            var values: [WhatsAppChat] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return values }
                guard result == SQLITE_ROW else { throw sqliteError(code: result) }
                values.append(try decodeChat(statement))
            }
        }
    }

    public func chat(id: WhatsAppChatID) throws -> WhatsAppChat? {
        try locked {
            let statement = try prepare(
                "SELECT id, title, kind, unread_count, last_message_at_ms FROM chats WHERE id = ?"
            )
            defer { sqlite3_finalize(statement) }
            try bindText(id.rawValue, at: 1, to: statement)

            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }
            return try decodeChat(statement)
        }
    }

    public func upsert(participant: WhatsAppParticipant) throws {
        try locked { try upsertParticipant(participant) }
    }

    public func participant(id: WhatsAppParticipantID) throws -> WhatsAppParticipant? {
        try locked {
            let statement = try prepare(
                "SELECT id, display_name FROM participants WHERE id = ?"
            )
            defer { sqlite3_finalize(statement) }
            try bindText(id.rawValue, at: 1, to: statement)

            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }

            guard let rawID = columnText(statement, at: 0), let participantID = WhatsAppParticipantID(rawID) else {
                throw SQLitePersistenceError.invalidStoredValue("participants.id")
            }
            return WhatsAppParticipant(id: participantID, displayName: columnText(statement, at: 1))
        }
    }

    public func upsert(message: WhatsAppMessage) throws {
        guard message.translation == nil else {
            throw SQLitePersistenceError.unsupportedTranslationMetadata
        }

        try locked {
            guard try chatExists(message.chatID) else {
                throw SQLitePersistenceError.missingChat(message.chatID)
            }

            if let senderID = message.senderID {
                try upsertParticipant(WhatsAppParticipant(id: senderID, displayName: nil), preserveExistingName: true)
            }
            if let quoteSenderID = message.quote?.senderID {
                try upsertParticipant(WhatsAppParticipant(id: quoteSenderID, displayName: nil), preserveExistingName: true)
            }

            let sql = """
            INSERT INTO messages(
                chat_id,
                whatsapp_message_id,
                sender_id,
                timestamp_ms,
                body,
                from_me,
                quote_message_id,
                quote_sender_id,
                quote_body,
                media_kind,
                media_mime_type,
                media_filename,
                media_size_bytes,
                media_duration_ms,
                media_width,
                media_height
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chat_id, whatsapp_message_id) DO UPDATE SET
                sender_id = excluded.sender_id,
                timestamp_ms = excluded.timestamp_ms,
                body = excluded.body,
                from_me = excluded.from_me,
                quote_message_id = excluded.quote_message_id,
                quote_sender_id = excluded.quote_sender_id,
                quote_body = excluded.quote_body,
                media_kind = excluded.media_kind,
                media_mime_type = excluded.media_mime_type,
                media_filename = excluded.media_filename,
                media_size_bytes = excluded.media_size_bytes,
                media_duration_ms = excluded.media_duration_ms,
                media_width = excluded.media_width,
                media_height = excluded.media_height
            """

            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            try bindText(message.chatID.rawValue, at: 1, to: statement)
            try bindText(message.id.rawValue, at: 2, to: statement)
            try bindOptionalText(message.senderID?.rawValue, at: 3, to: statement)
            try bindInt64(message.timestamp.millisecondsSince1970, at: 4, to: statement)
            try bindOptionalText(message.body, at: 5, to: statement)
            try bindInt64(message.fromMe ? 1 : 0, at: 6, to: statement)
            try bindOptionalText(message.quote?.messageID.rawValue, at: 7, to: statement)
            try bindOptionalText(message.quote?.senderID?.rawValue, at: 8, to: statement)
            try bindOptionalText(message.quote?.body, at: 9, to: statement)
            try bindOptionalText(message.media.map { encode($0.kind) }, at: 10, to: statement)
            try bindOptionalText(message.media?.mimeType, at: 11, to: statement)
            try bindOptionalText(message.media?.filename, at: 12, to: statement)
            try bindOptionalInt64(message.media?.sizeBytes, at: 13, to: statement)
            try bindOptionalInt64(message.media?.durationMilliseconds, at: 14, to: statement)
            try bindOptionalInt64(message.media?.width.map(Int64.init), at: 15, to: statement)
            try bindOptionalInt64(message.media?.height.map(Int64.init), at: 16, to: statement)
            try stepDone(statement)
        }
    }

    public func message(chatID: WhatsAppChatID, messageID: WhatsAppMessageID) throws -> WhatsAppMessage? {
        try locked {
            let statement = try prepare(
                """
                SELECT
                    whatsapp_message_id, chat_id, sender_id, timestamp_ms, body, from_me,
                    quote_message_id, quote_sender_id, quote_body,
                    media_kind, media_mime_type, media_filename, media_size_bytes,
                    media_duration_ms, media_width, media_height
                FROM messages
                WHERE chat_id = ? AND whatsapp_message_id = ?
                """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            try bindText(messageID.rawValue, at: 2, to: statement)

            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }
            return try decodeMessage(statement)
        }
    }

    public func messages(
        chatID: WhatsAppChatID,
        before cursor: WhatsAppMessageCursor? = nil,
        limit: Int
    ) throws -> WhatsAppMessagePage {
        guard (1...100).contains(limit) else {
            throw SQLitePersistenceError.invalidArgument("limit")
        }

        return try locked {
            let cursorValues = try resolveCursor(cursor, chatID: chatID)
            let sql: String
            if cursorValues == nil {
                sql = """
                SELECT
                    whatsapp_message_id, chat_id, sender_id, timestamp_ms, body, from_me,
                    quote_message_id, quote_sender_id, quote_body,
                    media_kind, media_mime_type, media_filename, media_size_bytes,
                    media_duration_ms, media_width, media_height
                FROM messages
                WHERE chat_id = ?
                ORDER BY timestamp_ms DESC, whatsapp_message_id DESC
                LIMIT ?
                """
            } else {
                sql = """
                SELECT
                    whatsapp_message_id, chat_id, sender_id, timestamp_ms, body, from_me,
                    quote_message_id, quote_sender_id, quote_body,
                    media_kind, media_mime_type, media_filename, media_size_bytes,
                    media_duration_ms, media_width, media_height
                FROM messages
                WHERE chat_id = ?
                  AND (timestamp_ms < ? OR (timestamp_ms = ? AND whatsapp_message_id < ?))
                ORDER BY timestamp_ms DESC, whatsapp_message_id DESC
                LIMIT ?
                """
            }

            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            if let cursorValues {
                try bindInt64(cursorValues.timestamp, at: 2, to: statement)
                try bindInt64(cursorValues.timestamp, at: 3, to: statement)
                try bindText(cursorValues.messageID, at: 4, to: statement)
                try bindInt64(Int64(limit), at: 5, to: statement)
            } else {
                try bindInt64(Int64(limit), at: 2, to: statement)
            }

            var values: [WhatsAppMessage] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw sqliteError(code: result) }
                values.append(try decodeMessage(statement))
            }

            let nextCursor: WhatsAppMessageCursor?
            if values.count == limit, let last = values.last {
                nextCursor = WhatsAppMessageCursor(
                    beforeMessageID: last.id,
                    beforeTimestamp: last.timestamp
                )
            } else {
                nextCursor = nil
            }
            return WhatsAppMessagePage(messages: values, nextCursor: nextCursor)
        }
    }

    public func messageCount(chatID: WhatsAppChatID) throws -> Int {
        try locked {
            let statement = try prepare("SELECT COUNT(*) FROM messages WHERE chat_id = ?")
            defer { sqlite3_finalize(statement) }
            try bindText(chatID.rawValue, at: 1, to: statement)
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else { throw sqliteError(code: result) }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func migrateIfNeeded() throws {
        try locked {
            let version = try pragmaUserVersion()
            guard version <= Self.schemaVersion else {
                throw SQLitePersistenceError.unsupportedSchemaVersion(version)
            }
            guard version < Self.schemaVersion else { return }

            try executeUnlocked("BEGIN IMMEDIATE")
            do {
                if version < 1 {
                    try applyMigration1()
                }
                if version < 2 {
                    try executeUnlocked("""
                        CREATE TABLE IF NOT EXISTS chat_drafts(
                            chat_id TEXT PRIMARY KEY NOT NULL,
                            body TEXT NOT NULL
                        );
                        """)
                }
                try executeUnlocked("PRAGMA user_version = \(Self.schemaVersion)")
                try executeUnlocked("COMMIT")
            } catch {
                try? executeUnlocked("ROLLBACK")
                throw error
            }
        }
    }

    private func applyMigration1() throws {
        try executeUnlocked(
            """
            CREATE TABLE IF NOT EXISTS chats(
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                kind TEXT NOT NULL CHECK(kind IN ('direct', 'group')),
                unread_count INTEGER NOT NULL CHECK(unread_count >= 0),
                last_message_at_ms INTEGER NULL CHECK(last_message_at_ms IS NULL OR last_message_at_ms >= 0)
            );

            CREATE TABLE IF NOT EXISTS participants(
                id TEXT PRIMARY KEY NOT NULL,
                display_name TEXT NULL
            );

            CREATE TABLE IF NOT EXISTS messages(
                chat_id TEXT NOT NULL,
                whatsapp_message_id TEXT NOT NULL,
                sender_id TEXT NULL,
                timestamp_ms INTEGER NOT NULL CHECK(timestamp_ms >= 0),
                body TEXT NULL,
                from_me INTEGER NOT NULL CHECK(from_me IN (0, 1)),
                quote_message_id TEXT NULL,
                quote_sender_id TEXT NULL,
                quote_body TEXT NULL,
                media_kind TEXT NULL CHECK(media_kind IS NULL OR media_kind IN ('image', 'video', 'audio', 'document', 'sticker', 'other')),
                media_mime_type TEXT NULL,
                media_filename TEXT NULL,
                media_size_bytes INTEGER NULL CHECK(media_size_bytes IS NULL OR media_size_bytes >= 0),
                media_duration_ms INTEGER NULL CHECK(media_duration_ms IS NULL OR media_duration_ms >= 0),
                media_width INTEGER NULL CHECK(media_width IS NULL OR media_width >= 0),
                media_height INTEGER NULL CHECK(media_height IS NULL OR media_height >= 0),
                PRIMARY KEY(chat_id, whatsapp_message_id),
                FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE,
                FOREIGN KEY(sender_id) REFERENCES participants(id),
                FOREIGN KEY(quote_sender_id) REFERENCES participants(id)
            );

            CREATE INDEX IF NOT EXISTS messages_by_chat_time
            ON messages(chat_id, timestamp_ms DESC, whatsapp_message_id DESC);
            """
        )
    }

    private func resolveCursor(
        _ cursor: WhatsAppMessageCursor?,
        chatID: WhatsAppChatID
    ) throws -> (timestamp: Int64, messageID: String)? {
        guard let cursor else { return nil }
        if let timestamp = cursor.beforeTimestamp, let messageID = cursor.beforeMessageID {
            return (timestamp.millisecondsSince1970, messageID.rawValue)
        }
        if let timestamp = cursor.beforeTimestamp {
            return (timestamp.millisecondsSince1970, "")
        }
        guard let messageID = cursor.beforeMessageID else {
            throw SQLitePersistenceError.invalidArgument("cursor")
        }

        let statement = try prepare(
            "SELECT timestamp_ms FROM messages WHERE chat_id = ? AND whatsapp_message_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bindText(chatID.rawValue, at: 1, to: statement)
        try bindText(messageID.rawValue, at: 2, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            if result == SQLITE_DONE { throw SQLitePersistenceError.invalidArgument("cursor.messageID") }
            throw sqliteError(code: result)
        }
        return (sqlite3_column_int64(statement, 0), messageID.rawValue)
    }

    private func upsertParticipant(
        _ participant: WhatsAppParticipant,
        preserveExistingName: Bool = false
    ) throws {
        let sql: String
        if preserveExistingName {
            sql = """
            INSERT INTO participants(id, display_name) VALUES (?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = COALESCE(excluded.display_name, participants.display_name)
            """
        } else {
            sql = """
            INSERT INTO participants(id, display_name) VALUES (?, ?)
            ON CONFLICT(id) DO UPDATE SET display_name = excluded.display_name
            """
        }

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bindText(participant.id.rawValue, at: 1, to: statement)
        try bindOptionalText(participant.displayName, at: 2, to: statement)
        try stepDone(statement)
    }

    private func chatExists(_ id: WhatsAppChatID) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM chats WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bindText(id.rawValue, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw sqliteError(code: result)
    }

    private func decodeChat(_ statement: OpaquePointer) throws -> WhatsAppChat {
        guard
            let rawID = columnText(statement, at: 0),
            let id = WhatsAppChatID(rawID),
            let title = columnText(statement, at: 1),
            let rawKind = columnText(statement, at: 2),
            let kind = decodeChatKind(rawKind)
        else {
            throw SQLitePersistenceError.invalidStoredValue("chat")
        }

        let unreadCount64 = sqlite3_column_int64(statement, 3)
        guard unreadCount64 >= 0, unreadCount64 <= Int64(Int.max) else {
            throw SQLitePersistenceError.invalidStoredValue("chats.unread_count")
        }
        let lastMessageAt: WhatsAppTimestamp?
        if sqlite3_column_type(statement, 4) == SQLITE_NULL {
            lastMessageAt = nil
        } else {
            guard let timestamp = WhatsAppTimestamp(millisecondsSince1970: sqlite3_column_int64(statement, 4)) else {
                throw SQLitePersistenceError.invalidStoredValue("chats.last_message_at_ms")
            }
            lastMessageAt = timestamp
        }

        guard let chat = WhatsAppChat(
            id: id,
            title: title,
            kind: kind,
            unreadCount: Int(unreadCount64),
            lastMessageAt: lastMessageAt
        ) else {
            throw SQLitePersistenceError.invalidStoredValue("chat")
        }
        return chat
    }

    private func decodeMessage(_ statement: OpaquePointer) throws -> WhatsAppMessage {
        guard
            let rawMessageID = columnText(statement, at: 0),
            let messageID = WhatsAppMessageID(rawMessageID),
            let rawChatID = columnText(statement, at: 1),
            let chatID = WhatsAppChatID(rawChatID),
            let timestamp = WhatsAppTimestamp(millisecondsSince1970: sqlite3_column_int64(statement, 3))
        else {
            throw SQLitePersistenceError.invalidStoredValue("message")
        }

        let senderID = try decodeOptionalParticipantID(columnText(statement, at: 2), field: "messages.sender_id")
        let fromMeValue = sqlite3_column_int64(statement, 5)
        guard fromMeValue == 0 || fromMeValue == 1 else {
            throw SQLitePersistenceError.invalidStoredValue("messages.from_me")
        }

        let quote: WhatsAppQuote?
        if let rawQuoteMessageID = columnText(statement, at: 6) {
            guard let quoteMessageID = WhatsAppMessageID(rawQuoteMessageID) else {
                throw SQLitePersistenceError.invalidStoredValue("messages.quote_message_id")
            }
            quote = WhatsAppQuote(
                messageID: quoteMessageID,
                senderID: try decodeOptionalParticipantID(
                    columnText(statement, at: 7),
                    field: "messages.quote_sender_id"
                ),
                body: columnText(statement, at: 8)
            )
        } else {
            guard columnText(statement, at: 7) == nil, columnText(statement, at: 8) == nil else {
                throw SQLitePersistenceError.invalidStoredValue("messages.quote")
            }
            quote = nil
        }

        let media: WhatsAppMediaMetadata?
        if let rawMediaKind = columnText(statement, at: 9) {
            guard let mediaKind = decodeMediaKind(rawMediaKind) else {
                throw SQLitePersistenceError.invalidStoredValue("messages.media_kind")
            }
            let sizeBytes = try optionalNonNegativeInt64(statement, at: 12, field: "messages.media_size_bytes")
            let duration = try optionalNonNegativeInt64(statement, at: 13, field: "messages.media_duration_ms")
            let width = try optionalNonNegativeInt(statement, at: 14, field: "messages.media_width")
            let height = try optionalNonNegativeInt(statement, at: 15, field: "messages.media_height")
            guard let decoded = WhatsAppMediaMetadata(
                kind: mediaKind,
                mimeType: columnText(statement, at: 10),
                filename: columnText(statement, at: 11),
                sizeBytes: sizeBytes,
                durationMilliseconds: duration,
                width: width,
                height: height
            ) else {
                throw SQLitePersistenceError.invalidStoredValue("messages.media")
            }
            media = decoded
        } else {
            let hasOrphanedMediaMetadata = (10...15).contains {
                sqlite3_column_type(statement, Int32($0)) != SQLITE_NULL
            }
            guard !hasOrphanedMediaMetadata else {
                throw SQLitePersistenceError.invalidStoredValue("messages.media")
            }
            media = nil
        }

        return WhatsAppMessage(
            id: messageID,
            chatID: chatID,
            senderID: senderID,
            timestamp: timestamp,
            body: columnText(statement, at: 4),
            fromMe: fromMeValue == 1,
            quote: quote,
            media: media,
            translation: nil
        )
    }

    private func decodeOptionalParticipantID(_ raw: String?, field: String) throws -> WhatsAppParticipantID? {
        guard let raw else { return nil }
        guard let id = WhatsAppParticipantID(raw) else {
            throw SQLitePersistenceError.invalidStoredValue(field)
        }
        return id
    }

    private func optionalNonNegativeInt64(
        _ statement: OpaquePointer,
        at index: Int32,
        field: String
    ) throws -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_int64(statement, index)
        guard value >= 0 else { throw SQLitePersistenceError.invalidStoredValue(field) }
        return value
    }

    private func optionalNonNegativeInt(
        _ statement: OpaquePointer,
        at index: Int32,
        field: String
    ) throws -> Int? {
        guard let value = try optionalNonNegativeInt64(statement, at: index, field: field) else { return nil }
        guard value <= Int64(Int.max) else { throw SQLitePersistenceError.invalidStoredValue(field) }
        return Int(value)
    }

    private func encode(_ kind: WhatsAppChatKind) -> String {
        switch kind {
        case .direct: "direct"
        case .group: "group"
        }
    }

    private func decodeChatKind(_ value: String) -> WhatsAppChatKind? {
        switch value {
        case "direct": .direct
        case "group": .group
        default: nil
        }
    }

    private func encode(_ kind: WhatsAppMediaKind) -> String {
        switch kind {
        case .image: "image"
        case .video: "video"
        case .audio: "audio"
        case .document: "document"
        case .sticker: "sticker"
        case .other: "other"
        }
    }

    private func decodeMediaKind(_ value: String) -> WhatsAppMediaKind? {
        switch value {
        case "image": .image
        case "video": .video
        case "audio": .audio
        case "document": .document
        case "sticker": .sticker
        case "other": .other
        default: nil
        }
    }

    private func pragmaUserVersion() throws -> Int32 {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else { throw sqliteError(code: result) }
        return sqlite3_column_int(statement, 0)
    }

    private func execute(_ sql: String) throws {
        try locked { try executeUnlocked(sql) }
    }

    private func executeUnlocked(_ sql: String) throws {
        guard let db else { throw SQLitePersistenceError.openFailed("closed") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw SQLitePersistenceError.sqlite(code: result, message: message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw SQLitePersistenceError.openFailed("closed") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw sqliteError(code: result) }
        return statement
    }

    private func bindText(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        guard result == SQLITE_OK else { throw sqliteError(code: result) }
    }

    private func bindOptionalText(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        if let value {
            try bindText(value, at: index, to: statement)
        } else {
            let result = sqlite3_bind_null(statement, index)
            guard result == SQLITE_OK else { throw sqliteError(code: result) }
        }
    }

    private func bindInt64(_ value: Int64, at index: Int32, to statement: OpaquePointer) throws {
        let result = sqlite3_bind_int64(statement, index, value)
        guard result == SQLITE_OK else { throw sqliteError(code: result) }
    }

    private func bindOptionalInt64(_ value: Int64?, at index: Int32, to statement: OpaquePointer) throws {
        if let value {
            try bindInt64(value, at: index, to: statement)
        } else {
            let result = sqlite3_bind_null(statement, index)
            guard result == SQLITE_OK else { throw sqliteError(code: result) }
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw sqliteError(code: result) }
    }

    private func columnText(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: text)
    }

    private func sqliteError(code: Int32) -> SQLitePersistenceError {
        guard let db else { return .sqlite(code: code, message: "closed") }
        return .sqlite(code: code, message: String(cString: sqlite3_errmsg(db)))
    }

    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
