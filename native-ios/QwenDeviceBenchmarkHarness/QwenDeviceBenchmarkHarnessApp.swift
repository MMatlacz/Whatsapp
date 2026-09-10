import Darwin
import Foundation
import QwenMLXDiagnosticAdapter
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct QwenDeviceBenchmarkHarnessApp: App {
    init() {
        guard let configuration = QwenSimulatorCIConfiguration.current else {
            return
        }

        Task { @MainActor in
            await QwenSimulatorCIRunner.run(configuration)
        }
    }

    var body: some Scene {
        WindowGroup {
            QwenDeviceBenchmarkView()
        }
    }
}

@MainActor
private struct QwenDeviceBenchmarkView: View {
    @StateObject private var controller = QwenDeviceBenchmarkController()
    @State private var showingImporter = false
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Verified local model") {
                    Text(controller.state.statusMessage)
                    if let path = controller.state.modelDirectoryPath {
                        Text(path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Button("Import Qwen model folder") {
                        showingImporter = true
                    }
                    .disabled(controller.isBusy)
                }

                Section("Benchmark") {
                    TextField(
                        "Source revision (git SHA)",
                        text: $controller.sourceRevision
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button(controller.offlineButtonTitle) {
                        controller.cycleOfflineObservation()
                    }
                    .disabled(controller.isBusy)

                    Button("Run shared P0.1 benchmark") {
                        controller.runFullBenchmark()
                    }
                    .disabled(!controller.canRun)

                    Button("Cancel in-flight benchmark", role: .destructive) {
                        controller.cancelRun()
                    }
                    .disabled(!controller.canCancel)

                    Button("Reset model for cold run") {
                        controller.resetForColdRun()
                    }
                    .disabled(!controller.canResetColdState)
                }

                Section("Current environment") {
                    LabeledContent("Device", value: controller.deviceSummary)
                    LabeledContent("OS", value: controller.osSummary)
                    LabeledContent("Thermal", value: controller.thermalSummary)
                    LabeledContent("Battery", value: controller.batterySummary)
                    Text(
                        "Simulator/macOS validation is never promoted to physical-device acceptance. On-device evidence remains unknown until #114 records the complete run, memory measurement, quality review, and decision."
                    )
                    .font(.caption)
                }

                if let report = controller.report {
                    Section("Last report") {
                        LabeledContent(
                            "Cases",
                            value: "\(report.results.count) / 7"
                        )
                        LabeledContent(
                            "Device evidence",
                            value: report.physicalDeviceEvidence.state.rawValue
                        )
                        LabeledContent(
                            "Contract",
                            value: report.evaluationContract.version
                        )
                        Text(TranslationBenchmarkExporter.markdownSummary(report))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(24)
                    }

                    Section("Export") {
                        Button("Copy Markdown summary") {
                            controller.copyMarkdown()
                        }
                        Button("Copy report JSON") {
                            controller.copyJSON()
                        }
                        Button("Share report files") {
                            showingShareSheet = true
                        }
                        .disabled(controller.exportFiles.isEmpty)
                    }
                }
            }
            .navigationTitle("Qwen Device Benchmark")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await controller.importModelFolder(url)
                }
            case .failure(let error):
                controller.recordImporterFailure(error)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(activityItems: controller.exportFiles)
        }
        .onAppear {
            controller.refreshEnvironmentSummary()
        }
    }
}

private enum OfflineObservation: String, Sendable {
    case notRun
    case passed
    case failed

    var evidence: PhysicalDeviceEvidenceState {
        switch self {
        case .notRun:
            .notRun
        case .passed:
            .passed
        case .failed:
            .failed
        }
    }
}

@MainActor
private final class QwenDeviceBenchmarkController: ObservableObject {
    @Published private(set) var state = QwenDeviceBenchmarkHarnessState()
    @Published var sourceRevision = ""
    @Published private(set) var report: TranslationBenchmarkReport?
    @Published private(set) var exportFiles: [URL] = []
    @Published private(set) var deviceSummary = "unknown"
    @Published private(set) var osSummary = "unknown"
    @Published private(set) var thermalSummary = "unknown"
    @Published private(set) var batterySummary = "unknown"

    private var session: QwenMLXBenchmarkSession?
    private var runTask: Task<Void, Never>?
    private var cancellationRequested = false
    private var offlineObservation: OfflineObservation = .notRun

    var isBusy: Bool {
        switch state.phase {
        case .verifying, .running, .cancelling:
            true
        default:
            false
        }
    }

    var canRun: Bool { session != nil && !isBusy }

    var canCancel: Bool {
        state.phase == .running || state.phase == .cancelling
    }

    var canResetColdState: Bool { session != nil && !isBusy }

    var offlineButtonTitle: String {
        "Offline-after-provisioning: \(offlineObservation.rawValue)"
    }

    func importModelFolder(_ sourceURL: URL) async {
        guard !isBusy else { return }
        state.beginVerification()
        report = nil
        exportFiles = []
        cancellationRequested = false

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let destination = try await Task.detached(priority: .userInitiated) {
                try Self.copyModelFolderIntoApplicationSupport(sourceURL)
            }.value
            let verified = try await Task.detached(priority: .userInitiated) {
                try QwenMLXArtifactVerifier.verify(directory: destination)
            }.value

            session = QwenMLXBenchmarkSession(verifiedArtifacts: verified)
            state.verificationSucceeded(directory: verified.directory)
            refreshEnvironmentSummary()
        } catch {
            session = nil
            state.verificationFailed(
                "Model import/verification failed: \(error.localizedDescription)"
            )
        }
    }

    func recordImporterFailure(_ error: Error) {
        state.verificationFailed(
            "Model folder selection failed: \(error.localizedDescription)"
        )
    }

    func runFullBenchmark() {
        guard runTask == nil, let session else { return }
        guard state.beginRun() else { return }

        cancellationRequested = false
        report = nil
        exportFiles = []
        refreshEnvironmentSummary()

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let revision = normalizedSourceRevision
        let initialEvidence = environmentEvidence(
            cancellationBehavior: .notRun
        )

        runTask = Task { [weak self] in
            guard let self else { return }
            defer { runTask = nil }

            do {
                let initialReport = try await session.runSharedP01(
                    timestamp: timestamp,
                    sourceRevision: revision,
                    physicalDeviceEvidence: initialEvidence,
                    timeoutSeconds: 120
                )
                let hasCancelledResult = initialReport.results.contains {
                    $0.termination == .cancelled
                }
                let cancellationEvidence: PhysicalDeviceEvidenceState
                if cancellationRequested {
                    cancellationEvidence = hasCancelledResult ? .passed : .failed
                } else {
                    cancellationEvidence = .notRun
                }

                let finalReport = TranslationBenchmarkReport(
                    timestamp: initialReport.timestamp,
                    sourceRevision: initialReport.sourceRevision,
                    model: initialReport.model,
                    maxGeneratedTokens: initialReport.maxGeneratedTokens,
                    evaluationContract: initialReport.evaluationContract,
                    physicalDeviceEvidence: environmentEvidence(
                        cancellationBehavior: cancellationEvidence
                    ),
                    results: initialReport.results,
                    corpus: initialReport.corpus,
                    timeoutSeconds: initialReport.timeoutSeconds
                )

                report = finalReport
                exportFiles = try writeExport(finalReport)
                state.runCompleted(exportAvailable: !exportFiles.isEmpty)
                refreshEnvironmentSummary()
            } catch {
                state.runFailed("Benchmark failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelRun() {
        guard canCancel else { return }
        cancellationRequested = true
        state.requestCancellation()
        runTask?.cancel()
    }

    func resetForColdRun() {
        guard let session, !isBusy else { return }
        Task { [weak self] in
            await session.resetModelForColdRun()
            guard let self else { return }
            state.resetForColdRun()
        }
    }

    func cycleOfflineObservation() {
        switch offlineObservation {
        case .notRun:
            offlineObservation = .passed
        case .passed:
            offlineObservation = .failed
        case .failed:
            offlineObservation = .notRun
        }
    }

    func copyMarkdown() {
        guard let report else { return }
        UIPasteboard.general.string = TranslationBenchmarkExporter.markdownSummary(report)
    }

    func copyJSON() {
        guard
            let report,
            let data = try? TranslationBenchmarkExporter.encodeReport(report),
            let string = String(data: data, encoding: .utf8)
        else {
            return
        }
        UIPasteboard.general.string = string
    }

    func refreshEnvironmentSummary() {
        deviceSummary = Self.machineIdentifier()
        osSummary = "\(UIDevice.current.systemVersion) — \(ProcessInfo.processInfo.operatingSystemVersionString)"
        thermalSummary = Self.thermalStateDescription(
            ProcessInfo.processInfo.thermalState
        )
        batterySummary = Self.batteryObservation()
    }

    private var normalizedSourceRevision: String? {
        let value = sourceRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func environmentEvidence(
        cancellationBehavior: PhysicalDeviceEvidenceState
    ) -> PhysicalDeviceEnvironmentEvidence {
        let xcodeVersion = Self.bundleString("DTXcode")
        let xcodeBuild = Self.bundleString("DTXcodeBuild")
        let sdkVersion = Self.bundleString("DTSDKName")
        let offlineEvidence = offlineObservation.evidence

#if targetEnvironment(simulator)
        let evidenceState: PhysicalDeviceEvidenceState = .notRun
#else
        let evidenceState: PhysicalDeviceEvidenceState = .unknown
#endif

        var unknown = [
            "peakMemoryBytes",
            "peakMemoryMeasurementSource",
        ]
        if normalizedSourceRevision == nil {
            unknown.append("sourceRevision")
        }
        if offlineObservation == .notRun {
            unknown.append("offlineAfterProvisioning")
        }
        if cancellationBehavior == .notRun || cancellationBehavior == .unknown {
            unknown.append("cancellationBehavior")
        }
        if xcodeVersion == nil { unknown.append("xcodeVersion") }
        if xcodeBuild == nil { unknown.append("xcodeBuild") }
        if sdkVersion == nil { unknown.append("sdkVersion") }

        return PhysicalDeviceEnvironmentEvidence(
            state: evidenceState,
            deviceModel: Self.machineIdentifier(),
            osVersion: UIDevice.current.systemVersion,
            osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
            xcodeVersion: xcodeVersion,
            xcodeBuild: xcodeBuild,
            sdkVersion: sdkVersion,
            sourceRevision: normalizedSourceRevision,
            provisioningState: session == nil ? nil : "verified-local-copy",
            offlineAfterProvisioning: offlineEvidence,
            cancellationBehavior: cancellationBehavior,
            peakMemoryBytes: nil,
            peakMemoryMeasurementSource: nil,
            thermalObservation: Self.thermalStateDescription(
                ProcessInfo.processInfo.thermalState
            ),
            batteryObservation: Self.batteryObservation(),
            unknownMeasurements: unknown
        )
    }

    private func writeExport(
        _ report: TranslationBenchmarkReport
    ) throws -> [URL] {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent(
            "QwenDeviceBenchmarkExport",
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try TranslationBenchmarkExporter.write(report: report, to: directory)

        var urls = [
            directory.appendingPathComponent("report.json"),
            directory.appendingPathComponent("summary.md"),
        ]
        urls.append(contentsOf: report.results.map {
            directory
                .appendingPathComponent("results", isDirectory: true)
                .appendingPathComponent("\($0.fixtureID).json")
        })
        return urls
    }

    nonisolated private static func copyModelFolderIntoApplicationSupport(
        _ sourceURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = applicationSupport.appendingPathComponent(
            "QwenDeviceBenchmarkHarness",
            isDirectory: true
        )
        let destination = root.appendingPathComponent("model", isDirectory: true)

        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)

        var mutableDestination = destination
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableDestination.setResourceValues(values)
        return destination
    }

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let capacity = MemoryLayout.size(ofValue: systemInfo.machine)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }

    private static func thermalStateDescription(
        _ state: ProcessInfo.ThermalState
    ) -> String {
        switch state {
        case .nominal:
            "nominal"
        case .fair:
            "fair"
        case .serious:
            "serious"
        case .critical:
            "critical"
        @unknown default:
            "unknown"
        }
    }

    private static func batteryObservation() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state: String
        switch UIDevice.current.batteryState {
        case .unknown:
            state = "unknown"
        case .unplugged:
            state = "unplugged"
        case .charging:
            state = "charging"
        case .full:
            state = "full"
        @unknown default:
            state = "unknown"
        }

        let level = UIDevice.current.batteryLevel
        if level < 0 {
            return "level=unknown; state=\(state)"
        }
        return String(
            format: "level=%.0f%%; state=%@",
            level * 100,
            state
        )
    }

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) else {
            return nil
        }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private struct QwenSimulatorCIConfiguration: Sendable {
    let modelDirectory: URL
    let outputFile: URL
    let sourceRevision: String?

    static var current: QwenSimulatorCIConfiguration? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let modelPath = value(
                for: "--qwen-ci-model-dir",
                in: arguments
            ),
            let outputPath = value(
                for: "--qwen-ci-output",
                in: arguments
            ),
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        else {
            return nil
        }

        return QwenSimulatorCIConfiguration(
            modelDirectory: documents.appendingPathComponent(
                modelPath,
                isDirectory: true
            ),
            outputFile: documents.appendingPathComponent(outputPath),
            sourceRevision: value(
                for: "--qwen-ci-source-revision",
                in: arguments
            )
        )
    }

    private static func value(
        for name: String,
        in arguments: [String]
    ) -> String? {
        guard let index = arguments.firstIndex(of: name) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        let value = arguments[valueIndex]
        return value.isEmpty ? nil : value
    }
}

private struct QwenSimulatorCIResult: Codable {
    let timestamp: String
    let status: String
    let executionEnvironment: String
    let durationSeconds: TimeInterval
    let model: TranslationBenchmarkModelProvenance?
    let result: TranslationBenchmarkResultRecord?
    let fullResultCount: Int?
    let fullFailureCount: Int?
    let fullReportDirectory: String?
    let failure: String?
}

private enum QwenSimulatorCIRunner {
    static func run(
        _ configuration: QwenSimulatorCIConfiguration
    ) async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let timestamp = ISO8601DateFormatter().string(from: Date())

        do {
            let verified = try QwenMLXArtifactVerifier.verify(
                directory: configuration.modelDirectory
            )
            let limits = QwenMLXDiagnosticLimits.functionalCI
            let provenance = TranslationBenchmarkModelProvenance(
                manifest: verified.manifest,
                generation: QwenMLXGenerationSettings(limits: limits),
                executionEnvironment: "ios-simulator"
            )
            let runner = try makeRunner(
                verified: verified,
                limits: limits
            )
            guard let result = await runner.run(
                fixtures: [QwenFunctionalTranslationBenchmarkFixtures.smoke]
            ).first else {
                throw NSError(
                    domain: "QwenSimulatorCIRunner",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No smoke result was produced."]
                )
            }
            let passed = isSuccessful(result)
            guard passed else {
                let envelope = QwenSimulatorCIResult(
                    timestamp: timestamp,
                    status: "failed",
                    executionEnvironment: "ios-simulator",
                    durationSeconds: elapsed(since: startedAt),
                    model: provenance,
                    result: result,
                    fullResultCount: nil,
                    fullFailureCount: nil,
                    fullReportDirectory: nil,
                    failure: "Smoke result was not valid non-empty text."
                )
                try write(envelope, to: configuration.outputFile)
                print("QWEN_CI_SIMULATOR_SMOKE_STATUS=failed")
                Darwin.exit(EXIT_FAILURE)
            }

            let results = await runner.run(
                fixtures: QwenFunctionalTranslationBenchmarkFixtures.fixtures
            )
            let reportDirectory = configuration.outputFile
                .deletingLastPathComponent()
                .appendingPathComponent("QwenFunctionalReport", isDirectory: true)
            let report = TranslationBenchmarkReport(
                timestamp: timestamp,
                sourceRevision: configuration.sourceRevision,
                model: provenance,
                maxGeneratedTokens: limits.maxGeneratedTokens,
                results: results,
                corpus: "qwen-functional",
                timeoutSeconds: 120
            )
            try TranslationBenchmarkExporter.write(
                report: report,
                to: reportDirectory
            )
            let failures = results.filter { !isSuccessful($0) }.count
            let fullPassed = failures == 0
            let envelope = QwenSimulatorCIResult(
                timestamp: timestamp,
                status: fullPassed ? "passed" : "failed",
                executionEnvironment: "ios-simulator",
                durationSeconds: elapsed(since: startedAt),
                model: provenance,
                result: result,
                fullResultCount: results.count,
                fullFailureCount: failures,
                fullReportDirectory: reportDirectory.lastPathComponent,
                failure: fullPassed ? nil : "Full functional benchmark had invalid result records."
            )
            try write(envelope, to: configuration.outputFile)
            print("QWEN_CI_SIMULATOR_SMOKE_STATUS=passed")
            print("QWEN_CI_SIMULATOR_BENCHMARK_STATUS=\(fullPassed ? "passed" : "failed")")
            Darwin.exit(fullPassed ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            let envelope = QwenSimulatorCIResult(
                timestamp: timestamp,
                status: "failed",
                executionEnvironment: "ios-simulator",
                durationSeconds: elapsed(since: startedAt),
                model: nil,
                result: nil,
                fullResultCount: nil,
                fullFailureCount: nil,
                fullReportDirectory: nil,
                failure: String(describing: error)
            )
            try? write(envelope, to: configuration.outputFile)
            print("QWEN_CI_SIMULATOR_SMOKE_STATUS=failed")
            print("QWEN_CI_SIMULATOR_SMOKE_ERROR=\(error)")
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func makeRunner(
        verified: QwenMLXVerifiedArtifacts,
        limits: QwenMLXDiagnosticLimits
    ) throws -> TranslationBenchmarkRunner {
        let model = QwenMLXDiagnosticModel(
            verifiedArtifacts: verified,
            limits: limits
        )
        let executor = QwenMLXBenchmarkExecutor(
            model: model,
            limits: limits
        )
        guard let runner = TranslationBenchmarkRunner(
            executor: executor,
            timeoutSeconds: 120
        ) else {
            throw NSError(
                domain: "QwenSimulatorCIRunner",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid smoke timeout."]
            )
        }
        return runner
    }

    private static func isSuccessful(
        _ result: TranslationBenchmarkResultRecord
    ) -> Bool {
        result.termination == .returned
            && result.outputValidity == .validText
            && !(result.output ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private static func write(
        _ result: QwenSimulatorCIResult,
        to fileURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(result).write(to: fileURL, options: .atomic)
    }

    private static func elapsed(since startedAt: TimeInterval) -> TimeInterval {
        max(0, ProcessInfo.processInfo.systemUptime - startedAt)
    }
}
