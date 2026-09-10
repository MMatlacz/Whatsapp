import Foundation

public enum TranslationBenchmarkContextMode: String, Codable, Equatable, Sendable {
    case none
    case bounded
}

public struct TranslationBenchmarkContextTurn: Codable, Equatable, Sendable {
    public let speaker: String
    public let body: String

    public init(speaker: String, body: String) {
        self.speaker = speaker
        self.body = body
    }

    init(_ turn: TranslationContextTurn) {
        self.init(speaker: turn.speaker.rawValue, body: turn.body)
    }

}

public struct TranslationBenchmarkContextSnapshot: Codable, Equatable, Sendable {
    public let recentTurns: [TranslationBenchmarkContextTurn]
    public let quotedTurn: TranslationBenchmarkContextTurn?

    public init(
        recentTurns: [TranslationBenchmarkContextTurn] = [],
        quotedTurn: TranslationBenchmarkContextTurn? = nil
    ) {
        self.recentTurns = recentTurns
        self.quotedTurn = quotedTurn
    }

    public static let none = TranslationBenchmarkContextSnapshot()
}

public struct TranslationBenchmarkFixture: Equatable, Sendable {
    public let id: String
    public let semanticCaseID: String
    public let title: String
    public let route: String
    public let contextWindow: Int
    public let contextMode: TranslationBenchmarkContextMode
    public let focus: String
    public let input: String
    public let suppliedContext: TranslationBenchmarkContextSnapshot
    public let intendedMeaning: String
    public let preservationNotes: String
    public let request: TranslationRequest

    public init(
        id: String,
        semanticCaseID: String? = nil,
        title: String,
        route: String,
        contextWindow: Int,
        contextMode: TranslationBenchmarkContextMode = .none,
        focus: String,
        input: String? = nil,
        suppliedContext: TranslationBenchmarkContextSnapshot = .none,
        intendedMeaning: String = "",
        preservationNotes: String = "",
        request: TranslationRequest
    ) {
        self.id = id
        self.semanticCaseID = semanticCaseID ?? id
        self.title = title
        self.route = route
        self.contextWindow = contextWindow
        self.contextMode = contextMode
        self.focus = focus
        self.input = input ?? request.sourceText ?? ""
        self.suppliedContext = suppliedContext
        self.intendedMeaning = intendedMeaning
        self.preservationNotes = preservationNotes
        self.request = request
    }
}

/// The unencoded P0.1 benchmark corpus shared by system-model and local-model
/// diagnostics. The prompts are sourced directly from `P01BenchmarkFixtures`
/// so the local-model benchmark cannot silently drift from the original
/// source-controlled P0.1 fixtures or the 0/3/8/16 context windows.
public enum P01SharedTranslationBenchmarkFixtures {
    public static let unencoded: [TranslationBenchmarkFixture] =
        P01BenchmarkFixtures.requests.map(makeFixture)

    private static func makeFixture(
        _ fixture: P01BenchmarkRequest
    ) -> TranslationBenchmarkFixture {
        let source: String
        let target: String
        let sourceText: String

        switch fixture.id {
        case "id-en-hard-particles":
            source = "id"
            target = "en"
            sourceText = "Dia bilang, nanti aja ya. Aku lagi mager banget nih, jangan dipaksa dong wkwk."
        case "en-pl-natural-chat":
            source = "en"
            target = "pl"
            sourceText = "She said maybe later. She is really too lazy to go out right now, so don't push her, haha."
        case "id-pl-omitted-subject":
            source = "id"
            target = "pl"
            sourceText = "Kok nggak bilang dari tadi? Masa harus nebak sendiri sih? Aku kan udah nunggu lama banget."
        case "contextual-id-pl-0",
             "contextual-id-pl-3",
             "contextual-id-pl-8",
             "contextual-id-pl-16":
            source = "id"
            target = "pl"
            sourceText = "\"Nanti aku nyusul\" kata dia. Jangan panik dong, traffic lagi gila nih wkwk. Bapak sudah tahu kalau Tante mau ikut juga?"
        default:
            preconditionFailure(
                "Unexpected unencoded P0.1 benchmark fixture: \(fixture.id)"
            )
        }

        let prompt = TranslationPrompt(
            version: fixture.promptVersion,
            instructions: fixture.instructions,
            untrustedInput: fixture.prompt
        )
        let request = TranslationRequest(
            id: TranslationRequestID(rawValue: fixture.id)!,
            revision: 1,
            languages: TranslationLanguagePair(
                sourceLanguage: source,
                targetLanguage: target
            )!,
            prompt: prompt,
            sourceText: sourceText
        )!

        return TranslationBenchmarkFixture(
            id: fixture.id,
            semanticCaseID: fixture.id,
            title: fixture.title,
            route: fixture.route,
            contextWindow: fixture.contextWindow,
            contextMode: .none,
            focus: fixture.focus,
            input: sourceText,
            intendedMeaning: "Review the output against the fixture's source meaning.",
            preservationNotes: fixture.focus,
            request: request
        )
    }
}
