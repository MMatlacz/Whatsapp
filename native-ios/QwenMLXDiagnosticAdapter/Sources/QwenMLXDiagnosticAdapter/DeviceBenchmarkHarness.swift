import Foundation
import TranslationCore

public enum QwenMLXBenchmarkSessionError: Error, Equatable, Sendable {
    case invalidTimeout
}

public actor QwenMLXBenchmarkSession {
    private let verifiedArtifacts: QwenMLXVerifiedArtifacts
    private let limits: QwenMLXDiagnosticLimits
    private var model: QwenMLXDiagnosticModel?

    public init(
        verifiedArtifacts: QwenMLXVerifiedArtifacts,
        limits: QwenMLXDiagnosticLimits = .benchmark
    ) {
        self.verifiedArtifacts = verifiedArtifacts
        self.limits = limits
    }

    public func resetModelForColdRun() {
        model = nil
    }

    public func runSharedP01(
        timestamp: String,
        sourceRevision: String?,
        physicalDeviceEvidence: PhysicalDeviceEnvironmentEvidence = .notRun,
        timeoutSeconds: Int = 120
    ) async throws -> TranslationBenchmarkReport {
        guard let runner = TranslationBenchmarkRunner(
            executor: QwenMLXBenchmarkExecutor(
                model: activeModel(),
                limits: limits
            ),
            timeoutSeconds: timeoutSeconds
        ) else {
            throw QwenMLXBenchmarkSessionError.invalidTimeout
        }

        let results = await runner.run(
            fixtures: P01SharedTranslationBenchmarkFixtures.unencoded
        )
        return TranslationBenchmarkReport(
            timestamp: timestamp,
            sourceRevision: sourceRevision,
            model: TranslationBenchmarkModelProvenance(
                manifest: verifiedArtifacts.manifest
            ),
            maxGeneratedTokens: limits.maxGeneratedTokens,
            physicalDeviceEvidence: physicalDeviceEvidence,
            results: results
        )
    }

    private func activeModel() -> QwenMLXDiagnosticModel {
        if let model {
            return model
        }
        let model = QwenMLXDiagnosticModel(
            verifiedArtifacts: verifiedArtifacts,
            limits: limits
        )
        self.model = model
        return model
    }
}

public enum QwenDeviceBenchmarkHarnessPhase: String, Equatable, Sendable {
    case idle
    case verifying
    case ready
    case running
    case cancelling
    case completed
    case failed
}

public struct QwenDeviceBenchmarkHarnessState: Equatable, Sendable {
    public private(set) var phase: QwenDeviceBenchmarkHarnessPhase
    public private(set) var modelDirectoryPath: String?
    public private(set) var exportAvailable: Bool
    public private(set) var statusMessage: String

    public init() {
        self.phase = .idle
        self.modelDirectoryPath = nil
        self.exportAvailable = false
        self.statusMessage = "Import the verified Qwen model folder to begin."
    }

    public mutating func beginVerification() {
        phase = .verifying
        exportAvailable = false
        statusMessage = "Copying and verifying local model artifacts…"
    }

    public mutating func verificationSucceeded(directory: URL) {
        phase = .ready
        modelDirectoryPath = directory.standardizedFileURL.path
        exportAvailable = false
        statusMessage = "Verified local model artifacts. Ready to benchmark."
    }

    public mutating func verificationFailed(_ message: String) {
        phase = .failed
        modelDirectoryPath = nil
        exportAvailable = false
        statusMessage = message
    }

    @discardableResult
    public mutating func beginRun() -> Bool {
        guard modelDirectoryPath != nil else {
            verificationFailed("No verified local model is available.")
            return false
        }
        phase = .running
        exportAvailable = false
        statusMessage = "Running the shared P0.1 benchmark…"
        return true
    }

    public mutating func requestCancellation() {
        guard phase == .running else { return }
        phase = .cancelling
        statusMessage = "Cancellation requested…"
    }

    public mutating func runCompleted(exportAvailable: Bool) {
        phase = .completed
        self.exportAvailable = exportAvailable
        statusMessage = exportAvailable
            ? "Benchmark finished. Export is ready."
            : "Benchmark finished without an export."
    }

    public mutating func runFailed(_ message: String) {
        phase = .failed
        exportAvailable = false
        statusMessage = message
    }

    public mutating func resetForColdRun() {
        guard modelDirectoryPath != nil else {
            phase = .idle
            exportAvailable = false
            statusMessage = "Import the verified Qwen model folder to begin."
            return
        }
        phase = .ready
        exportAvailable = false
        statusMessage = "Model state reset. The next run will begin cold."
    }
}
