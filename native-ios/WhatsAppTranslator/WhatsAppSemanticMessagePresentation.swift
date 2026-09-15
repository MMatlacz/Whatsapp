import Foundation

struct WhatsAppSemanticMessagePresentation: Equatable, Sendable {
    let title: String
    let detail: String?
    let items: [String]
    let systemImage: String
    let accessibilityLabel: String
}

enum WhatsAppSemanticMessagePresenter {
    static func presentation(for content: WhatsAppTransportMessageContent) -> WhatsAppSemanticMessagePresentation? {
        switch content.kind {
        case .text, .media, .linkPreview:
            return nil
        case .location:
            guard let location = content.location else { return fallback("Location") }
            let title = bounded(location.name, 256) ?? "Location"
            let coordinate = String(format: "%.5f, %.5f", location.latitude, location.longitude)
            let detail = bounded(location.address, 1_024) ?? coordinate
            return make(title: title, detail: detail, items: [], image: "location", prefix: "Location")
        case .contact:
            let names = (content.contacts ?? []).prefix(8).map {
                bounded($0.displayName, 256) ?? "Contact card"
            }
            let title = names.count == 1 ? "Contact" : "Contacts"
            return make(title: title, detail: nil, items: Array(names), image: "person.crop.rectangle", prefix: title)
        case .poll:
            guard let poll = content.poll else { return fallback("Poll") }
            return make(
                title: bounded(poll.question, 2_048) ?? "Poll",
                detail: nil,
                items: poll.options.prefix(20).compactMap { bounded($0, 512) },
                image: "chart.bar.doc.horizontal",
                prefix: "Poll"
            )
        case .revoked:
            return make(title: "Message deleted", detail: nil, items: [], image: "trash", prefix: "Message deleted")
        case .system:
            guard let system = content.system else { return fallback("WhatsApp system message") }
            let title = bounded(system.text, 2_048) ?? "WhatsApp system message"
            let detail = bounded(system.type, 128)
            return make(title: title, detail: detail, items: [], image: "info.circle", prefix: "System message")
        case .unsupported:
            let rawType = bounded(content.rawType, 64) ?? "unknown"
            let title = "Unsupported WhatsApp message · \(rawType)"
            return make(title: title, detail: nil, items: [], image: "questionmark.bubble", prefix: title)
        }
    }

    private static func make(
        title: String, detail: String?, items: [String], image: String, prefix: String
    ) -> WhatsAppSemanticMessagePresentation {
        var parts = [prefix]
        if title != prefix { parts.append(title) }
        if let detail, !detail.isEmpty { parts.append(detail) }
        parts.append(contentsOf: items)
        return .init(
            title: title,
            detail: detail,
            items: items,
            systemImage: image,
            accessibilityLabel: parts.joined(separator: ". ")
        )
    }

    private static func fallback(_ title: String) -> WhatsAppSemanticMessagePresentation {
        make(title: title, detail: nil, items: [], image: "questionmark.bubble", prefix: title)
    }

    private static func bounded(_ value: String?, _ limit: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }
}
