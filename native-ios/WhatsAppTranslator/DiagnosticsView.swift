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

                Section("WebKit") {
                    diagnosticRow("WebPage", value: "initialized")
                    diagnosticRow("Current URL", value: page.url?.absoluteString ?? "not loaded")
                    diagnosticRow("Persistent store", value: "default WKWebsiteDataStore")
                }

                Section {
                    Text("This screen only verifies that the native app, Foundation Models, and WebKit are wired correctly. WhatsApp loading and translation prompts are separate architecture spikes.")
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
