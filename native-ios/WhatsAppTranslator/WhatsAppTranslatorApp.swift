import SwiftUI

@main
struct WhatsAppTranslatorApp: App {
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
