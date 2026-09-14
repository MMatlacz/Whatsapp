import Foundation

enum WhatsAppTransportConnectionState: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case syncing
    case ready
}

/// Delivery state reported by WhatsApp's message ACK stream. `nil` means the
/// runtime did not provide an ACK, so callers must not infer a state from
/// message direction or a successful bridge response.
enum WhatsAppTransportDeliveryState: String, Codable, Equatable, Sendable {
    case pending
    case sent
    case delivered
    case read
    case played
    case failed

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .read: "Read"
        case .played: "Played"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "clock"
        case .sent: "checkmark"
        case .delivered: "checkmark.circle"
        case .read, .played: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle"
        }
    }
}

struct WhatsAppTransportChat: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let isGroup: Bool
    let unreadCount: Int
    let lastMessageTimestampMilliseconds: Int64?
}

struct WhatsAppTransportQuote: Codable, Equatable, Sendable {
    let messageID: String
    let senderID: String?
    let body: String?
}

enum WhatsAppTransportMediaKind: String, Codable, Equatable, Sendable {
    case image
    case video
    case audio
    case document
    case sticker
    case other
}

struct WhatsAppTransportMediaMetadata: Codable, Equatable, Sendable {
    let kind: WhatsAppTransportMediaKind
    let mimeType: String?
    let filename: String?
    let sizeBytes: Int64?
    let durationMilliseconds: Int64?
    let width: Int?
    let height: Int?
    let isViewOnce: Bool

    init(
        kind: WhatsAppTransportMediaKind, mimeType: String?, filename: String?,
        sizeBytes: Int64?, durationMilliseconds: Int64?, width: Int?, height: Int?,
        isViewOnce: Bool = false
    ) {
        self.kind = kind
        self.mimeType = mimeType
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.durationMilliseconds = durationMilliseconds
        self.width = width
        self.height = height
        self.isViewOnce = isViewOnce
    }

    private enum CodingKeys: String, CodingKey {
        case kind, mimeType, filename, sizeBytes, durationMilliseconds, width, height, isViewOnce
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(WhatsAppTransportMediaKind.self, forKey: .kind)
        mimeType = try values.decodeIfPresent(String.self, forKey: .mimeType)
        filename = try values.decodeIfPresent(String.self, forKey: .filename)
        sizeBytes = try values.decodeIfPresent(Int64.self, forKey: .sizeBytes)
        durationMilliseconds = try values.decodeIfPresent(Int64.self, forKey: .durationMilliseconds)
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
        isViewOnce = try values.decodeIfPresent(Bool.self, forKey: .isViewOnce) ?? false
    }
}

struct WhatsAppTransportLinkPreview: Codable, Equatable, Sendable {
    let matchedText: String
    let canonicalURL: String?
    let title: String?
    let description: String?
}

enum WhatsAppTransportMessageContentKind: String, Codable, Equatable, Sendable {
    case text
    case media
    case linkPreview
    case location
    case contact
    case poll
    case revoked
    case system
    case unsupported
}

struct WhatsAppTransportLocationContent: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let name: String?
    let address: String?
}

struct WhatsAppTransportContactCard: Codable, Equatable, Sendable {
    let displayName: String?
    let vCard: String
}

struct WhatsAppTransportPollContent: Codable, Equatable, Sendable {
    let question: String
    let options: [String]
}

struct WhatsAppTransportSystemContent: Codable, Equatable, Sendable {
    let type: String
    let text: String?
}

struct WhatsAppTransportMessageContent: Codable, Equatable, Sendable {
    let kind: WhatsAppTransportMessageContentKind
    let location: WhatsAppTransportLocationContent?
    let contacts: [WhatsAppTransportContactCard]?
    let poll: WhatsAppTransportPollContent?
    let system: WhatsAppTransportSystemContent?
    let rawType: String?

    init(
        kind: WhatsAppTransportMessageContentKind,
        location: WhatsAppTransportLocationContent? = nil,
        contacts: [WhatsAppTransportContactCard]? = nil,
        poll: WhatsAppTransportPollContent? = nil,
        system: WhatsAppTransportSystemContent? = nil,
        rawType: String? = nil
    ) {
        self.kind = kind
        self.location = location
        self.contacts = contacts
        self.poll = poll
        self.system = system
        self.rawType = rawType
    }
}

struct WhatsAppTransportMediaPreview: Codable, Equatable, Sendable {
    let mimeType: String
    let data: Data
    let width: Int?
    let height: Int?
}


enum MediaPreviewPurpose: String, Hashable, Sendable {
    case attachment
    case linkPreview
}

struct MediaPreviewKey: Hashable, Sendable {
    let chatID: String
    let messageID: String
    let purpose: MediaPreviewPurpose
    let requestedPixelSize: Int
}

enum MediaPreviewPriority: Int, Comparable, Sendable {
    case visible = 0
    case prefetch = 1

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ByteCostLRUCacheStats: Equatable, Sendable {
    let entryCount: Int
    let totalCostBytes: Int
}

struct ByteCostLRUCache<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var cost: Int
        var recency: UInt64
    }

    let softLimitBytes: Int
    let hardLimitBytes: Int
    private var entries: [Key: Entry] = [:]
    private var totalCost = 0
    private var recency: UInt64 = 0

    init(softLimitBytes: Int, hardLimitBytes: Int) {
        precondition(softLimitBytes >= 0 && hardLimitBytes >= softLimitBytes)
        self.softLimitBytes = softLimitBytes
        self.hardLimitBytes = hardLimitBytes
    }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        recency &+= 1
        entry.recency = recency
        entries[key] = entry
        return entry.value
    }

    @discardableResult
    mutating func insert(_ value: Value, for key: Key, costBytes: Int) -> [Key] {
        guard costBytes >= 0, costBytes <= hardLimitBytes else { return [] }
        if let previous = entries.removeValue(forKey: key) {
            totalCost -= previous.cost
        }
        recency &+= 1
        entries[key] = Entry(value: value, cost: costBytes, recency: recency)
        totalCost += costBytes

        guard totalCost > hardLimitBytes else { return [] }
        var evicted: [Key] = []
        while totalCost > softLimitBytes,
              let oldest = entries.min(by: { $0.value.recency < $1.value.recency }) {
            entries.removeValue(forKey: oldest.key)
            totalCost -= oldest.value.cost
            evicted.append(oldest.key)
        }
        return evicted
    }

    @discardableResult
    mutating func removeValue(for key: Key) -> Value? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        totalCost -= entry.cost
        return entry.value
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        totalCost = 0
    }

    func contains(_ key: Key) -> Bool { entries[key] != nil }

    var stats: ByteCostLRUCacheStats {
        .init(entryCount: entries.count, totalCostBytes: totalCost)
    }
}

enum MediaPreviewLoaderFailure: Error, Equatable, Sendable {
    case transport
}

enum MediaPreviewState: Equatable, Sendable {
    case idle
    case queued
    case loading
    case ready(WhatsAppTransportMediaPreview)
    case unavailable
    case failed(MediaPreviewLoaderFailure)
}

enum MediaPreviewCacheBudget {
    static let encodedSoftBytes = 32 * 1_024 * 1_024
    static let encodedHardBytes = 48 * 1_024 * 1_024
    static let decodedBytes = 24 * 1_024 * 1_024
}

actor MediaPreviewLoader {
    static let encodedCacheSoftLimitBytes = MediaPreviewCacheBudget.encodedSoftBytes
    static let encodedCacheHardLimitBytes = MediaPreviewCacheBudget.encodedHardBytes

    typealias Fetch = @Sendable (MediaPreviewKey) async throws -> WhatsAppTransportMediaPreview

    private struct Waiter {
        let continuation: CheckedContinuation<MediaPreviewState, Never>
    }

    private struct Request {
        var priority: MediaPreviewPriority
        let sequence: UInt64
        var waiters: [UUID: Waiter]
        var task: Task<Void, Never>?
    }

    private struct QueueEntry {
        let key: MediaPreviewKey
        var priority: MediaPreviewPriority
        let sequence: UInt64
    }

    private let maximumConcurrentRequests: Int
    private let fetch: Fetch
    private var sequence: UInt64 = 0
    private var requests: [MediaPreviewKey: Request] = [:]
    private var queue: [QueueEntry] = []
    private var running: Set<MediaPreviewKey> = []
    private var states: [MediaPreviewKey: MediaPreviewState] = [:]
    private var encodedCache = ByteCostLRUCache<MediaPreviewKey, WhatsAppTransportMediaPreview>(
        softLimitBytes: MediaPreviewLoader.encodedCacheSoftLimitBytes,
        hardLimitBytes: MediaPreviewLoader.encodedCacheHardLimitBytes
    )

    init(maximumConcurrentRequests: Int = 2, fetch: @escaping Fetch) {
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.fetch = fetch
    }

    func state(for key: MediaPreviewKey) -> MediaPreviewState {
        if let preview = encodedCache.value(for: key) { return .ready(preview) }
        return states[key] ?? .idle
    }

    func encodedCacheStats() -> ByteCostLRUCacheStats { encodedCache.stats }

    func purgeEncodedCache() { encodedCache.removeAll() }

    func load(
        _ key: MediaPreviewKey,
        isViewOnce: Bool,
        priority: MediaPreviewPriority = .visible
    ) async -> MediaPreviewState {
        if isViewOnce {
            encodedCache.removeValue(for: key)
            states[key] = .unavailable
            return .unavailable
        }
        if let preview = encodedCache.value(for: key) {
            return .ready(preview)
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .idle)
                    return
                }
                enqueue(
                    key: key,
                    priority: priority,
                    waiterID: waiterID,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.cancelWaiter(key: key, waiterID: waiterID) }
        }
    }

    func cancel(_ key: MediaPreviewKey) {
        cancelRequest(key)
    }

    var activeRequestCount: Int { running.count }
    var queuedRequestCount: Int { queue.count }

    private func enqueue(
        key: MediaPreviewKey,
        priority: MediaPreviewPriority,
        waiterID: UUID,
        continuation: CheckedContinuation<MediaPreviewState, Never>
    ) {
        if var request = requests[key] {
            request.waiters[waiterID] = Waiter(continuation: continuation)
            if priority < request.priority, request.task == nil {
                request.priority = priority
                if let index = queue.firstIndex(where: { $0.key == key }) {
                    queue[index].priority = priority
                }
            }
            requests[key] = request
            startAvailableRequests()
            return
        }

        sequence &+= 1
        let request = Request(
            priority: priority,
            sequence: sequence,
            waiters: [waiterID: Waiter(continuation: continuation)],
            task: nil
        )
        requests[key] = request
        queue.append(QueueEntry(key: key, priority: priority, sequence: sequence))
        states[key] = .queued
        sortQueue()
        startAvailableRequests()
    }

    private func sortQueue() {
        queue.sort {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.sequence < $1.sequence
        }
    }

    private func startAvailableRequests() {
        while running.count < maximumConcurrentRequests, !queue.isEmpty {
            let entry = queue.removeFirst()
            guard var request = requests[entry.key], request.task == nil, !request.waiters.isEmpty else {
                continue
            }
            running.insert(entry.key)
            states[entry.key] = .loading
            let key = entry.key
            let fetch = self.fetch
            let task = Task { [weak self] in
                do {
                    let preview = try await fetch(key)
                    guard !Task.isCancelled else {
                        await self?.finishCancelled(key)
                        return
                    }
                    await self?.finish(key, state: .ready(preview))
                } catch is CancellationError {
                    await self?.finishCancelled(key)
                } catch let error as WhatsAppTransportMediaPreviewFailure where error == .unavailable {
                    await self?.finish(key, state: .unavailable)
                } catch {
                    guard !Task.isCancelled else {
                        await self?.finishCancelled(key)
                        return
                    }
                    await self?.finish(key, state: .failed(.transport))
                }
            }
            request.task = task
            requests[key] = request
        }
    }

    private func finish(_ key: MediaPreviewKey, state: MediaPreviewState) {
        guard let request = requests.removeValue(forKey: key) else { return }
        running.remove(key)
        if case .ready(let preview) = state {
            _ = encodedCache.insert(preview, for: key, costBytes: preview.data.count)
            states.removeValue(forKey: key)
        } else {
            states[key] = state
        }
        request.waiters.values.forEach { $0.continuation.resume(returning: state) }
        startAvailableRequests()
    }

    private func finishCancelled(_ key: MediaPreviewKey) {
        guard let request = requests.removeValue(forKey: key) else { return }
        running.remove(key)
        queue.removeAll { $0.key == key }
        states[key] = .idle
        request.waiters.values.forEach { $0.continuation.resume(returning: .idle) }
        startAvailableRequests()
    }

    private func cancelWaiter(key: MediaPreviewKey, waiterID: UUID) {
        guard var request = requests[key], let waiter = request.waiters.removeValue(forKey: waiterID) else { return }
        waiter.continuation.resume(returning: .idle)
        if request.waiters.isEmpty {
            requests[key] = request
            cancelRequest(key)
        } else {
            requests[key] = request
        }
    }

    private func cancelRequest(_ key: MediaPreviewKey) {
        guard let request = requests.removeValue(forKey: key) else {
            states[key] = .idle
            return
        }
        queue.removeAll { $0.key == key }
        running.remove(key)
        request.task?.cancel()
        states[key] = .idle
        request.waiters.values.forEach { $0.continuation.resume(returning: .idle) }
        startAvailableRequests()
    }
}

struct WhatsAppTransportMessage: Codable, Equatable, Sendable {
    let id: String
    let chatID: String
    let senderID: String?
    let timestampMilliseconds: Int64
    let body: String?
    let fromMe: Bool
    let quote: WhatsAppTransportQuote?
    let media: WhatsAppTransportMediaMetadata?
    let linkPreview: WhatsAppTransportLinkPreview?
    let content: WhatsAppTransportMessageContent
    let deliveryState: WhatsAppTransportDeliveryState?

    init(
        id: String,
        chatID: String,
        senderID: String?,
        timestampMilliseconds: Int64,
        body: String?,
        fromMe: Bool,
        quote: WhatsAppTransportQuote?,
        media: WhatsAppTransportMediaMetadata?,
        linkPreview: WhatsAppTransportLinkPreview? = nil,
        content: WhatsAppTransportMessageContent? = nil,
        deliveryState: WhatsAppTransportDeliveryState? = nil
    ) {
        self.id = id
        self.chatID = chatID
        self.senderID = senderID
        self.timestampMilliseconds = timestampMilliseconds
        self.body = body
        self.fromMe = fromMe
        self.quote = quote
        self.media = media
        self.linkPreview = linkPreview
        self.content = content ?? Self.inferredContent(body: body, media: media, linkPreview: linkPreview)
        self.deliveryState = deliveryState
    }

    private enum CodingKeys: String, CodingKey {
        case id, chatID, senderID, timestampMilliseconds, body, fromMe, quote, media, linkPreview, content, deliveryState
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        chatID = try values.decode(String.self, forKey: .chatID)
        senderID = try values.decodeIfPresent(String.self, forKey: .senderID)
        timestampMilliseconds = try values.decode(Int64.self, forKey: .timestampMilliseconds)
        body = try values.decodeIfPresent(String.self, forKey: .body)
        fromMe = try values.decode(Bool.self, forKey: .fromMe)
        quote = try values.decodeIfPresent(WhatsAppTransportQuote.self, forKey: .quote)
        media = try values.decodeIfPresent(WhatsAppTransportMediaMetadata.self, forKey: .media)
        linkPreview = try values.decodeIfPresent(WhatsAppTransportLinkPreview.self, forKey: .linkPreview)
        content = try values.decodeIfPresent(WhatsAppTransportMessageContent.self, forKey: .content)
            ?? Self.inferredContent(body: body, media: media, linkPreview: linkPreview)
        deliveryState = try values.decodeIfPresent(WhatsAppTransportDeliveryState.self, forKey: .deliveryState)
    }

    private static func inferredContent(
        body: String?,
        media: WhatsAppTransportMediaMetadata?,
        linkPreview: WhatsAppTransportLinkPreview?
    ) -> WhatsAppTransportMessageContent {
        if media != nil { return .init(kind: .media) }
        if linkPreview != nil { return .init(kind: .linkPreview) }
        return .init(kind: .text)
    }
}

struct WhatsAppTransportMessageCursor: Codable, Equatable, Sendable {
    let beforeMessageID: String?
    let beforeTimestampMilliseconds: Int64?
}

struct WhatsAppTransportMessagePage: Codable, Equatable, Sendable {
    let messages: [WhatsAppTransportMessage]
    let nextCursor: WhatsAppTransportMessageCursor?
}

enum WhatsAppTransportEvent: Equatable, Sendable {
    case ready
    case message(WhatsAppTransportMessage)
    case messageUpdate(WhatsAppTransportMessage)
    case chatUpdate(WhatsAppTransportChat)
    case disconnected(reason: String?)
    case historySync(
        chatID: String,
        messages: [WhatsAppTransportMessage],
        nextCursor: WhatsAppTransportMessageCursor?
    )
}

protocol WhatsAppTransport: Sendable {
    func connect() async throws
    func connectionState() async throws -> WhatsAppTransportConnectionState
    func listChats() async throws -> [WhatsAppTransportChat]
    func loadMessages(
        chatID: String,
        cursor: WhatsAppTransportMessageCursor?,
        limit: Int
    ) async throws -> WhatsAppTransportMessagePage
    func sendText(_ text: String, to chatID: String) async throws -> WhatsAppTransportMessage
    func reply(
        _ text: String,
        to messageID: String,
        in chatID: String
    ) async throws -> WhatsAppTransportMessage
    func mediaPreview(chatID: String, messageID: String, maxPixelSize: Int) async throws -> WhatsAppTransportMediaPreview
    func eventStream() async -> AsyncStream<WhatsAppTransportEvent>
}

extension WhatsAppTransport {
    func mediaPreview(chatID: String, messageID: String, maxPixelSize: Int) async throws -> WhatsAppTransportMediaPreview {
        throw WhatsAppTransportMediaPreviewFailure.unavailable
    }
}

enum WhatsAppTransportMediaPreviewFailure: Error, Equatable, Sendable {
    case unavailable
}

enum WhatsAppBridgeResponse: Equatable, Sendable {
    case connectionState(WhatsAppTransportConnectionState)
    case chats([WhatsAppTransportChat])
    case messages(WhatsAppTransportMessagePage)
    case sentMessage(WhatsAppTransportMessage)
    case repliedMessage(WhatsAppTransportMessage)
    case mediaPreview(WhatsAppTransportMediaPreview)
}

enum WhatsAppBridgeDecodingError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case unknownEventKind(String)
    case unknownResponseKind(String)
    case invalidPayload(String)
}

enum WhatsAppBridgeContract {
    static let version = 1
}

enum WhatsAppBridgeDecoder {
    static func decodeEvent(from data: Data) throws -> WhatsAppTransportEvent {
        let header = try decodeHeader(from: data)
        try requireSupportedVersion(header.version)

        switch header.kind {
        case "ready":
            _ = try decodeEnvelope(EmptyPayload.self, from: data)
            return .ready
        case "message":
            let payload = try decodeEnvelope(WhatsAppTransportMessage.self, from: data).payload
            try validate(payload)
            return .message(payload)
        case "messageUpdate":
            let payload = try decodeEnvelope(WhatsAppTransportMessage.self, from: data).payload
            try validate(payload)
            return .messageUpdate(payload)
        case "chatUpdate":
            let payload = try decodeEnvelope(WhatsAppTransportChat.self, from: data).payload
            try validate(payload)
            return .chatUpdate(payload)
        case "disconnected":
            let payload = try decodeEnvelope(DisconnectedPayload.self, from: data).payload
            return .disconnected(reason: payload.reason)
        case "historySync":
            let payload = try decodeEnvelope(HistorySyncPayload.self, from: data).payload
            try validateHistorySync(payload)
            return .historySync(
                chatID: payload.chatID,
                messages: payload.messages,
                nextCursor: payload.nextCursor
            )
        default:
            throw WhatsAppBridgeDecodingError.unknownEventKind(header.kind)
        }
    }

    static func decodeResponse(from data: Data) throws -> WhatsAppBridgeResponse {
        let header = try decodeHeader(from: data)
        try requireSupportedVersion(header.version)

        switch header.kind {
        case "connectionState":
            let payload = try decodeEnvelope(ConnectionStatePayload.self, from: data).payload
            return .connectionState(payload.state)
        case "listChats":
            let payload = try decodeEnvelope(ChatListPayload.self, from: data).payload
            try payload.chats.forEach(validate)
            return .chats(payload.chats)
        case "loadMessages":
            let payload = try decodeEnvelope(WhatsAppTransportMessagePage.self, from: data).payload
            try validate(payload)
            return .messages(payload)
        case "sendText":
            let payload = try decodeEnvelope(MessagePayload.self, from: data).payload
            try validate(payload.message)
            return .sentMessage(payload.message)
        case "reply":
            let payload = try decodeEnvelope(MessagePayload.self, from: data).payload
            try validate(payload.message)
            return .repliedMessage(payload.message)
        case "mediaPreview":
            let payload = try decodeEnvelope(WhatsAppTransportMediaPreview.self, from: data).payload
            try validate(payload)
            return .mediaPreview(payload)
        default:
            throw WhatsAppBridgeDecodingError.unknownResponseKind(header.kind)
        }
    }

    private static func decodeHeader(from data: Data) throws -> EnvelopeHeader {
        do {
            return try JSONDecoder().decode(EnvelopeHeader.self, from: data)
        } catch {
            throw WhatsAppBridgeDecodingError.invalidPayload("envelope")
        }
    }

    private static func decodeEnvelope<Payload: Decodable>(
        _ payloadType: Payload.Type,
        from data: Data
    ) throws -> Envelope<Payload> {
        do {
            let envelope = try JSONDecoder().decode(Envelope<Payload>.self, from: data)
            guard envelope.version == WhatsAppBridgeContract.version else {
                throw WhatsAppBridgeDecodingError.unsupportedVersion(envelope.version)
            }
            return envelope
        } catch let error as WhatsAppBridgeDecodingError {
            throw error
        } catch {
            throw WhatsAppBridgeDecodingError.invalidPayload(String(describing: payloadType))
        }
    }

    private static func requireSupportedVersion(_ version: Int) throws {
        guard version == WhatsAppBridgeContract.version else {
            throw WhatsAppBridgeDecodingError.unsupportedVersion(version)
        }
    }

    private static func validate(_ chat: WhatsAppTransportChat) throws {
        guard !chat.id.isEmpty, chat.unreadCount >= 0 else {
            throw WhatsAppBridgeDecodingError.invalidPayload("chat")
        }
        if let timestamp = chat.lastMessageTimestampMilliseconds, timestamp < 0 {
            throw WhatsAppBridgeDecodingError.invalidPayload("chat")
        }
    }

    private static func validate(_ message: WhatsAppTransportMessage) throws {
        guard !message.id.isEmpty, !message.chatID.isEmpty, message.timestampMilliseconds >= 0 else {
            throw WhatsAppBridgeDecodingError.invalidPayload("message")
        }
        if let senderID = message.senderID, senderID.isEmpty {
            throw WhatsAppBridgeDecodingError.invalidPayload("message")
        }
        if let quote = message.quote {
            guard !quote.messageID.isEmpty else {
                throw WhatsAppBridgeDecodingError.invalidPayload("quote")
            }
            if let senderID = quote.senderID, senderID.isEmpty {
                throw WhatsAppBridgeDecodingError.invalidPayload("quote")
            }
        }
        if let media = message.media {
            try validate(media)
        }
        if let preview = message.linkPreview {
            guard !preview.matchedText.isEmpty else {
                throw WhatsAppBridgeDecodingError.invalidPayload("linkPreview")
            }
        }
        try validate(message.content)
        switch message.content.kind {
        case .text:
            guard message.media == nil, message.linkPreview == nil else {
                throw WhatsAppBridgeDecodingError.invalidPayload("messageContent")
            }
        case .media:
            guard message.media != nil else { throw WhatsAppBridgeDecodingError.invalidPayload("messageContent") }
        case .linkPreview:
            guard message.media == nil, message.linkPreview != nil else {
                throw WhatsAppBridgeDecodingError.invalidPayload("messageContent")
            }
        case .location, .contact, .poll, .revoked, .system, .unsupported:
            guard message.body == nil, message.media == nil, message.linkPreview == nil else {
                throw WhatsAppBridgeDecodingError.invalidPayload("messageContent")
            }
        }
    }

    private static func validate(_ content: WhatsAppTransportMessageContent) throws {
        let noSpecialPayload = content.location == nil && content.contacts == nil && content.poll == nil
            && content.system == nil && content.rawType == nil
        switch content.kind {
        case .text, .media, .linkPreview, .revoked:
            guard noSpecialPayload else {
                throw WhatsAppBridgeDecodingError.invalidPayload("messageContent")
            }
        case .location:
            guard let location = content.location, content.contacts == nil, content.poll == nil,
                  content.system == nil, content.rawType == nil,
                  location.latitude.isFinite, (-90...90).contains(location.latitude),
                  location.longitude.isFinite, (-180...180).contains(location.longitude),
                  (location.name?.count ?? 0) <= 512, (location.address?.count ?? 0) <= 1_024 else {
                throw WhatsAppBridgeDecodingError.invalidPayload("messageContent.location")
            }
        case .contact:
            guard let contacts = content.contacts, !contacts.isEmpty, contacts.count <= 8,
                  content.location == nil, content.poll == nil, content.system == nil, content.rawType == nil,
                  contacts.allSatisfy({ !$0.vCard.isEmpty && $0.vCard.count <= 4_096
                      && ($0.displayName?.count ?? 0) <= 256 }) else {
                throw WhatsAppBridgeDecodingError.invalidPayload("messageContent.contact")
            }
        case .poll:
            guard let poll = content.poll, !poll.question.isEmpty, poll.question.count <= 2_048,
                  !poll.options.isEmpty, poll.options.count <= 20,
                  poll.options.allSatisfy({ !$0.isEmpty && $0.count <= 512 }),
                  content.location == nil, content.contacts == nil, content.system == nil, content.rawType == nil else {
                throw WhatsAppBridgeDecodingError.invalidPayload("messageContent.poll")
            }
        case .system:
            guard let system = content.system, !system.type.isEmpty, system.type.count <= 128,
                  (system.text?.count ?? 0) <= 2_048, content.location == nil, content.contacts == nil,
                  content.poll == nil, content.rawType == nil else {
                throw WhatsAppBridgeDecodingError.invalidPayload("messageContent.system")
            }
        case .unsupported:
            guard let rawType = content.rawType, !rawType.isEmpty, rawType.count <= 64,
                  content.location == nil, content.contacts == nil, content.poll == nil, content.system == nil else {
                throw WhatsAppBridgeDecodingError.invalidPayload("messageContent.unsupported")
            }
        }
    }

    private static func validate(_ media: WhatsAppTransportMediaMetadata) throws {
        let values: [Int64?] = [media.sizeBytes, media.durationMilliseconds]
        guard values.compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else {
            throw WhatsAppBridgeDecodingError.invalidPayload("media")
        }
        let dimensions: [Int?] = [media.width, media.height]
        guard dimensions.compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else {
            throw WhatsAppBridgeDecodingError.invalidPayload("media")
        }
    }

    private static func validate(_ preview: WhatsAppTransportMediaPreview) throws {
        guard !preview.mimeType.isEmpty, !preview.data.isEmpty, preview.data.count <= 1_500_000 else {
            throw WhatsAppBridgeDecodingError.invalidPayload("mediaPreview")
        }
        let dimensions = [preview.width, preview.height].compactMap { $0 }
        guard dimensions.allSatisfy({ $0 > 0 && $0 <= 4_096 }) else {
            throw WhatsAppBridgeDecodingError.invalidPayload("mediaPreview")
        }
    }

    private static func validate(_ cursor: WhatsAppTransportMessageCursor) throws {
        guard cursor.beforeMessageID != nil || cursor.beforeTimestampMilliseconds != nil else {
            throw WhatsAppBridgeDecodingError.invalidPayload("cursor")
        }
        if let messageID = cursor.beforeMessageID, messageID.isEmpty {
            throw WhatsAppBridgeDecodingError.invalidPayload("cursor")
        }
        if let timestamp = cursor.beforeTimestampMilliseconds, timestamp < 0 {
            throw WhatsAppBridgeDecodingError.invalidPayload("cursor")
        }
    }

    private static func validate(_ page: WhatsAppTransportMessagePage) throws {
        try page.messages.forEach(validate)
        if let nextCursor = page.nextCursor {
            try validate(nextCursor)
        }
    }

    private static func validateHistorySync(_ payload: HistorySyncPayload) throws {
        guard !payload.chatID.isEmpty else {
            throw WhatsAppBridgeDecodingError.invalidPayload("historySync")
        }
        try payload.messages.forEach { message in
            try validate(message)
            guard message.chatID == payload.chatID else {
                throw WhatsAppBridgeDecodingError.invalidPayload("historySync")
            }
        }
        if let nextCursor = payload.nextCursor {
            try validate(nextCursor)
        }
    }
}

private struct EnvelopeHeader: Decodable {
    let version: Int
    let kind: String
}

private struct Envelope<Payload: Decodable>: Decodable {
    let version: Int
    let kind: String
    let payload: Payload
}

private struct EmptyPayload: Decodable {}

private struct DisconnectedPayload: Decodable {
    let reason: String?
}

private struct HistorySyncPayload: Decodable {
    let chatID: String
    let messages: [WhatsAppTransportMessage]
    let nextCursor: WhatsAppTransportMessageCursor?
}

private struct ConnectionStatePayload: Decodable {
    let state: WhatsAppTransportConnectionState
}

private struct ChatListPayload: Decodable {
    let chats: [WhatsAppTransportChat]
}

private struct MessagePayload: Decodable {
    let message: WhatsAppTransportMessage
}
