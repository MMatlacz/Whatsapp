import Foundation
import Observation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
#if SWIFT_PACKAGE
import PersistenceCore
import WhatsAppDomainCore
#endif

enum NativeAutomaticTranslationEligibility {
    private static let strongIndonesianTokens: Set<String> = [
        "nggak", "gak", "udah", "belum", "nanti", "makasih", "wkwk", "mager", "baper",
        "dong", "sih", "nih", "kok", "besok", "banget", "aja", "gimana", "kenapa",
        "minum", "makan"
    ]
    private static let supportingIndonesianTokens: Set<String> = [
        "aku", "kamu", "dia", "iya", "ya", "ga", "sudah", "mau", "bisa", "boleh",
        "jadi", "kita", "kami", "mereka", "jangan", "lagi", "tolong", "terima", "kasih",
        "jam", "dari", "untuk", "dengan", "kalau", "tapi", "juga"
    ]

    static func allows(message: WhatsAppTransportMessage, body: String) -> Bool {
        guard !message.fromMe else { return false }
        return allows(body: body)
    }

    static func allows(body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.contains(where: CharacterSet.letters.contains),
              !isURLOnly(trimmed) else { return false }

        let tokens = trimmed.lowercased().split { !$0.isLetter }.map(String.init)
        if tokens.contains(where: strongIndonesianTokens.contains) { return true }

        let supportingCount = tokens.reduce(into: 0) { count, token in
            if supportingIndonesianTokens.contains(token) { count += 1 }
        }
        if supportingCount >= 2 { return true }

        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        if recognizer.dominantLanguage == .indonesian { return true }
        let confidence = recognizer.languageHypotheses(withMaximum: 3)[.indonesian] ?? 0
        if confidence >= 0.55 { return true }
        #endif

        return false
    }

    private static func isURLOnly(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy { token in
            let value = token.lowercased()
            return value.hasPrefix("https://") || value.hasPrefix("http://")
        }
    }
}

struct NativeContactIdentity: Equatable, Sendable {
    let name: String?
    let photo: Data?
}

protocol NativeContactIdentityProvider: Sendable {
    func identity(for id: String) async throws -> NativeContactIdentity
}

@available(iOS 17, macOS 14, *)
@MainActor @Observable
final class NativeChatModel {
    private struct PendingSend: Equatable {
        let body: String
        let quoteID: String?
        let knownMessageIDs: Set<String>
        let attemptStartedMilliseconds: Int64
    }

    let translations: NativeTranslationModel
    let automaticTranslationSettings: AutomaticTranslationSettingsStore
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
    /// A send with an unknown final outcome blocks another send until a fresh
    /// history read or an explicit user resolution prevents duplication.
    private(set) var uncertainSends: Set<String> = []
    private(set) var historyCheckedAfterUncertainSends: Set<String> = []
    private(set) var storageNotice: String?
    private(set) var identities: [String: NativeContactIdentity] = [:]
    private(set) var mediaPreviews: [MediaPreviewKey: WhatsAppTransportMediaPreview] = [:]
    @ObservationIgnored private var identityProvider: (any NativeContactIdentityProvider)?
    @ObservationIgnored private var loadingIdentities: Set<String> = []
    @ObservationIgnored private var loadedIdentityIDs: Set<String> = []
    @ObservationIgnored private var identityOrder: [String] = []
    @ObservationIgnored private var mediaPreviewLoader: MediaPreviewLoader?
    var drafts: [String: String] = [:]
    var quotes: [String: WhatsAppTransportMessage] = [:]
    var errors: [String: String] = [:]
    var search = "" { didSet { updateFilter() } }
    var filter: Filter = .all { didSet { updateFilter() } }
    @ObservationIgnored private var transport: (any WhatsAppTransport)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var eventStreamGeneration = UUID()
    @ObservationIgnored private var store: SQLiteWhatsAppStore?
    @ObservationIgnored private var pendingSends: [String: PendingSend] = [:]
    @ObservationIgnored private var loadedCachedHistory: Set<String> = []
    @ObservationIgnored private var draftSaveTasks: [String: Task<Void, Never>] = [:]

    init(transport: (any WhatsAppTransport)? = nil, translations: NativeTranslationModel? = nil,
         store: SQLiteWhatsAppStore? = nil,
         identityProvider: (any NativeContactIdentityProvider)? = nil,
         automaticTranslationSettings: AutomaticTranslationSettingsStore? = nil) {
        self.transport = transport
        self.translations = translations ?? NativeTranslationModel()
        self.automaticTranslationSettings = automaticTranslationSettings ?? AutomaticTranslationSettingsStore()
        self.store = store
        self.identityProvider = identityProvider
        if let transport {
            self.mediaPreviewLoader = MediaPreviewLoader { key in
                try await transport.mediaPreview(
                    chatID: key.chatID,
                    messageID: key.messageID,
                    purpose: key.purpose,
                    maxPixelSize: key.requestedPixelSize
                )
            }
        } else {
            self.mediaPreviewLoader = nil
        }
        do {
            drafts = try store?.drafts() ?? [:]
            chats = try store?.chats().map(WhatsAppTransportDomainMapper.transportChat) ?? []
            if let store {
                // Keep one cached message per chat available for list previews after
                // relaunch. The full history remains loaded on demand.
                for chat in chats {
                    guard let id = WhatsAppChatID(chat.id),
                          let page = try? store.messages(chatID: id, before: nil, limit: 1),
                          !page.messages.isEmpty else { continue }
                    let cached = page.messages.map(WhatsAppTransportDomainMapper.transportMessage)
                    messages[chat.id] = cached.sorted {
                        $0.timestampMilliseconds == $1.timestampMilliseconds
                            ? $0.id < $1.id : $0.timestampMilliseconds < $1.timestampMilliseconds
                    }
                    for message in cached {
                        cacheStoredIdentity(message.senderID, in: store)
                        cacheStoredIdentity(message.quote?.senderID, in: store)
                    }
                }
                for (chatID, messageID) in try store.replyTargets() {
                    guard let chat = WhatsAppChatID(chatID), let message = WhatsAppMessageID(messageID),
                          let stored = try store.message(chatID: chat, messageID: message) else { continue }
                    quotes[chatID] = WhatsAppTransportDomainMapper.transportMessage(stored)
                }
                for stored in try store.pendingSends() {
                    pendingSends[stored.chatID] = PendingSend(
                        body: stored.body,
                        quoteID: stored.quoteMessageID,
                        knownMessageIDs: stored.knownMessageIDs,
                        attemptStartedMilliseconds: stored.attemptStartedMilliseconds
                    )
                    uncertainSends.insert(stored.chatID)
                    if stored.historyChecked { historyCheckedAfterUncertainSends.insert(stored.chatID) }
                    errors[stored.chatID] = stored.historyChecked
                        ? "Previous send was not found in refreshed history. Check WhatsApp before allowing a retry."
                        : "A previous send may already have been delivered. Refresh history before retrying."
                }
            }
            updateFilter()
        }
        catch { storageNotice = "Saved drafts could not be loaded. Local storage needs attention." }
    }

    static func applicationModel(transport: any WhatsAppTransport,
                                 retranslator: (any NativeRetranslator)? = nil,
                                 identityProvider: (any NativeContactIdentityProvider)? = nil) -> NativeChatModel {
        do {
            var folder = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("NativeChats", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            let databaseURL = folder.appendingPathComponent("chats.sqlite")
            #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
            #endif
            let store = try SQLiteWhatsAppStore(path: databaseURL.path)
            #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: databaseURL.path)
            #endif
            return NativeChatModel(transport: transport,
                                   translations: .applicationStore(retranslator: retranslator), store: store,
                                   identityProvider: identityProvider,
                                   automaticTranslationSettings: .applicationStore())
        } catch {
            let model = NativeChatModel(transport: transport,
                                        translations: .applicationStore(retranslator: retranslator),
                                        identityProvider: identityProvider,
                                        automaticTranslationSettings: .applicationStore())
            model.storageNotice = "Local storage is unavailable. Drafts will not survive closing the app."
            return model
        }
    }

    func loadIdentity(for id: String) async {
        guard connectionState == .ready, !loadedIdentityIDs.contains(id),
              !loadingIdentities.contains(id), let identityProvider else { return }
        loadingIdentities.insert(id)
        defer { loadingIdentities.remove(id) }
        guard let identity = try? await identityProvider.identity(for: id) else { return }
        loadedIdentityIDs.insert(id)
        identityOrder.removeAll { $0 == id }
        identityOrder.append(id)
        if identityOrder.count > 100 {
            let overflow = identityOrder.count - 100
            let evicted = Array(identityOrder.prefix(overflow))
            identityOrder.removeFirst(overflow)
            for oldID in evicted {
                identities.removeValue(forKey: oldID)
                loadedIdentityIDs.remove(oldID)
            }
        }
        identities[id] = identity
        if let store, let participantID = WhatsAppParticipantID(id) {
            do {
                try store.upsert(participant: .init(id: participantID, displayName: identity.name))
            } catch {
                storageNotice = "Contact details could not be cached. Live messages remain available."
            }
        }
    }

    func mediaPreviewKey(for message: WhatsAppTransportMessage) -> MediaPreviewKey? {
        let previewableAttachment = message.media.map {
            $0.kind == .image || $0.kind == .sticker
        } ?? false
        if previewableAttachment {
            return MediaPreviewKey(
                chatID: message.chatID,
                messageID: message.id,
                purpose: .attachment,
                requestedPixelSize: 768
            )
        }
        if message.linkPreview != nil {
            return MediaPreviewKey(
                chatID: message.chatID,
                messageID: message.id,
                purpose: .linkPreview,
                requestedPixelSize: 320
            )
        }
        return nil
    }

    func loadMediaPreview(for message: WhatsAppTransportMessage) async {
        guard connectionState == .ready,
              let key = mediaPreviewKey(for: message),
              mediaPreviews[key] == nil,
              let mediaPreviewLoader else { return }

        let state = await mediaPreviewLoader.load(
            key,
            isViewOnce: message.media?.isViewOnce == true,
            priority: .visible
        )
        guard !Task.isCancelled, case .ready(let preview) = state else { return }
        mediaPreviews[key] = preview
    }

    func releaseMediaPreview(for message: WhatsAppTransportMessage) {
        guard let key = mediaPreviewKey(for: message) else { return }
        mediaPreviews.removeValue(forKey: key)
    }

    func purgeEncodedMediaPreviewCache() async {
        mediaPreviews.removeAll(keepingCapacity: true)
        await mediaPreviewLoader?.purgeEncodedCache()
    }

    func encodedMediaPreviewCacheStats() async -> ByteCostLRUCacheStats {
        await mediaPreviewLoader?.encodedCacheStats() ?? .init(entryCount: 0, totalCostBytes: 0)
    }

    func setGlobalAutomaticTranslationEnabled(_ enabled: Bool) {
        automaticTranslationSettings.setGlobalEnabled(enabled)
    }

    func automaticTranslationOverride(for chatID: String) -> AutomaticTranslationOverride {
        automaticTranslationSettings.override(for: chatID)
    }

    func setAutomaticTranslationOverride(_ value: AutomaticTranslationOverride, for chatID: String) {
        automaticTranslationSettings.setOverride(value, for: chatID)
    }

    func automaticTranslationEnabled(for chatID: String) -> Bool {
        automaticTranslationSettings.effectiveEnabled(for: chatID)
    }

    subscript(draft chatID: String) -> String {
        get { drafts[chatID] ?? "" }
        set {
            drafts[chatID] = newValue
            if draftSaveTasks[chatID] == nil {
                persistDraftNow(chatID: chatID, body: newValue)
            }
            scheduleDraftSave(chatID: chatID, body: newValue)
        }
    }

    private func scheduleDraftSave(chatID: String, body: String) {
        draftSaveTasks[chatID]?.cancel()
        guard store != nil else { return }
        draftSaveTasks[chatID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persistDraftNow(chatID: chatID, body: body)
        }
    }

    private func persistDraftNow(chatID: String, body: String) {
        draftSaveTasks[chatID]?.cancel()
        draftSaveTasks.removeValue(forKey: chatID)
        guard let store, let id = WhatsAppChatID(chatID) else { return }
        do {
            try store.saveDraft(body, chatID: id)
            storageNotice = nil
        } catch {
            storageNotice = "Draft could not be saved. Keep the app open and copy your text before closing."
        }
    }

    func setReply(_ message: WhatsAppTransportMessage?, chatID: String) {
        quotes[chatID] = message
        guard let store, let id = WhatsAppChatID(chatID) else { return }
        do {
            try store.saveReplyTarget(message?.id, chatID: id)
            storageNotice = nil
        } catch {
            storageNotice = "Reply context could not be saved. Keep the app open until sending."
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
                let generation = UUID()
                eventStreamGeneration = generation
                eventTask = Task { [weak self] in
                    for await event in stream {
                        guard !Task.isCancelled else { break }
                        await self?.handle(event)
                    }
                    self?.eventStreamEnded(generation: generation)
                }
            }
            for _ in 0..<30 {
                try Task.checkCancellation()
                connectionState = try await transport.connectionState()
                if connectionState == .ready {
                    chats = try await transport.listChats()
                    cacheChats()
                    connectionNotice = nil
                    updateFilter()
                    return
                }
                if connectionState == .authenticating {
                    connectionNotice = "The saved session needs linking. Choose Link WhatsApp to continue."
                    return
                }
                try await Task.sleep(for: .seconds(1))
            }
            connectionNotice = connectionState == .syncing
                ? "WhatsApp is still synchronizing. Check connection details before retrying."
                : "WhatsApp did not finish connecting. Check connection details; reconnect reloads the page without unlinking."
        } catch {
            connectionState = .disconnected
            connectionNotice = "Could not connect the hidden transport. Your saved session is preserved. Retry to reconnect."
            throw error
        }
    }

    func reconnect() async {
        do { try await connect() } catch { /* User-visible status is set by connect. */ }
    }

    /// Reconciles a pairing transition that can complete between WA-JS event
    /// subscription and the primary phone returning this app to the foreground.
    /// This reads the existing session and never reloads or clears its profile.
    func refreshConnectionAfterPairing() async {
        guard let transport, !isConnecting else { return }
        do {
            connectionState = try await transport.connectionState()
            guard connectionState == .ready else { return }
            chats = try await transport.listChats()
            cacheChats()
            connectionNotice = nil
            updateFilter()
        } catch {
            connectionState = .disconnected
            connectionNotice = "Connection readiness could not be confirmed. Reconnect before sending."
        }
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
            let durable = merge([message], in: message.chatID)
            enqueueAutomaticTranslations(durable)
            if case .message = event {
                updateChatLastMessage(for: message)
                reconcilePendingSend(for: message.chatID, historyWasRefreshed: false)
            }
        case .chatUpdate(let chat):
            chats.removeAll { $0.id == chat.id }
            chats.append(chat)
            cacheChats()
            updateFilter()
        case .disconnected:
            connectionState = .disconnected
            connectionNotice = "Connection interrupted. Your drafts are kept; reconnect before sending."
        case .historySync(let chatID, let incoming, let cursor):
            let durable = merge(incoming, in: chatID)
            enqueueAutomaticTranslations(durable)
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

    func title(for chatID: String) -> String {
        guard let chat = chats.first(where: { $0.id == chatID }) else { return "Chat" }
        return chat.isGroup ? chat.title : identities[chatID]?.name ?? chat.title
    }
    func translationKey(
        chatID: String,
        messageID: String,
        forceIndonesian: Bool = false
    ) -> NativeTranslationKey {
        let sourceLanguage: String
        if isSample && messageID == "\(chatID)-1" {
            sourceLanguage = "id"
        } else if forceIndonesian {
            sourceLanguage = "id"
        } else if let message = messages[chatID]?.first(where: { $0.id == messageID }),
                  let body = message.body,
                  NativeAutomaticTranslationEligibility.allows(message: message, body: body) {
            sourceLanguage = "id"
        } else {
            sourceLanguage = "und"
        }
        return .init(
            chatID: chatID,
            messageID: messageID,
            sourceLanguage: sourceLanguage,
            targetLanguage: "pl"
        )
    }
    func preview(for chatID: String) -> String {
        guard let message = messages[chatID]?.last, let body = message.body else {
            return "Open conversation"
        }
        guard chats.first(where: { $0.id == chatID })?.isGroup == true,
              !message.fromMe, let senderID = message.senderID else { return body }
        let sender = identities[senderID]?.name ?? "Group participant"
        return "\(sender): \(body)"
    }

    func canSend(chatID: String) -> Bool {
        (isSample || connectionState == .ready) && chats.contains { $0.id == chatID }
            && !sending.contains(chatID)
            && !uncertainSends.contains(chatID)
            && !(drafts[chatID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load(chatID: String, older: Bool = false) async {
        guard !isSample, !loadingHistory.contains(chatID) else { return }
        if !older, !loadedCachedHistory.contains(chatID), let store, let id = WhatsAppChatID(chatID) {
            do {
                let page = try store.messages(chatID: id, before: nil, limit: 100)
                let cached = merge(
                    page.messages.map(WhatsAppTransportDomainMapper.transportMessage),
                    in: chatID,
                    persist: false
                )
                enqueueAutomaticTranslations(cached)
                loadedCachedHistory.insert(chatID)
            } catch { storageNotice = "Cached messages could not be loaded." }
        }
        guard let transport, connectionState == .ready else { return }
        if older, historyCursors[chatID] == nil { return }
        loadingHistory.insert(chatID)
        defer { loadingHistory.remove(chatID) }
        do {
            let page = try await transport.loadMessages(chatID: chatID,
                                                        cursor: older ? historyCursors[chatID] : nil, limit: 100)
            let durable = merge(page.messages, in: chatID)
            enqueueAutomaticTranslations(durable)
            historyCursors[chatID] = page.nextCursor
            if !older { reconcilePendingSend(for: chatID, historyWasRefreshed: true) }
            if !uncertainSends.contains(chatID) { errors[chatID] = nil }
        } catch {
            errors[chatID] = "Could not load messages. Reopen this conversation to retry."
        }
    }

    func send(chatID: String) async {
        guard canSend(chatID: chatID) else { return }
        let draft = drafts[chatID] ?? ""
        persistDraftNow(chatID: chatID, body: draft)
        let quote = quotes[chatID]
        let knownMessageIDs = Set(messages[chatID, default: []].map(\.id))
        let attemptStartedMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
        let pending = PendingSend(body: draft, quoteID: quote?.id, knownMessageIDs: knownMessageIDs,
                                  attemptStartedMilliseconds: attemptStartedMilliseconds)
        pendingSends[chatID] = pending
        uncertainSends.insert(chatID)
        historyCheckedAfterUncertainSends.remove(chatID)
        guard persistPendingSend(pending, chatID: chatID, historyChecked: false) else {
            pendingSends.removeValue(forKey: chatID)
            uncertainSends.remove(chatID)
            errors[chatID] = "Send was not started because its recovery record could not be saved."
            return
        }
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
            if quotes[chatID]?.id == quote?.id { setReply(nil, chatID: chatID) }
            clearPendingSend(chatID: chatID)
            errors[chatID] = nil
        } catch {
            // The incoming event can race a failed bridge confirmation. Check
            // the in-memory history before presenting a retry lock.
            reconcilePendingSend(for: chatID, historyWasRefreshed: false)
            guard uncertainSends.contains(chatID) else { return }
            errors[chatID] = "Send could not be confirmed. Your draft is kept. Check the conversation before retrying."
        }
    }

    /// Release the retry lock only after the user has refreshed the chat and
    /// explicitly decided that the uncertain message is safe to resend.
    func resolveUncertainSend(chatID: String) {
        guard uncertainSends.contains(chatID),
              historyCheckedAfterUncertainSends.contains(chatID) else { return }
        uncertainSends.remove(chatID)
        historyCheckedAfterUncertainSends.remove(chatID)
        pendingSends.removeValue(forKey: chatID)
        if let store, let id = WhatsAppChatID(chatID) {
            do { try store.deletePendingSend(chatID: id) }
            catch { storageNotice = "The send recovery record could not be cleared." }
        }
        errors[chatID] = nil
    }

    private func persistPendingSend(_ pending: PendingSend, chatID: String, historyChecked: Bool) -> Bool {
        guard let store, let id = WhatsAppChatID(chatID) else { return isSample }
        do {
            try store.savePendingSend(.init(
                chatID: id.rawValue, body: pending.body, quoteMessageID: pending.quoteID,
                knownMessageIDs: pending.knownMessageIDs,
                attemptStartedMilliseconds: pending.attemptStartedMilliseconds,
                historyChecked: historyChecked
            ))
            return true
        } catch {
            storageNotice = "Send recovery state could not be saved. Sending is paused."
            return false
        }
    }

    private func clearPendingSend(chatID: String) {
        uncertainSends.remove(chatID)
        historyCheckedAfterUncertainSends.remove(chatID)
        pendingSends.removeValue(forKey: chatID)
        guard let store, let id = WhatsAppChatID(chatID) else { return }
        do { try store.deletePendingSend(chatID: id) }
        catch { storageNotice = "The send recovery record could not be cleared." }
    }

    private func cacheChat(_ chat: WhatsAppTransportChat) {
        guard let store, !isSample else { return }
        do { try store.upsert(chat: WhatsAppTransportDomainMapper.chat(chat)) }
        catch { storageNotice = "Chat cache could not be saved. Live content remains available." }
    }

    private func cacheChats() {
        guard let store, !isSample else { return }
        do {
            for chat in chats { try store.upsert(chat: WhatsAppTransportDomainMapper.chat(chat)) }
        } catch { storageNotice = "Chat cache could not be saved. Live content remains available." }
    }

    private func cacheStoredIdentity(_ id: String?, in store: SQLiteWhatsAppStore) {
        guard let id, identities[id] == nil, let participantID = WhatsAppParticipantID(id),
              let participant = try? store.participant(id: participantID),
              let name = participant.displayName, !name.isEmpty else { return }
        identities[id] = NativeContactIdentity(name: name, photo: nil)
    }

    private func eventStreamEnded(generation: UUID) {
        guard eventStreamGeneration == generation else { return }
        eventTask = nil
        guard connectionState != .ready else {
            connectionState = .disconnected
            connectionNotice = "Connection events stopped. Reconnect before sending."
            return
        }
        connectionNotice = connectionNotice ?? "Connection events stopped. Reconnect to reload chats."
    }

    private func updateChatLastMessage(for message: WhatsAppTransportMessage) {
        guard let index = chats.firstIndex(where: { $0.id == message.chatID }) else { return }
        let chat = chats[index]
        guard chat.lastMessageTimestampMilliseconds ?? 0 < message.timestampMilliseconds else { return }
        let updated = WhatsAppTransportChat(
            id: chat.id, title: chat.title, isGroup: chat.isGroup,
            unreadCount: chat.unreadCount,
            lastMessageTimestampMilliseconds: message.timestampMilliseconds
        )
        chats[index] = updated
        cacheChat(updated)
        updateFilter()
    }

    private func reconcilePendingSend(for chatID: String, historyWasRefreshed: Bool) {
        guard uncertainSends.contains(chatID), let pending = pendingSends[chatID] else { return }
        let matches = messages[chatID]?.contains { message in
            message.fromMe && !pending.knownMessageIDs.contains(message.id)
                && message.timestampMilliseconds >= pending.attemptStartedMilliseconds - 5_000
                && message.body == pending.body && message.quote?.messageID == pending.quoteID
        } == true
        if matches {
            clearPendingSend(chatID: chatID)
            if drafts[chatID] == pending.body { self[draft: chatID] = "" }
            if let quoteID = pending.quoteID, quotes[chatID]?.id == quoteID { setReply(nil, chatID: chatID) }
            errors[chatID] = nil
        } else if historyWasRefreshed {
            historyCheckedAfterUncertainSends.insert(chatID)
            _ = persistPendingSend(pending, chatID: chatID, historyChecked: true)
            errors[chatID] = "Previous send was not found in refreshed history. Check WhatsApp before allowing a retry."
        }
    }

    @discardableResult
    private func merge(
        _ incoming: [WhatsAppTransportMessage],
        in chatID: String,
        persist: Bool = true
    ) -> [WhatsAppTransportMessage] {
        let matching = incoming.filter { $0.chatID == chatID }
        var byID = Dictionary(
            (messages[chatID] ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { _, new in new }
        )
        for message in matching { byID[message.id] = message }

        var durableIDs: Set<String> = []
        if persist, !isSample, let store {
            do {
                for message in matching {
                    if let id = WhatsAppChatID(chatID), try store.chat(id: id) == nil,
                       let timestamp = WhatsAppTimestamp(millisecondsSince1970: message.timestampMilliseconds),
                       let placeholder = WhatsAppChat(
                           id: id,
                           title: chats.first(where: { $0.id == chatID })?.title ?? "Chat",
                           kind: chatID.hasSuffix("@g.us") ? .group : .direct,
                           unreadCount: 0,
                           lastMessageAt: timestamp
                       ) {
                        try store.upsert(chat: placeholder)
                    }
                    try store.upsert(message: WhatsAppTransportDomainMapper.message(message))
                    durableIDs.insert(message.id)
                }
            } catch {
                storageNotice = "Some messages could not be cached. Keep the app connected to reload them."
            }
        } else if !persist, !isSample, store != nil {
            // persist=false is used only for rows just read from SQLite; they
            // are already durable and may safely enter automatic translation.
            durableIDs.formUnion(matching.map(\.id))
        }

        messages[chatID] = byID.values.sorted {
            $0.timestampMilliseconds == $1.timestampMilliseconds
                ? $0.id < $1.id : $0.timestampMilliseconds < $1.timestampMilliseconds
        }
        return matching.filter { durableIDs.contains($0.id) }
    }

    private func enqueueAutomaticTranslations(_ messages: [WhatsAppTransportMessage]) {
        guard !isSample, translations.experimentalTranslationEnabled else { return }

        for message in messages {
            guard automaticTranslationEnabled(for: message.chatID),
                  let body = message.body,
                  NativeAutomaticTranslationEligibility.allows(message: message, body: body) else {
                continue
            }

            let key = NativeTranslationKey(
                chatID: message.chatID,
                messageID: message.id,
                sourceLanguage: "id",
                targetLanguage: "pl"
            )
            if let existing = translations.record(for: key, original: body),
               !existing.parts.isEmpty || !existing.comment.isEmpty {
                continue
            }

            let translationModel = translations
            Task { @MainActor in
                await translationModel.translate(key: key, original: body)
            }
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
