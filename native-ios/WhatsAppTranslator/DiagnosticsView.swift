import Foundation
import FoundationModels
import Translation
import SwiftUI
import UIKit
import WebKit

@MainActor
struct DiagnosticsView: View {
    private let model = SystemLanguageModel.default
    @State private var page = WebPage()

    var body: some View {
        NavigationStack {
            List {
                Section("Runtime") {
                    diagnosticRow("OS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    diagnosticRow("Bundle", value: Bundle.main.bundleIdentifier ?? "unknown")
                }

                Section("Foundation Models") {
                    diagnosticRow("Availability", value: modelAvailability)
                    diagnosticRow("Context size", value: "\(model.contextSize) tokens")
                    diagnosticRow("Supported languages", value: "\(model.supportedLanguages.count)")
                    diagnosticRow("Indonesian (id_ID)", value: model.supportsLocale(Locale(identifier: "id_ID")) ? "supported" : "not advertised")
                    diagnosticRow("Polish (pl_PL)", value: model.supportsLocale(Locale(identifier: "pl_PL")) ? "supported" : "not advertised")
                }

                Section("Experimental Indonesian paths") {
                    diagnosticRow(
                        "Two-step provider",
                        value: "adapter ready; provider not configured"
                    )
                    diagnosticRow(
                        "Pipeline",
                        value: "Indonesian → English → Polish"
                    )
                    diagnosticRow(
                        "Multilingual local model",
                        value: "adapter ready; model not installed"
                    )

                    Text("Both paths are opt-in and currently diagnostic only. The router will not claim Indonesian support until a real provider or licensed local model returns validated output.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Benchmarks") {
                    NavigationLink("P0.1 SystemLanguageModel benchmark") {
                        P01BenchmarkView()
                    }

                    Text("Runs synthetic Indonesian/Polish translation prompts and exports a Markdown result table for docs/native/.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("WebKit") {
                    diagnosticRow("WebPage", value: "initialized")
                    diagnosticRow("Current URL", value: page.url?.absoluteString ?? "not loaded")
                    diagnosticRow("Persistent store", value: "default WKWebsiteDataStore")
                }

                Section("WhatsApp") {
                    diagnosticRow("Login state", value: "not evaluated (P0.3)")
                }

                Section {
                    Text("This screen verifies that the native app, Foundation Models, and WebKit are wired correctly. WhatsApp login is reported explicitly as not evaluated until the separate P0.3 transport spike loads WhatsApp Web.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Native iOS Spike")
        }
    }

    private var modelAvailability: String {
        switch model.availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return "unavailable: \(String(describing: reason))"
        }
    }

    @ViewBuilder
    private func diagnosticRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

@MainActor
struct P01BenchmarkView: View {
    @StateObject private var runner = P01BenchmarkRunner()
    @State private var didCopyMarkdownExport = false

    var body: some View {
        List {
            Section("Model gate") {
                benchmarkRow("Availability", value: runner.modelAvailability)
                benchmarkRow("Context size", value: "\(runner.model.contextSize) tokens")
                benchmarkRow("Supported languages", value: "\(runner.model.supportedLanguages.count)")
                benchmarkRow("Indonesian (id_ID)", value: runner.model.supportsLocale(Locale(identifier: "id_ID")) ? "advertised" : "not advertised")
                benchmarkRow("Polish (pl_PL)", value: runner.model.supportsLocale(Locale(identifier: "pl_PL")) ? "advertised" : "not advertised")
            }

            Section("Run") {
                Button(runner.isRunning ? "Running benchmark..." : "Run P0.1 benchmark") {
                    didCopyMarkdownExport = false
                    Task {
                        await runner.runAll()
                    }
                }
                .disabled(runner.isRunning)

                Text(runner.status)
                    .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Apple Translation framework") {
                benchmarkRow("Indonesian -> Polish", value: runner.translationFrameworkStatus)

                Button("Probe TranslationSession") {
                    Task {
                        await runner.runTranslationFrameworkProbe()
                    }
                }
                .disabled(runner.isRunning || runner.isTranslationFrameworkProbeRunning)

                Text("Diagnostic only: checks the system Translation framework as a fallback when Foundation Models rejects Indonesian.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                benchmarkRow(
                    "Indonesian -> English -> Polish",
                    value: runner.twoStepTranslationFrameworkStatus
                )

                Button("Probe two-step fallback") {
                    Task {
                        await runner.runTwoStepTranslationFrameworkProbe()
                    }
                }
                .disabled(
                    runner.isRunning
                        || runner.isTranslationFrameworkProbeRunning
                        || runner.isTwoStepTranslationFrameworkProbeRunning
                )

                Text("Runs two independent Translation.framework hops. It does not download a language model automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Benchmark matrix") {
                ForEach(P01BenchmarkFixtures.allRequests) { request in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.title)
                            .font(.headline)
                        Text("\(request.route) · context: \(request.contextWindow) messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(request.focus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Results") {
                if runner.results.isEmpty {
                    Text("No results yet. Run on a physical Apple-Intelligence-capable iPhone and copy the Markdown export into docs/native/p0.1-system-model-benchmark.md.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(runner.results) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(result.request.title)
                                    .font(.headline)
                                Spacer()
                                Text(result.elapsedMilliseconds.map { "\($0) ms" } ?? "no timing")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("Route: \(result.request.route); context: \(result.request.contextWindow)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let output = result.output {
                                Text(output)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }

                            if let errorMessage = result.errorMessage {
                                Text("Error category: \(result.errorCategory ?? "unknown")")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Markdown export") {
                Button {
                    UIPasteboard.general.string = runner.markdownExport
                    didCopyMarkdownExport = true
                } label: {
                    Label(
                        didCopyMarkdownExport ? "Copied all results" : "Copy all results",
                        systemImage: didCopyMarkdownExport ? "checkmark.circle" : "doc.on.doc"
                    )
                }
                .disabled(runner.results.isEmpty)
                .accessibilityHint("Copies the complete Markdown benchmark export to the clipboard.")

                if didCopyMarkdownExport {
                    Text("Full Markdown export copied to the clipboard.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(runner.markdownExport)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("P0.1 Benchmark")
    }

    @ViewBuilder
    private func benchmarkRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

@MainActor
final class P01BenchmarkRunner: ObservableObject {
    let model = SystemLanguageModel.default

    @Published private(set) var isRunning = false
    @Published private(set) var isTranslationFrameworkProbeRunning = false
    @Published private(set) var isTwoStepTranslationFrameworkProbeRunning = false
    @Published private(set) var status = "Not run"
    @Published private(set) var translationFrameworkStatus = "Not run"
    @Published private(set) var twoStepTranslationFrameworkStatus = "Not run"
    @Published private(set) var results: [P01BenchmarkResult] = []

    var modelAvailability: String {
        switch model.availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return "unavailable: \(String(describing: reason))"
        @unknown default:
            return "unknown future availability state"
        }
    }

    var markdownExport: String {
        let promptVersions = Set(
            results.map { $0.request.promptVersion.rawValue }
        )
        let promptVersionDescription = (promptVersions.isEmpty
            ? [TranslationPromptBuilder.currentVersion.rawValue]
            : promptVersions.sorted())
            .joined(separator: ", ")

        let header = """
        # P0.1 Apple SystemLanguageModel benchmark results

        ## Run metadata

        - Timestamp: \(ISO8601DateFormatter().string(from: Date()))
        - OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")
        - Model availability: \(modelAvailability)
        - Context size: \(model.contextSize) tokens
        - Supported languages count: \(model.supportedLanguages.count)
        - Supports Indonesian id_ID: \(model.supportsLocale(Locale(identifier: "id_ID")) ? "yes" : "no / not advertised")
        - Supports Polish pl_PL: \(model.supportsLocale(Locale(identifier: "pl_PL")) ? "yes" : "no / not advertised")
        - Translation prompt versions: \(promptVersionDescription)

        ## Results

        | Case | Route | Context messages | Latency | Result | Error category | Output / error |
        | --- | --- | ---: | ---: | --- | --- | --- |
        """

        let rows = results.map { result in
            let outcome = result.output == nil ? "error" : "success"
            let latency = result.elapsedMilliseconds.map { "\($0) ms" } ?? "n/a"
            let category = result.errorCategory ?? "n/a"
            let output = sanitizeMarkdownCell(result.output ?? result.errorMessage ?? "")
            return "| \(sanitizeMarkdownCell(result.request.title)) | \(result.request.route) | \(result.request.contextWindow) | \(latency) | \(outcome) | \(category) | \(output) |"
        }.joined(separator: "\n")

        let footer = """

        ## Manual quality notes

        Fill this in after reviewing the device output:

        - Indonesian -> English:
        - English -> Polish:
        - Indonesian -> Polish:
        - English prompt: Indonesian -> Polish:
        - ASCII/Base64 prompt: Indonesian -> Polish:
        - ASCII/Unicode-escape prompt: Indonesian -> Polish:
        - ASCII/Unicode-escape body prompt: Indonesian -> Polish:
        - Contextual Indonesian -> Polish, 0 messages:
        - Contextual Indonesian -> Polish, 3 messages:
        - Contextual Indonesian -> Polish, 8 messages:
        - Contextual Indonesian -> Polish, 16 messages:

        ## Decision

        Choose exactly one after the physical-device run:

        - [ ] Apple SystemLanguageModel is viable as the primary translator.
        - [ ] Apple SystemLanguageModel is partially viable and needs fallback.
        - [ ] Apple SystemLanguageModel is rejected for this product direction.

        ## Error interpretation

        Distinguish unsupported-language/runtime failures from poor translation quality:

        - Unsupported language or availability failure means the API/model cannot support the route on this device/locale combination.
        - Poor output quality means the route runs but produces unacceptable translations.
        """

        return [header, rows.isEmpty ? "| Not run | n/a | 0 | n/a | pending | n/a | Run the benchmark on device. |" : rows, footer]
            .joined(separator: "\n")
    }

    func runAll() async {
        guard !isRunning else { return }

        isRunning = true
        results = []
        status = "Running \(P01BenchmarkFixtures.allRequests.count) benchmark cases..."
        defer {
            isRunning = false
        }

        for (index, request) in P01BenchmarkFixtures.allRequests.enumerated() {
            status = "Running case \(index + 1) of \(P01BenchmarkFixtures.allRequests.count): \(request.title)"
            let started = Date()

            do {
                let session = LanguageModelSession(instructions: request.instructions)
                let response = try await session.respond(to: request.prompt)
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                results.append(
                    P01BenchmarkResult(
                        request: request,
                        elapsedMilliseconds: elapsed,
                        output: response.content,
                        errorCategory: nil,
                        errorMessage: nil
                    )
                )
            } catch {
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                results.append(
                    P01BenchmarkResult(
                        request: request,
                        elapsedMilliseconds: elapsed,
                        output: nil,
                        errorCategory: classify(error),
                        errorMessage: String(describing: error)
                    )
                )
            }
        }

        status = "Completed \(results.count) benchmark cases. Review output quality manually."
    }

    func runTranslationFrameworkProbe() async {
        guard !isTranslationFrameworkProbeRunning else { return }

        isTranslationFrameworkProbeRunning = true
        translationFrameworkStatus = "Checking language pair..."
        defer {
            isTranslationFrameworkProbeRunning = false
        }

        translationFrameworkStatus = await Self.translationFrameworkProbe()
    }

    func runTwoStepTranslationFrameworkProbe() async {
        guard !isTwoStepTranslationFrameworkProbeRunning else { return }

        isTwoStepTranslationFrameworkProbeRunning = true
        twoStepTranslationFrameworkStatus = "Checking Indonesian -> English -> Polish..."
        defer {
            isTwoStepTranslationFrameworkProbeRunning = false
        }

        let sourceToEnglish = SystemTranslationTextProvider()
        let englishToPolish = SystemTranslationTextProvider()

        let firstHopAvailability = await sourceToEnglish.availability(
            sourceLanguage: "id",
            targetLanguage: "en"
        )
        guard case .available = firstHopAvailability else {
            twoStepTranslationFrameworkStatus = "Indonesian -> English \(describe(firstHopAvailability))"
            return
        }

        let secondHopAvailability = await englishToPolish.availability(
            sourceLanguage: "en",
            targetLanguage: "pl"
        )
        guard case .available = secondHopAvailability else {
            twoStepTranslationFrameworkStatus = "English -> Polish \(describe(secondHopAvailability))"
            return
        }

        guard let pipeline = TwoStepTranslationProvider(
            intermediateLanguage: "en",
            sourceToIntermediate: sourceToEnglish,
            intermediateToTarget: englishToPolish,
            identifier: "apple-translation-two-step"
        ) else {
            twoStepTranslationFrameworkStatus = "invalid pipeline configuration"
            return
        }

        let availability = await pipeline.availability(
            sourceLanguage: "id",
            targetLanguage: "pl"
        )
        guard case .available = availability else {
            twoStepTranslationFrameworkStatus = "unavailable: \(String(describing: availability))"
            return
        }

        do {
            let output = try await pipeline.translate(
                text: "Dia bilang, nanti aja ya. Aku lagi mager banget nih, jangan dipaksa dong wkwk.",
                sourceLanguage: "id",
                targetLanguage: "pl"
            )
            twoStepTranslationFrameworkStatus = "success: \(output)"
        } catch {
            twoStepTranslationFrameworkStatus = "error: \(String(describing: error))"
        }
    }

    private func describe(_ availability: TranslationEngineAvailability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return "unavailable (\(String(describing: reason)))"
        }
    }

    /// Translation.framework currently exposes a non-Sendable session type.
    /// Keep the whole probe in a nonisolated async scope and return only text
    /// to the main-actor view model.
    nonisolated private static func translationFrameworkProbe() async -> String {
        let source = Locale.Language(identifier: "id")
        let target = Locale.Language(identifier: "pl")
        let availability = LanguageAvailability()
        let pairStatus = await availability.status(from: source, to: target)

        guard pairStatus != .unsupported else {
            return "unsupported pair (Translation framework)"
        }

        let session = TranslationSession(installedSource: source, target: target)
        guard await session.isReady else {
            return "pair \(String(describing: pairStatus)); model not installed/ready; downloads=\(session.canRequestDownloads)"
        }

        do {
            let response = try await session.translate(
                "Dia bilang, nanti aja ya. Aku lagi mager banget nih, jangan dipaksa dong wkwk."
            )
            return "pair \(String(describing: pairStatus)); \(response.targetText)"
        } catch {
            return "pair \(String(describing: pairStatus)); error: \(String(describing: error))"
        }
    }

    private func classify(_ error: Error) -> String {
        let description = String(describing: error).lowercased()

        if description.contains("language") || description.contains("locale") || description.contains("unsupported") {
            return "unsupported-language/runtime"
        }

        if description.contains("available") || description.contains("availability") || description.contains("not ready") {
            return "model-availability"
        }

        if description.contains("context") || description.contains("token") {
            return "context-size/runtime"
        }

        if description.contains("guardrail") || description.contains("safety") {
            return "guardrail/safety"
        }

        return "runtime-error"
    }

    private func sanitizeMarkdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}

struct P01BenchmarkResult: Identifiable {
    let id = UUID()
    let request: P01BenchmarkRequest
    let elapsedMilliseconds: Int?
    let output: String?
    let errorCategory: String?
    let errorMessage: String?
}

/// App-only adapter for Apple's system Translation framework. The core package
/// keeps this dependency out of its macOS-compatible target; the diagnostics
/// screen can still exercise the real two-hop provider on iOS Simulator/device.
private struct SystemTranslationTextProvider: TranslationTextProvider {
    let identifier: String

    init(identifier: String = "apple-translation-framework") {
        self.identifier = identifier
    }

    func availability(
        sourceLanguage: String,
        targetLanguage: String
    ) async -> TranslationEngineAvailability {
        guard let pair = TranslationLanguagePair(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ) else {
            return .unavailable(.unsupportedLanguagePair)
        }

        let availability = LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: pair.sourceLanguage),
            to: Locale.Language(identifier: pair.targetLanguage)
        )
        guard status != .unsupported else {
            return .unavailable(.unsupportedLanguagePair)
        }
        return .available
    }

    func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String {
        guard
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let pair = TranslationLanguagePair(
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        else {
            throw TranslationEngineFailure.invalidRequest
        }
        guard !Task.isCancelled else {
            throw TranslationEngineFailure.cancelled
        }

        let session = TranslationSession(
            installedSource: Locale.Language(identifier: pair.sourceLanguage),
            target: Locale.Language(identifier: pair.targetLanguage)
        )
        guard await session.isReady else {
            throw session.canRequestDownloads
                ? TranslationEngineFailure.unavailable
                : TranslationEngineFailure.transient
        }

        do {
            return try await session.translate(text).targetText
        } catch let failure as TranslationEngineFailure {
            throw failure
        } catch is CancellationError {
            throw TranslationEngineFailure.cancelled
        } catch {
            let description = String(describing: error).lowercased()
            if description.contains("unsupported") || description.contains("language") {
                throw TranslationEngineFailure.unsupported
            }
            throw TranslationEngineFailure.transient
        }
    }
}
