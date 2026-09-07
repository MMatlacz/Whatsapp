import Foundation

#if SWIFT_PACKAGE
import WhatsAppDomainCore
#endif

public struct TranslationSpeakerAlias: RawRepresentable, Equatable, Hashable, Sendable, Comparable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.rawValue = rawValue
    }

    public static let localUser = TranslationSpeakerAlias(rawValue: "SELF")!
    public static let unknown = TranslationSpeakerAlias(rawValue: "UNKNOWN")!

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TranslationContextTurn: Equatable, Sendable {
    public let speaker: TranslationSpeakerAlias
    public let body: String

    public init(speaker: TranslationSpeakerAlias, body: String) {
        self.speaker = speaker
        self.body = body
    }
}

public struct TranslationQuotedTurn: Equatable, Sendable {
    public let speaker: TranslationSpeakerAlias
    public let body: String

    public init(speaker: TranslationSpeakerAlias, body: String) {
        self.speaker = speaker
        self.body = body
    }
}

public struct TranslationContextSummary: Equatable, Sendable {
    public let version: Int
    public let body: String
    public let sourceMessageCount: Int

    public init?(version: Int, body: String, sourceMessageCount: Int) {
        guard
            version > 0,
            sourceMessageCount > 0,
            !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        self.version = version
        self.body = body
        self.sourceMessageCount = sourceMessageCount
    }
}

public struct TranslationTarget: Equatable, Sendable {
    public let speaker: TranslationSpeakerAlias
    public let body: String

    public init(speaker: TranslationSpeakerAlias, body: String) {
        self.speaker = speaker
        self.body = body
    }
}

public struct TranslationContext: Equatable, Sendable {
    public let target: TranslationTarget
    public let recentTurns: [TranslationContextTurn]
    public let quotedTurn: TranslationQuotedTurn?
    public let summary: TranslationContextSummary?

    public init(
        target: TranslationTarget,
        recentTurns: [TranslationContextTurn],
        quotedTurn: TranslationQuotedTurn?,
        summary: TranslationContextSummary?
    ) {
        self.target = target
        self.recentTurns = recentTurns
        self.quotedTurn = quotedTurn
        self.summary = summary
    }
}

public enum TranslationContextBuilderError: Error, Equatable, Sendable {
    case invalidRecentTurnLimit(Int)
    case targetHasNoText
}

public struct TranslationContextBuilder: Sendable {
    public static let defaultRecentTurnLimit = 8
    public static let maximumRecentTurnLimit = 16

    public init() {}

    public func build(
        target: WhatsAppMessage,
        conversation: [WhatsAppMessage],
        summary: TranslationContextSummary? = nil,
        recentTurnLimit: Int = Self.defaultRecentTurnLimit
    ) throws -> TranslationContext {
        guard (0...Self.maximumRecentTurnLimit).contains(recentTurnLimit) else {
            throw TranslationContextBuilderError.invalidRecentTurnLimit(recentTurnLimit)
        }
        guard let targetBody = textualBody(target.body) else {
            throw TranslationContextBuilderError.targetHasNoText
        }

        let priorMessages = conversation
            .filter { $0.chatID == target.chatID && comesBefore($0, target: target) }
            .sorted(by: messageOrder)

        let aliases = aliasMap(for: priorMessages, target: target)
        let quoted = quotedTurn(
            target: target,
            priorMessages: priorMessages,
            aliases: aliases
        )

        let quotedMessageID = quoted == nil ? nil : target.quote?.messageID
        let recentMessages = priorMessages
            .filter { message in
                message.id != quotedMessageID && textualBody(message.body) != nil
            }
        let selectedRecent = BoundedContext.recent(recentMessages, limit: recentTurnLimit)

        return TranslationContext(
            target: TranslationTarget(
                speaker: speakerAlias(for: target, aliases: aliases),
                body: targetBody
            ),
            recentTurns: selectedRecent.compactMap { message in
                guard let body = textualBody(message.body) else { return nil }
                return TranslationContextTurn(
                    speaker: speakerAlias(for: message, aliases: aliases),
                    body: body
                )
            },
            quotedTurn: quoted,
            summary: summary
        )
    }

    private func aliasMap(
        for priorMessages: [WhatsAppMessage],
        target: WhatsAppMessage
    ) -> [WhatsAppParticipantID: TranslationSpeakerAlias] {
        var participantIDs = Set<WhatsAppParticipantID>()

        for message in priorMessages + [target] {
            if !message.fromMe, let senderID = message.senderID {
                participantIDs.insert(senderID)
            }
            if let quoteSenderID = message.quote?.senderID {
                participantIDs.insert(quoteSenderID)
            }
        }

        if let quoteSenderID = target.quote?.senderID {
            participantIDs.insert(quoteSenderID)
        }

        let sortedIDs = participantIDs.sorted { $0.rawValue < $1.rawValue }
        var aliases: [WhatsAppParticipantID: TranslationSpeakerAlias] = [:]
        aliases.reserveCapacity(sortedIDs.count)

        for (index, participantID) in sortedIDs.enumerated() {
            aliases[participantID] = TranslationSpeakerAlias(rawValue: "P\(index + 1)")!
        }

        return aliases
    }

    private func quotedTurn(
        target: WhatsAppMessage,
        priorMessages: [WhatsAppMessage],
        aliases: [WhatsAppParticipantID: TranslationSpeakerAlias]
    ) -> TranslationQuotedTurn? {
        guard let quote = target.quote else { return nil }

        let matchedMessage = priorMessages.first { $0.id == quote.messageID }
        let body = textualBody(matchedMessage?.body) ?? textualBody(quote.body)
        guard let body else { return nil }

        let speaker: TranslationSpeakerAlias
        if let matchedMessage {
            speaker = speakerAlias(for: matchedMessage, aliases: aliases)
        } else if let senderID = quote.senderID {
            speaker = aliases[senderID] ?? .unknown
        } else {
            speaker = .unknown
        }

        return TranslationQuotedTurn(speaker: speaker, body: body)
    }

    private func speakerAlias(
        for message: WhatsAppMessage,
        aliases: [WhatsAppParticipantID: TranslationSpeakerAlias]
    ) -> TranslationSpeakerAlias {
        if message.fromMe {
            return .localUser
        }
        guard let senderID = message.senderID else {
            return .unknown
        }
        return aliases[senderID] ?? .unknown
    }

    private func comesBefore(_ message: WhatsAppMessage, target: WhatsAppMessage) -> Bool {
        guard message.id != target.id else { return false }
        if message.timestamp != target.timestamp {
            return message.timestamp < target.timestamp
        }
        return message.id.rawValue < target.id.rawValue
    }

    private func messageOrder(_ lhs: WhatsAppMessage, _ rhs: WhatsAppMessage) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private func textualBody(_ body: String?) -> String? {
        guard let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return body
    }
}

enum BoundedContext {
    static func recent<Message>(
        _ messages: [Message],
        limit: Int
    ) -> [Message] {
        guard limit > 0 else {
            return []
        }

        return Array(messages.suffix(limit))
    }
}

struct P01BenchmarkRequest: Identifiable, Sendable {
    let id: String
    let title: String
    let route: String
    let contextWindow: Int
    let focus: String
    let prompt: String
}

enum P01BenchmarkFixtures {
    static let requests: [P01BenchmarkRequest] = [
        simple(
            id: "id-en-hard-particles",
            title: "ID -> EN particles and slang",
            route: "Indonesian -> English",
            focus: "dia ambiguity, dong/sih/nih tone, mager, wkwk",
            input: "Dia bilang, nanti aja ya. Aku lagi mager banget nih, jangan dipaksa dong wkwk."
        ),
        simple(
            id: "en-pl-natural-chat",
            title: "EN -> PL natural chat",
            route: "English -> Polish",
            focus: "natural Polish tone, informal chat register",
            input: "She said maybe later. She is really too lazy to go out right now, so don't push her, haha."
        ),
        simple(
            id: "id-pl-omitted-subject",
            title: "ID -> PL omitted subject",
            route: "Indonesian -> Polish",
            focus: "kok, masa, sih, omitted subject, nggak/gak variants",
            input: "Kok nggak bilang dari tadi? Masa harus nebak sendiri sih? Aku kan udah nunggu lama banget."
        ),
        contextual(contextWindow: 0),
        contextual(contextWindow: 3),
        contextual(contextWindow: 8),
        contextual(contextWindow: 16)
    ]

    private static func simple(
        id: String,
        title: String,
        route: String,
        focus: String,
        input: String
    ) -> P01BenchmarkRequest {
        P01BenchmarkRequest(
            id: id,
            title: title,
            route: route,
            contextWindow: 0,
            focus: focus,
            prompt: """
            Translate this chat message.

            Input:
            \(input)
            """
        )
    }

    private static func contextual(contextWindow: Int) -> P01BenchmarkRequest {
        let context = BoundedContext.recent(contextMessages, limit: contextWindow)
            .enumerated()
            .map { index, message in "\(index + 1). \(message)" }
            .joined(separator: "\n")

        return P01BenchmarkRequest(
            id: "contextual-id-pl-\(contextWindow)",
            title: "Contextual ID -> PL (\(contextWindow))",
            route: "Contextual Indonesian -> Polish",
            contextWindow: contextWindow,
            focus: "dia resolution, family terms, quoted reply, code-switching, jokes, context window sensitivity",
            prompt: """
            Translate the target Indonesian chat message into Polish.
            Use conversation context only when it helps resolve references.

            Context messages available: \(contextWindow)
            \(context.isEmpty ? "No prior context." : context)

            Target message:
            Sari: "Nanti aku nyusul" kata dia. Jangan panik dong, traffic lagi gila nih wkwk. Bapak sudah tahu kalau Tante mau ikut juga?
            """
        )
    }

    private static let contextMessages: [String] = [
        "Marcin: Czy Rina jedzie z nami do cioci?",
        "Sari: Rina masih di kantor, meeting-nya molor.",
        "Bapak: Kalau terlalu malam, kita langsung ke rumah Tante saja.",
        "Rina: Aku ikut, tapi jangan tunggu aku di bawah.",
        "Sari: Oke, nanti aku bilang ke Marcin.",
        "Marcin: Bapak już wie o zmianie planu?",
        "Sari: Belum, Bapak lagi mandi.",
        "Tante: Aku jadi ikut makan malam ya.",
        "Rina: Macet parah, aku nyusul aja.",
        "Marcin: Does 'nyusul' mean she will come later?",
        "Sari: Iya, she will join later, not cancel.",
        "Bapak: Jangan lupa bawa martabak.",
        "Rina: Kalau aku telat, langsung pesan duluan.",
        "Sari: Marcin agak panik karena jadwal berubah.",
        "Tante: Santai saja, aku tunggu di rumah.",
        "Rina: Nanti aku nyusul."
    ]
}
