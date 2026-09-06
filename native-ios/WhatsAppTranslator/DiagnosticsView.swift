import Foundation
import FoundationModels
import SwiftUI
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
                    Task {
                        await runner.runAll()
                    }
                }
                .disabled(runner.isRunning)

                Text(runner.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Benchmark matrix") {
                ForEach(P01BenchmarkFixtures.requests) { request in
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
    @Published private(set) var status = "Not run"
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
        status = "Running \(P01BenchmarkFixtures.requests.count) benchmark cases..."
        defer {
            isRunning = false
        }

        for (index, request) in P01BenchmarkFixtures.requests.enumerated() {
            status = "Running case \(index + 1) of \(P01BenchmarkFixtures.requests.count): \(request.title)"
            let started = Date()

            do {
                let session = LanguageModelSession(instructions: instructions(for: request))
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

    private func instructions(for request: P01BenchmarkRequest) -> String {
        """
        You are running a deterministic translation benchmark for a private local-first chat translation app.
        Translate faithfully. Preserve speaker identity, implied subject, tone, jokes, family terms, and quoted replies when context makes them clear.
        Do not add facts that are not in the input or context.
        Do not explain general translation theory.
        Return exactly this structure:
        Translation: <translated text>
        Confidence: high|medium|low
        Ambiguities: <short note, or none>

        Benchmark route: \(request.route)
        Evaluation focus: \(request.focus)
        """
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
