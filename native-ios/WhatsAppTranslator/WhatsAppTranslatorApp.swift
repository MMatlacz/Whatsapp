import SwiftUI
#if DEBUG
import QwenMLXDiagnosticAdapter
#endif

@main
struct WhatsAppTranslatorApp: App {
    #if DEBUG
    init() {
        // Explicit local diagnostic launch only. Never routes chat messages.
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--translation-token-probe"),
              arguments.indices.contains(flag + 1),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let revision = arguments[flag + 1]
        let directory = documents.appendingPathComponent("TranslationProbe", isDirectory: true)
        Task {
            do {
                try await TranslationTokenProbe.run(
                    modelDirectory: directory.appendingPathComponent("model", isDirectory: true),
                    inputFile: directory.appendingPathComponent("input.json"),
                    outputFile: directory.appendingPathComponent("output.json"),
                    sourceRevision: revision, limit: 36
                )
            } catch {
                let failure = ["status": "failed", "failure": String(describing: error)]
                if let data = try? JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys]) {
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try? data.write(to: directory.appendingPathComponent("failure.json"), options: .atomic)
                }
            }
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            TabView {
                DiagnosticsView()
                    .tabItem {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }

                WhatsAppWebProbeView()
                    .tabItem {
                        Label("WebKit Probe", systemImage: "globe")
                    }
            }
        }
    }
}
