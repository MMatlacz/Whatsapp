import Foundation

/// The small-model candidates that are currently worth measuring for the
/// Indonesian -> Polish local translation path.
///
/// These entries are research metadata, not a claim that any candidate has
/// passed the physical-device or translation-quality gates. In particular,
/// the non-Qwen entries intentionally do not carry a revision or checksum yet;
/// the operator must record the exact snapshot used for every run.
public enum TranslationBenchmarkCandidateID: String, Codable, CaseIterable, Sendable {
    case gemma3_1BItQat4Bit = "gemma-3-1b-it-qat-4bit"
    case qwen3_5_0_8B4Bit = "qwen3.5-0.8b-4bit"
    case gemma3_270MIt4Bit = "gemma-3-270m-it-4bit"
}

public enum TranslationBenchmarkCandidateProvenance: String, Codable, Equatable, Sendable {
    /// The snapshot and integrity manifest are committed in this repository.
    case pinned
    /// The repository/weight estimate is known, but the exact snapshot is an
    /// operator-provided input and must be recorded with the run.
    case researchUnpinned
}

public struct TranslationBenchmarkCandidate: Codable, Equatable, Sendable {
    public let id: TranslationBenchmarkCandidateID
    public let displayName: String
    public let repositoryID: String
    public let license: String
    public let quantization: String
    /// Approximate published weight size used for screening; not an integrity
    /// assertion and not a peak resident-memory measurement.
    public let publishedWeightBytes: Int64?
    public let memoryBudgetBytes: Int64
    public let revision: String?
    public let tokenizerRevision: String?
    public let chatTemplateRevision: String?
    public let provenance: TranslationBenchmarkCandidateProvenance

    public init(
        id: TranslationBenchmarkCandidateID,
        displayName: String,
        repositoryID: String,
        license: String,
        quantization: String,
        publishedWeightBytes: Int64? = nil,
        memoryBudgetBytes: Int64 = 1_610_612_736,
        revision: String? = nil,
        tokenizerRevision: String? = nil,
        chatTemplateRevision: String? = nil,
        provenance: TranslationBenchmarkCandidateProvenance = .researchUnpinned
    ) {
        self.id = id
        self.displayName = displayName
        self.repositoryID = repositoryID
        self.license = license
        self.quantization = quantization
        self.publishedWeightBytes = publishedWeightBytes
        self.memoryBudgetBytes = memoryBudgetBytes
        self.revision = revision
        self.tokenizerRevision = tokenizerRevision
        self.chatTemplateRevision = chatTemplateRevision
        self.provenance = provenance
    }

    /// Priority order for P0.2d3. The 270M model is a lower-bound baseline,
    /// not expected to be the primary candidate.
    public static let catalog: [TranslationBenchmarkCandidate] = [
        TranslationBenchmarkCandidate(
            id: .gemma3_1BItQat4Bit,
            displayName: "Gemma 3 1B IT QAT 4-bit",
            repositoryID: "mlx-community/gemma-3-1b-it-qat-4bit",
            license: "Gemma Terms of Use",
            quantization: "4-bit QAT",
            publishedWeightBytes: 733_000_000
        ),
        TranslationBenchmarkCandidate(
            id: .qwen3_5_0_8B4Bit,
            displayName: "Qwen3.5 0.8B 4-bit",
            repositoryID: "mlx-community/Qwen3.5-0.8B-MLX-4bit",
            license: "Apache-2.0",
            quantization: "4-bit",
            publishedWeightBytes: 625_000_000
        ),
        TranslationBenchmarkCandidate(
            id: .gemma3_270MIt4Bit,
            displayName: "Gemma 3 270M IT 4-bit",
            repositoryID: "mlx-community/gemma-3-270m-it-4bit",
            license: "Gemma Terms of Use",
            quantization: "4-bit",
            publishedWeightBytes: 151_000_000
        ),
    ]

    public static func candidate(
        for id: TranslationBenchmarkCandidateID
    ) -> TranslationBenchmarkCandidate {
        // The catalog is source-controlled and exhaustive for the enum.
        catalog.first { $0.id == id }!
    }

    /// Resolve the CLI spelling while keeping the report's ID canonical.
    public static func resolve(_ rawValue: String) -> TranslationBenchmarkCandidate? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let id = TranslationBenchmarkCandidateID(rawValue: normalized) {
            return candidate(for: id)
        }

        switch normalized {
        case "gemma3-1b", "gemma-3-1b", "gemma-3-1b-it", "gemma1b",
             "mlx-community/gemma-3-1b-it-qat-4bit":
            return candidate(for: .gemma3_1BItQat4Bit)
        case "qwen3.5-0.8b", "qwen35-0.8b", "qwen3-5-0.8b", "qwen35",
             "mlx-community/qwen3.5-0.8b-mlx-4bit":
            return candidate(for: .qwen3_5_0_8B4Bit)
        case "gemma3-270m", "gemma-3-270m", "gemma270m",
             "mlx-community/gemma-3-270m-it-4bit":
            return candidate(for: .gemma3_270MIt4Bit)
        default:
            return nil
        }
    }

    public var isPinned: Bool {
        provenance == .pinned
            && revision != nil
            && tokenizerRevision != nil
            && chatTemplateRevision != nil
    }

    /// Attach an operator-recorded immutable snapshot revision to a catalog
    /// entry. The catalog remains research-level until the corresponding
    /// artifact sizes and checksums are also captured.
    public func withSnapshotRevision(_ snapshotRevision: String) -> TranslationBenchmarkCandidate? {
        let value = snapshotRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return TranslationBenchmarkCandidate(
            id: id,
            displayName: displayName,
            repositoryID: repositoryID,
            license: license,
            quantization: quantization,
            publishedWeightBytes: publishedWeightBytes,
            memoryBudgetBytes: memoryBudgetBytes,
            revision: value,
            tokenizerRevision: tokenizerRevision ?? value,
            chatTemplateRevision: chatTemplateRevision ?? value,
            provenance: provenance
        )
    }
}

public struct TranslationBenchmarkCandidateInput: Equatable, Sendable {
    public let candidate: TranslationBenchmarkCandidate
    public let directory: URL

    public init(
        candidate: TranslationBenchmarkCandidate,
        directory: URL
    ) {
        self.candidate = candidate
        self.directory = directory.standardizedFileURL
    }
}

public enum TranslationBenchmarkCandidateRunStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
}

/// A candidate run can be exported even when provisioning or inference fails.
/// That keeps a missing model visible in a bake-off instead of silently
/// comparing only the candidates that happened to be installed.
public struct TranslationBenchmarkCandidateRun: Codable, Equatable, Sendable {
    public let candidate: TranslationBenchmarkCandidate
    public let status: TranslationBenchmarkCandidateRunStatus
    public let report: TranslationBenchmarkReport?
    public let errorCategory: String?
    public let errorDescription: String?

    public init(
        candidate: TranslationBenchmarkCandidate,
        status: TranslationBenchmarkCandidateRunStatus,
        report: TranslationBenchmarkReport? = nil,
        errorCategory: String? = nil,
        errorDescription: String? = nil
    ) {
        self.candidate = candidate
        self.status = status
        self.report = report
        self.errorCategory = errorCategory
        self.errorDescription = errorDescription
    }
}

public struct TranslationBenchmarkBakeoffReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let timestamp: String
    public let sourceRevision: String?
    public let corpus: String
    public let fixtureIDs: [String]
    public let candidates: [TranslationBenchmarkCandidateRun]

    public init(
        timestamp: String,
        sourceRevision: String?,
        corpus: String,
        fixtureIDs: [String],
        candidates: [TranslationBenchmarkCandidateRun]
    ) {
        self.schemaVersion = 1
        self.timestamp = timestamp
        self.sourceRevision = sourceRevision
        self.corpus = corpus
        self.fixtureIDs = fixtureIDs
        self.candidates = candidates
    }
}
