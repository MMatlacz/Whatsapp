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
