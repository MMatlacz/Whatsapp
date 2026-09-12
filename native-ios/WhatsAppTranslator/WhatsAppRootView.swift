import SwiftUI

@MainActor
struct WhatsAppRootView: View {
    @StateObject private var session = WhatsAppSessionController()
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            WhatsAppChatsView(session: session)
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)
            WhatsAppWebProbeView(session: session, showChats: { selectedTab = 0 })
                .tabItem { Label("Session", systemImage: "person.crop.circle") }
                .tag(1)
            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(2)
        }
        .task { session.restoreIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.restoreIfNeeded() }
        }
    }
}

@MainActor
private struct WhatsAppChatsView: View {
    @ObservedObject var session: WhatsAppSessionController
    @State private var confirmingReload = false

    var body: some View {
        NavigationStack {
            Group {
                if let webView = session.webView {
                    WhatsAppWebPage(webView: webView, pageZoom: session.pageZoom)
                        .accessibilityIdentifier("whatsapp-chat-page")
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Your WhatsApp chats")
                            .font(.title2.bold())
                        Text("Link your account to browse chats and send messages. Your session stays on this device.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Open WhatsApp") { session.loadWhatsAppWeb() }
                            .buttonStyle(.borderedProminent)
                            .disabled(session.isDisconnecting)
                        Text("Translation is not enabled yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Chats")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if session.webView != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Reload WhatsApp", systemImage: "arrow.clockwise") { confirmingReload = true }
                            Divider()
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { zoom in
                                Button {
                                    session.setPageZoom(zoom)
                                } label: {
                                    if session.pageZoom == zoom {
                                        Label("Page size \(Int(zoom * 100))%", systemImage: "checkmark")
                                    } else {
                                        Text("Page size \(Int(zoom * 100))%")
                                    }
                                }
                            }
                        } label: {
                            Label("Page options", systemImage: "ellipsis.circle")
                        }
                        .disabled(session.isDisconnecting)
                    }
                }
            }
            .overlay(alignment: .top) {
                if session.isLoading { ProgressView().padding(8).background(.regularMaterial, in: Capsule()) }
            }
            .safeAreaInset(edge: .bottom) {
                if session.loadState == "failed" {
                    HStack {
                        Text("WhatsApp could not load. Check your connection and reload.")
                            .font(.footnote)
                        Button("Retry") { session.loadWhatsAppWeb() }
                    }
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .confirmationDialog("Reload WhatsApp?", isPresented: $confirmingReload, titleVisibility: .visible) {
                Button("Reload") { session.loadWhatsAppWeb() }
            } message: {
                Text("An unfinished message or linking step may be lost. Your saved account session is kept.")
            }
        }
    }
}
