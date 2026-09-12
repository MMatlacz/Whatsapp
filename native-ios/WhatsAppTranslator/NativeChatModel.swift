import Foundation
import Observation
#if SWIFT_PACKAGE
import PersistenceCore
import WhatsAppDomainCore
#endif

@available(iOS 17, macOS 14, *)
@MainActor @Observable
final class NativeChatModel {
    let translations: NativeTranslationModel
    enum Filter { case all, unread, groups }
    private(set) var chats: [WhatsAppTransportChat] = []
    private(set) var visibleChats: [WhatsAppTransportChat] = []
    private(set) var messages: [String: [WhatsAppTransportMessage]] = [:]
    private(set) var isSample = false
    private(set) var sending: Set<String> = []
    private(set) var connectionState: WhatsAppTransportConnectionState = .disconnected
    private(set) var isConnecting = false
    private(set) var connectionNotice: String?
    private(set) var historyCursors: [String: WhatsAppTransportMessageCursor] = [:]
    private(set) var loadingHistory: Set<String> = []
    private(set) var storageNotice: String?
    var drafts: [String: String] = [:]
    var quotes: [String: WhatsAppTransportMessage] = [:]
    var errors: [String: String] = [:]
    var search = "" { didSet { updateFilter() } }
    var filter: Filter = .all { didSet { updateFilter() } }
    @ObservationIgnored private var transport: (any WhatsAppTransport)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var store: SQLiteWhatsAppStore?

    init(transport: (any WhatsAppTransport)? = nil, translations: NativeTranslationModel? = nil,
         store: SQLiteWhatsAppStore? = nil) {
        self.transport = transport
        self.translations = translations ?? NativeTranslationModel()
        self.store = store
        do {
            drafts = try store?.drafts() ?? [:]
            chats = try store?.chats().map(WhatsAppTransportDomainMapper.transportChat) ?? []
            updateFilter()
        }
        catch { storageNotice = "Saved drafts could not be loaded. Local storage needs attention." }
    }

    static func applicationModel(transport: any WhatsAppTransport) -> NativeChatModel {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("NativeChats", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = try SQLiteWhatsAppStore(path: folder.appendingPathComponent("chats.sqlite").path)
            return NativeChatModel(transport: transport, translations: .applicationStore(), store: store)
        } catch {
            let model = NativeChatModel(transport: transport, translations: .applicationStore())
            model.storageNotice = "Local storage is unavailable. Drafts will not survive closing the app."
            return model
        }
    }

    subscript(draft chatID: String) -> String {
        get { drafts[chatID] ?? "" }
        set {
            drafts[chatID] = newValue
            guard let store else { return }
            do {
                guard let id = WhatsAppChatID(chatID) else { return }
                try store.saveDraft(newValue, chatID: id)
                storageNotice = nil
            } catch {
                storageNotice = "Draft could not be saved. Keep the app open and copy your text before closing."
            }
        }
    }

    func connect() async throws {
        guard let transport, !isConnecting else { return }
        isConnecting = true
        connectionNotice = nil
        connectionState = .connecting
        defer { isConnecting = false }
        do {
            try await transport.connect()
            if eventTask == nil {
                let stream = await transport.eventStream()
                eventTask = Task { [weak self] in
                    for await event in stream {
                        guard !Task.isCancelled else { break }
                        await self?.handle(event)
                    }
                }
            }
            for _ in 0..<30 {
                try Task.checkCancellation()
                connectionState = try await transport.connectionState()
                if connectionState == .ready {
                    chats = try await transport.listChats()
                    cacheChats()
                    updateFilter()
                    return
                }
                if connectionState == .authenticating {
                    connectionNotice = "The saved session needs linking. Choose Link WhatsApp to continue."
                    return
                }
                try await Task.sleep(for: .seconds(1))
            }
            connectionNotice = "WhatsApp is still synchronizing. Retry to check again."
        } catch {
            connectionState = .disconnected
            connectionNotice = "Could not connect the hidden transport. Your saved session is preserved. Retry to reconnect."
            throw error
        }
    }

    func reconnect() async {
        do { try await connect() } catch { /* User-visible status is set by connect. */ }
    }

    private func handle(_ event: WhatsAppTransportEvent) async {
        switch event {
        case .ready:
            guard let transport else { return }
            do {
                connectionState = try await transport.connectionState()
                guard connectionState == .ready else { return }
                let updated = try await transport.listChats()
                chats = updated
                cacheChats()
                connectionNotice = nil
                updateFilter()
            } catch {
                connectionState = .disconnected
                connectionNotice = "Connection readiness could not be confirmed. Reconnect before sending."
            }
        case .message(let message), .messageUpdate(let message):
            merge([message], in: message.chatID)
        case .chatUpdate(let chat):
            chats.removeAll { $0.id == chat.id }
            chats.append(chat)
            cacheChats()
            updateFilter()
        case .disconnected:
            connectionState = .disconnected
            connectionNotice = "Connection interrupted. Your drafts are kept; reconnect before sending."
        case .historySync(let chatID, let incoming, let cursor):
            merge(incoming, in: chatID)
            historyCursors[chatID] = cursor
        }
    }

    func openSamples() {
        guard !isSample, transport == nil else { return }
        isSample = true
        let time = Int64(Date().timeIntervalSince1970 * 1_000)
        chats = [
            .init(id: "sample-alex", title: "Alex · Sample", isGroup: false,
                  unreadCount: 2, lastMessageTimestampMilliseconds: time),
            .init(id: "sample-weekend", title: "Weekend plans · Sample", isGroup: true,
                  unreadCount: 0, lastMessageTimestampMilliseconds: time - 60_000),
            .init(id: "sample-notes", title: "Notes · Sample", isGroup: false,
                  unreadCount: 0, lastMessageTimestampMilliseconds: time - 120_000)
        ]
        for chat in chats {
            messages[chat.id] = [
                sampleMessage(id: "\(chat.id)-1", chatID: chat.id,
                              body: "Aku minum kopi.", fromMe: false),
                sampleMessage(id: "\(chat.id)-2", chatID: chat.id,
                              body: "Try typing a message or long-press a bubble to reply.", fromMe: false)
            ]
            translations.seedSample(
                key: translationKey(chatID: chat.id, messageID: "\(chat.id)-1"),
                original: "Aku minum kopi.", parts: [
                    .init(id: "verb", source: "Aku minum", translation: "Piję"),
                    .init(id: "space", source: nil, translation: " "),
                    .init(id: "coffee", source: "kopi", translation: "kawę"),
                    .init(id: "period", source: nil, translation: ".")
                ]
            )
        }
        updateFilter()
    }

    func title(for chatID: String) -> String { chats.first { $0.id == chatID }?.title ?? "Chat" }
    func translationKey(chatID: String, messageID: String) -> NativeTranslationKey {
        .init(chatID: chatID, messageID: messageID,
              sourceLanguage: isSample && messageID == "\(chatID)-1" ? "id" : "und", targetLanguage: "pl")
    }
    func preview(for chatID: String) -> String { messages[chatID]?.last?.body ?? "Open conversation" }

    func canSend(chatID: String) -> Bool {
        (isSample || connectionState == .ready) && chats.contains { $0.id == chatID }
            && !sending.contains(chatID)
            && !(drafts[chatID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load(chatID: String, older: Bool = false) async {
        guard !isSample, !loadingHistory.contains(chatID) else { return }
        if !older, messages[chatID] == nil, let store, let id = WhatsAppChatID(chatID) {
            do {
                let page = try store.messages(chatID: id, before: nil, limit: 100)
                merge(page.messages.map(WhatsAppTransportDomainMapper.transportMessage), in: chatID, persist: false)
            } catch { storageNotice = "Cached messages could not be loaded." }
        }
        guard let transport, connectionState == .ready else { return }
        if older, historyCursors[chatID] == nil { return }
        loadingHistory.insert(chatID)
        defer { loadingHistory.remove(chatID) }
        do {
            let page = try await transport.loadMessages(chatID: chatID,
                                                        cursor: older ? historyCursors[chatID] : nil, limit: 100)
            merge(page.messages, in: chatID)
            historyCursors[chatID] = page.nextCursor
            errors[chatID] = nil
        } catch {
            errors[chatID] = "Could not load messages. Reopen this conversation to retry."
        }
    }

    func send(chatID: String) async {
        guard canSend(chatID: chatID) else { return }
        let draft = drafts[chatID] ?? ""
        let quote = quotes[chatID]
        sending.insert(chatID)
        defer { sending.remove(chatID) }
        do {
            let message: WhatsAppTransportMessage
            if isSample {
                message = sampleMessage(id: UUID().uuidString, chatID: chatID, body: draft,
                                        fromMe: true, quote: quote)
            } else if let transport {
                if let quote {
                    message = try await transport.reply(draft, to: quote.id, in: chatID)
                } else {
                    message = try await transport.sendText(draft, to: chatID)
                }
            } else { return }
            guard message.chatID == chatID, message.fromMe else {
                errors[chatID] = "The transport returned an unexpected result. Check the conversation before retrying."
                return
            }
            merge([message], in: chatID)
            if drafts[chatID] == draft { self[draft: chatID] = "" }
            if quotes[chatID]?.id == quote?.id { quotes[chatID] = nil }
            errors[chatID] = nil
        } catch {
            errors[chatID] = "Send could not be confirmed. Your draft is kept. Check the conversation before retrying."
        }
    }

    private func cacheChats() {
        guard let store, !isSample else { return }
        do {
            for chat in chats { try store.upsert(chat: WhatsAppTransportDomainMapper.chat(chat)) }
        } catch { storageNotice = "Chat cache could not be saved. Live content remains available." }
    }

    private func merge(_ incoming: [WhatsAppTransportMessage], in chatID: String, persist: Bool = true) {
        var byID = Dictionary((messages[chatID] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for message in incoming where message.chatID == chatID { byID[message.id] = message }
        if persist, !isSample, let store {
            do {
                for message in incoming where message.chatID == chatID {
                    try store.upsert(message: WhatsAppTransportDomainMapper.message(message))
                }
            } catch { storageNotice = "Some messages could not be cached. Keep the app connected to reload them." }
        }
        messages[chatID] = byID.values.sorted {
            $0.timestampMilliseconds == $1.timestampMilliseconds
                ? $0.id < $1.id : $0.timestampMilliseconds < $1.timestampMilliseconds
        }
    }

    private func updateFilter() {
        chats.sort { ($0.lastMessageTimestampMilliseconds ?? 0) > ($1.lastMessageTimestampMilliseconds ?? 0) }
        visibleChats = chats.filter {
            (search.isEmpty || $0.title.localizedStandardContains(search))
                && (filter != .unread || $0.unreadCount > 0)
                && (filter != .groups || $0.isGroup)
        }
    }

    private func sampleMessage(
        id: String, chatID: String, body: String, fromMe: Bool,
        quote: WhatsAppTransportMessage? = nil
    ) -> WhatsAppTransportMessage {
        .init(id: id, chatID: chatID, senderID: nil,
              timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
              body: body, fromMe: fromMe,
              quote: quote.map { .init(messageID: $0.id, senderID: $0.senderID, body: $0.body) }, media: nil)
    }
}
