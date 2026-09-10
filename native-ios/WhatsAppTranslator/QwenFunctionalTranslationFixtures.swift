import Foundation

/// Synthetic Indonesian -> Polish cases used by the functional Qwen CI run.
/// The corpus describes intended meaning and preservation requirements for
/// human review; it deliberately does not define one exact reference string.
public struct QwenFunctionalTranslationCase: Equatable, Sendable {
    public let id: String
    public let title: String
    public let focus: String
    public let input: String
    public let intendedMeaning: String
    public let preservationNotes: String
    public let recentContext: [TranslationContextTurn]
    public let quotedContext: TranslationQuotedTurn?
    public let compareContext: Bool

    public init(
        id: String,
        title: String,
        focus: String,
        input: String,
        intendedMeaning: String,
        preservationNotes: String,
        recentContext: [TranslationContextTurn] = [],
        quotedContext: TranslationQuotedTurn? = nil,
        compareContext: Bool = false
    ) {
        self.id = id
        self.title = title
        self.focus = focus
        self.input = input
        self.intendedMeaning = intendedMeaning
        self.preservationNotes = preservationNotes
        self.recentContext = recentContext
        self.quotedContext = quotedContext
        self.compareContext = compareContext
    }
}

public enum QwenFunctionalTranslationBenchmarkFixtures {
    public static let cases: [QwenFunctionalTranslationCase] = [
        QwenFunctionalTranslationCase(
            id: "straight-arrival",
            title: "Straightforward arrival",
            focus: "basic informal statement",
            input: "Aku sudah sampai di rumah.",
            intendedMeaning: "The speaker has already arrived home.",
            preservationNotes: "Keep the first-person voice and informal but neutral register."
        ),
        QwenFunctionalTranslationCase(
            id: "straight-plan",
            title: "Straightforward plan",
            focus: "future plan and casual question particle",
            input: "Besok kita makan siang jam satu ya.",
            intendedMeaning: "The speaker proposes lunch together tomorrow at one o'clock.",
            preservationNotes: "Preserve the friendly confirmation-seeking tone of ya."
        ),
        QwenFunctionalTranslationCase(
            id: "straight-thanks",
            title: "Straightforward thanks",
            focus: "natural conversational gratitude",
            input: "Makasih sudah bantu aku hari ini.",
            intendedMeaning: "The speaker thanks the other person for helping today.",
            preservationNotes: "Keep it warm and conversational rather than formal."
        ),
        QwenFunctionalTranslationCase(
            id: "dia-late",
            title: "Dia with contextual feminine referent",
            focus: "gender-neutral dia resolved from bounded context",
            input: "Dia bilang akan datang nanti.",
            intendedMeaning: "Rina said that she will come later.",
            preservationNotes: "Use a feminine Polish reference only because the context identifies Rina; do not invent a new event.",
            recentContext: [
                turn("P1", "Rina masih di kantor, tapi sebentar lagi selesai."),
                turn("P2", "Oke, kita tunggu dia di kafe."),
            ],
            compareContext: true
        ),
        QwenFunctionalTranslationCase(
            id: "omitted-subject-finished",
            title: "Omitted subject after a file check",
            focus: "omitted subject and passive-like chat shorthand",
            input: "Udah selesai, tinggal dikirim.",
            intendedMeaning: "The file/task is finished; it only needs to be sent.",
            preservationNotes: "Do not invent who finished or who will send it. Keep the omitted subject if natural in Polish.",
            recentContext: [
                turn("P1", "Kamu sudah periksa file laporan itu?"),
                turn("SELF", "Iya, semua angka sudah benar."),
            ],
            compareContext: true
        ),
        QwenFunctionalTranslationCase(
            id: "particle-dong",
            title: "Dong request particle",
            focus: "dong as a soft, mildly pleading request",
            input: "Tunggu sebentar dong.",
            intendedMeaning: "Please wait a moment.",
            preservationNotes: "Preserve the soft insistence; do not make it hostile or overly formal."
        ),
        QwenFunctionalTranslationCase(
            id: "particle-sih",
            title: "Sih playful blame",
            focus: "sih as conversational emphasis and teasing blame",
            input: "Kamu sih bikin aku kaget.",
            intendedMeaning: "You startled me; the speaker playfully blames the other person.",
            preservationNotes: "Keep the informal, teasing tone rather than translating sih literally."
        ),
        QwenFunctionalTranslationCase(
            id: "particle-nih",
            title: "Nih pointing particle",
            focus: "nih as emphatic pointing or presenting",
            input: "Ini nih yang aku maksud.",
            intendedMeaning: "This is exactly what I meant.",
            preservationNotes: "Preserve emphasis and conversational immediacy."
        ),
        QwenFunctionalTranslationCase(
            id: "particle-lah",
            title: "Lah acceptance particle",
            focus: "lah softening resignation",
            input: "Ya sudah lah, besok saja.",
            intendedMeaning: "All right then, tomorrow will do.",
            preservationNotes: "Keep the resigned, de-escalating tone."
        ),
        QwenFunctionalTranslationCase(
            id: "particle-kok",
            title: "Kok surprised question",
            focus: "kok as surprise or mild reproach",
            input: "Kok kamu belum tidur?",
            intendedMeaning: "Why are you still not asleep?",
            preservationNotes: "Keep the concerned, mildly surprised chat tone.",
            recentContext: [
                turn("P1", "Besok kamu harus bangun pagi untuk kerja."),
                turn("P2", "Aku masih belum ngantuk."),
            ],
            compareContext: true
        ),
        QwenFunctionalTranslationCase(
            id: "particle-masa",
            title: "Masa incredulous question",
            focus: "masa as disbelief or incredulity",
            input: "Masa harus aku jelasin lagi?",
            intendedMeaning: "Do I really have to explain it again?",
            preservationNotes: "Preserve incredulity, not a neutral information question."
        ),
        QwenFunctionalTranslationCase(
            id: "slang-wkwk",
            title: "Wkwk laughter slang",
            focus: "Indonesian chat laughter",
            input: "Aku salah masuk grup wkwk.",
            intendedMeaning: "I joined the wrong group, haha.",
            preservationNotes: "Render wkwk as natural laughter in Polish or preserve its light humorous effect."
        ),
        QwenFunctionalTranslationCase(
            id: "slang-mager",
            title: "Mager slang",
            focus: "mager meaning too lazy or unmotivated",
            input: "Hari ini aku mager banget.",
            intendedMeaning: "I am extremely unmotivated/lazy today and do not feel like doing anything.",
            preservationNotes: "Keep the casual self-description; do not turn it into a medical or moral judgment."
        ),
        QwenFunctionalTranslationCase(
            id: "slang-baper",
            title: "Baper slang",
            focus: "baper meaning taking something too personally",
            input: "Jangan baper, aku cuma bercanda.",
            intendedMeaning: "Do not take it personally; I was only joking.",
            preservationNotes: "Preserve the reassuring but teasing register."
        ),
        QwenFunctionalTranslationCase(
            id: "negative-gak",
            title: "Gak informal negation",
            focus: "gak variant and future participation",
            input: "Aku gak bisa ikut malam ini.",
            intendedMeaning: "I cannot join tonight.",
            preservationNotes: "Use informal Polish chat language without adding a reason."
        ),
        QwenFunctionalTranslationCase(
            id: "negative-nggak",
            title: "Nggak informal negation",
            focus: "nggak and polite refusal",
            input: "Nggak usah dijemput.",
            intendedMeaning: "There is no need to pick me up.",
            preservationNotes: "Preserve the polite, practical refusal and first-person implication.",
            recentContext: [
                turn("P1", "Aku bisa menjemputmu setelah kerja."),
                turn("SELF", "Aku sudah pesan ojek online."),
            ],
            compareContext: true
        ),
        QwenFunctionalTranslationCase(
            id: "negative-ga",
            title: "Ga question variant",
            focus: "ga spelling variant and change of plan",
            input: "Kamu ga jadi berangkat?",
            intendedMeaning: "Are you no longer going to leave/go?",
            preservationNotes: "Preserve the question about a changed plan, not a generic travel question.",
            recentContext: [
                turn("P1", "Bukannya kamu mau berangkat jam tujuh?"),
                turn("P2", "Iya, tapi hujan deras sekali."),
            ],
            compareContext: true
        ),
        QwenFunctionalTranslationCase(
            id: "kinship-bapak-tante",
            title: "Kinship terms",
            focus: "Bapak and Tante as family roles",
            input: "Bapak bilang Tante datang nanti.",
            intendedMeaning: "Dad/father said that Aunt will come later.",
            preservationNotes: "Preserve the family roles without replacing them with unrelated names or honorifics.",
            recentContext: [
                turn("P1", "Bapak adalah ayahku dan Tante adalah saudara perempuan ibuku."),
                turn("P2", "Kalau Tante datang, kita makan bersama."),
            ],
            compareContext: true
        ),
        QwenFunctionalTranslationCase(
            id: "code-switch-meeting",
            title: "Code-switched meeting message",
            focus: "Indonesian-English code-switching",
            input: "Meeting-nya diundur, jadi kita bisa santai dulu.",
            intendedMeaning: "The meeting has been postponed, so we can relax for now.",
            preservationNotes: "Translate the mixed-language message naturally and keep the relaxed tone."
        ),
        QwenFunctionalTranslationCase(
            id: "joke-treat",
            title: "Playful joke",
            focus: "conditional teasing and emoji",
            input: "Kalau telat lagi, kamu traktir ya 😄",
            intendedMeaning: "If you are late again, you have to treat us/pay for the meal, okay?",
            preservationNotes: "Keep the playful joke and emoji; do not turn it into a serious threat."
        ),
        QwenFunctionalTranslationCase(
            id: "quoted-reply",
            title: "Quoted reply reference",
            focus: "reply meaning supported by quoted message",
            input: "Aku nggak marah kok.",
            intendedMeaning: "I am not angry, really.",
            preservationNotes: "Keep the reassuring denial and connect it to the quoted question without translating the quote as extra output.",
            recentContext: [
                turn("P1", "Tadi kamu diam saja setelah aku bercanda."),
            ],
            quotedContext: quoted("P1", "Kamu marah sama aku?"),
            compareContext: true
        ),
        QwenFunctionalTranslationCase(
            id: "omitted-dia-station",
            title: "Dia with omitted gender",
            focus: "omitted subject context and later pickup",
            input: "Nanti aku jemput dia di stasiun.",
            intendedMeaning: "I will pick Rina up at the station later.",
            preservationNotes: "The context supports a feminine Polish pronoun; do not add a different destination or time.",
            recentContext: [
                turn("P1", "Rina tiba di stasiun sekitar jam delapan."),
                turn("P2", "Dia membawa koper besar."),
            ],
            compareContext: true
        ),
        QwenFunctionalTranslationCase(
            id: "particle-combo",
            title: "Combined particles",
            focus: "nih, kok, and sih in one reaction",
            input: "Serius nih? Kok bisa sih?",
            intendedMeaning: "Seriously? How is that even possible?",
            preservationNotes: "Preserve surprise and disbelief, not the literal particle words."
        ),
        QwenFunctionalTranslationCase(
            id: "negative-mixed",
            title: "Mixed negative and slang",
            focus: "ga, mager, and contrastive clarification",
            input: "Aku ga mager, cuma lagi capek aja.",
            intendedMeaning: "I am not being lazy; I am just tired.",
            preservationNotes: "Keep the contrast and defensive clarification in casual speech."
        ),
    ]

    public static let fixtures: [TranslationBenchmarkFixture] =
        cases.flatMap(makeFixtures)

    public static let smoke: TranslationBenchmarkFixture = fixtures[0]

    private static func makeFixtures(
        _ fixtureCase: QwenFunctionalTranslationCase
    ) -> [TranslationBenchmarkFixture] {
        var fixtures = [makeFixture(fixtureCase, mode: .none)]
        if fixtureCase.compareContext {
            fixtures.append(makeFixture(fixtureCase, mode: .bounded))
        }
        return fixtures
    }

    private static func makeFixture(
        _ fixtureCase: QwenFunctionalTranslationCase,
        mode: TranslationBenchmarkContextMode
    ) -> TranslationBenchmarkFixture {
        let recentContext = mode == .bounded ? fixtureCase.recentContext : []
        let quotedContext = mode == .bounded ? fixtureCase.quotedContext : nil
        let context = TranslationContext(
            target: TranslationTarget(speaker: .unknown, body: fixtureCase.input),
            recentTurns: recentContext,
            quotedTurn: quotedContext,
            summary: nil
        )
        let prompt: TranslationPrompt
        do {
            prompt = try TranslationPromptBuilder().build(
                sourceLanguage: "id",
                targetLanguage: "pl",
                context: context
            )
        } catch {
            preconditionFailure("Invalid Qwen functional fixture prompt: \(error)")
        }

        let suffix = mode == .bounded ? "context" : "no-context"
        let fixtureID = "qwen-\(fixtureCase.id)-\(suffix)"
        let requestID = TranslationRequestID(rawValue: fixtureID)!
        let languages = TranslationLanguagePair(
            sourceLanguage: "id",
            targetLanguage: "pl"
        )!
        let request = TranslationRequest(
            id: requestID,
            revision: 1,
            languages: languages,
            prompt: prompt,
            sourceText: fixtureCase.input
        )!
        let suppliedContext = TranslationBenchmarkContextSnapshot(
            recentTurns: recentContext.map {
                TranslationBenchmarkContextTurn($0)
            },
            quotedTurn: quotedContext.map {
                TranslationBenchmarkContextTurn(
                    speaker: $0.speaker.rawValue,
                    body: $0.body
                )
            }
        )

        return TranslationBenchmarkFixture(
            id: fixtureID,
            semanticCaseID: fixtureCase.id,
            title: fixtureCase.title,
            route: "Indonesian -> Polish",
            contextWindow: recentContext.count,
            contextMode: mode,
            focus: fixtureCase.focus,
            input: fixtureCase.input,
            suppliedContext: suppliedContext,
            intendedMeaning: fixtureCase.intendedMeaning,
            preservationNotes: fixtureCase.preservationNotes,
            request: request
        )
    }

    private static func turn(
        _ speaker: String,
        _ body: String
    ) -> TranslationContextTurn {
        TranslationContextTurn(
            speaker: alias(speaker),
            body: body
        )
    }

    private static func quoted(
        _ speaker: String,
        _ body: String
    ) -> TranslationQuotedTurn {
        TranslationQuotedTurn(
            speaker: alias(speaker),
            body: body
        )
    }

    private static func alias(_ rawValue: String) -> TranslationSpeakerAlias {
        guard let alias = TranslationSpeakerAlias(rawValue: rawValue) else {
            preconditionFailure("Invalid Qwen functional fixture speaker: \(rawValue)")
        }
        return alias
    }
}
