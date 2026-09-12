import Foundation
import Observation

@available(iOS 17, macOS 14, *)
@MainActor @Observable
final class NativeChatModel {
    enum Filter { case all, unread, groups }
    private(set) var chats: [WhatsAppTransportChat] = []
    private(set) var visibleChats: [WhatsAppTransportChat] = []
    private(set) var messages: [String: [WhatsAppTransportMessage]] = [:]
    private(set) var isSample = false
    private(set) var sending: Set<String> = []
    var drafts: [String: String] = [:]
    var quotes: [String: WhatsAppTransportMessage] = [:]
    var errors: [String: String] = [:]
    var search = "" { didSet { updateFilter() } }
    var filter: Filter = .all { didSet { updateFilter() } }
    @ObservationIgnored private var transport: (any WhatsAppTransport)?

    init(transport: (any WhatsAppTransport)? = nil) {
        self.transport = transport
    }

    subscript(draft chatID: String) -> String {
        get { drafts[chatID] ?? "" }
        set { drafts[chatID] = newValue }
    }

    func connect() async throws {
        guard let transport else { return }
        try await transport.connect()
        chats = try await transport.listChats()
        updateFilter()
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
                              body: "These are local sample messages, not your WhatsApp history.", fromMe: false),
                sampleMessage(id: "\(chat.id)-2", chatID: chat.id,
                              body: "Try typing a message or long-press a bubble to reply.", fromMe: false)
            ]
        }
        updateFilter()
    }

    func title(for chatID: String) -> String { chats.first { $0.id == chatID }?.title ?? "Chat" }
    func preview(for chatID: String) -> String { messages[chatID]?.last?.body ?? "Open conversation" }

    func canSend(chatID: String) -> Bool {
        (isSample || transport != nil) && chats.contains { $0.id == chatID }
            && !sending.contains(chatID)
            && !(drafts[chatID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load(chatID: String) async {
        guard !isSample, let transport else { return }
        do {
            let page = try await transport.loadMessages(chatID: chatID, cursor: nil, limit: 100)
            merge(page.messages, in: chatID)
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
            if drafts[chatID] == draft { drafts[chatID] = "" }
            if quotes[chatID]?.id == quote?.id { quotes[chatID] = nil }
            errors[chatID] = nil
        } catch {
            errors[chatID] = "Send could not be confirmed. Your draft is kept. Check the conversation before retrying."
        }
    }

    private func merge(_ incoming: [WhatsAppTransportMessage], in chatID: String) {
        var byID = Dictionary((messages[chatID] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for message in incoming where message.chatID == chatID { byID[message.id] = message }
        messages[chatID] = byID.values.sorted {
            $0.timestampMilliseconds == $1.timestampMilliseconds
                ? $0.id < $1.id : $0.timestampMilliseconds < $1.timestampMilliseconds
        }
    }

    private func updateFilter() {
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
