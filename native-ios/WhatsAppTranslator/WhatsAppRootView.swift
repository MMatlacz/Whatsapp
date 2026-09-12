import SwiftUI
import CoreImage.CIFilterBuiltins
import WebKit

@MainActor
struct WhatsAppRootView: View {
    @State private var runtime: WhatsAppWebKitBridgeRuntime
    @State private var model: NativeChatModel
    @State private var showingSamples = false
    @State private var showingPairing = false
    @State private var connectionDiagnostic: String?

    init() {
        let runtime = WhatsAppWebKitBridgeRuntime()
        _runtime = State(initialValue: runtime)
        _model = State(initialValue: NativeChatModel.applicationModel(
            transport: WhatsAppWebTransport(runtime: runtime)))
    }

    var body: some View {
        TabView {
            Tab("Chats", systemImage: "bubble.left.and.bubble.right.fill") {
                NativeChatList(model: model)
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    Form {
                        Section("Connection") {
                            Text("Connection: \(model.connectionState.rawValue)")
                            Button("Link WhatsApp") { showingPairing = true }
                            Button("Reconnect saved session") { Task { await model.reconnect() } }
                                .disabled(model.isConnecting)
                            if let notice = model.connectionNotice { Text(notice).font(.footnote) }
                            Button("Check connection details") {
                                Task { connectionDiagnostic = await runtime.connectionDiagnostic() }
                            }
                            if let connectionDiagnostic { Text(connectionDiagnostic).font(.caption) }
                            Text("Your saved linking profile is preserved. This interface does not load an embedded web page.")
                                .foregroundStyle(.secondary)
                        }
                        Section("Translation") {
                            Label("Translation disabled", systemImage: "hand.raised")
                            Text("Model quality must pass validation before real messages can be translated.")
                        }
                        Section("Interface testing") {
                            Button("Open local sample chats") { showingSamples = true }
                            Text("Sample messages stay in memory and are never sent to WhatsApp.")
                                .font(.footnote)
                        }
                    }
                    .navigationTitle("Settings")
                }
            }
        }
        .tint(.green)
        .background {
            HiddenTransportHost(runtime: runtime)
                .frame(width: 1, height: 1).opacity(0)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .safeAreaInset(edge: .top) {
            if model.connectionState == .authenticating {
                Button("Link WhatsApp to load your chats") { showingPairing = true }
                    .buttonStyle(.borderedProminent).padding()
            }
            if let notice = model.storageNotice {
                Text(notice).font(.footnote).padding().background(.yellow.opacity(0.2))
            }
        }
        .task { await model.reconnect() }
        .sheet(isPresented: $showingSamples) { NativeSampleBrowser() }
        .sheet(isPresented: $showingPairing) { NativePairingView(runtime: runtime, model: model) }
    }
}

#if canImport(UIKit)
private struct HiddenTransportHost: UIViewRepresentable {
    let runtime: WhatsAppWebKitBridgeRuntime
    func makeUIView(context: Context) -> UIView {
        (try? runtime.ensureWebView()) ?? UIView()
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#else
private struct HiddenTransportHost: NSViewRepresentable {
    let runtime: WhatsAppWebKitBridgeRuntime
    func makeNSView(context: Context) -> NSView {
        (try? runtime.ensureWebView()) ?? NSView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

private struct NativePairingView: View {
    let runtime: WhatsAppWebKitBridgeRuntime
    let model: NativeChatModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var qrImage: CGImage?
    @State private var notice = "Preparing a linking code…"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("On your primary phone, open WhatsApp → Settings → Linked Devices → Link a Device, then scan this code.")
                    if let qrImage {
                        Image(decorative: qrImage, scale: 1)
                            .interpolation(.none).resizable().scaledToFit()
                            .frame(maxWidth: 300).padding(24).background(.white)
                            .accessibilityLabel("WhatsApp linking QR code")
                            .privacySensitive()
                    } else {
                        ProgressView().accessibilityLabel("Waiting for linking code")
                    }
                    Text(notice).font(.footnote)
                    Text("Keep this code private. Linking must be approved on your primary phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Link WhatsApp")
            .toolbar { Button("Close") { dismiss() } }
            .task(id: scenePhase) {
                guard scenePhase == .active else { qrImage = nil; return }
                await refreshUntilLinked()
            }
            .onDisappear { qrImage = nil }
        }
    }

    private func refreshUntilLinked() async {
        while !Task.isCancelled {
            do {
                if model.connectionState == .ready { qrImage = nil; dismiss(); return }
                let code = try await runtime.pairingCode()
                try Task.checkCancellation()
                if let code {
                    let filter = CIFilter.qrCodeGenerator()
                    filter.message = Data(code.utf8)
                    filter.correctionLevel = "M"
                    if let output = filter.outputImage {
                        qrImage = CIContext().createCGImage(output, from: output.extent)
                    }
                    notice = "Scan with your primary phone. The code updates automatically."
                } else {
                    qrImage = nil
                    notice = "Waiting for WhatsApp to provide a code or finish linking…"
                }
                try await Task.sleep(for: .seconds(3))
            } catch is CancellationError { return }
            catch {
                qrImage = nil
                notice = "Could not load the linking code. Close this screen and reconnect to retry."
                return
            }
        }
    }
}

private struct NativeSampleBrowser: View {
    @State private var model = NativeChatModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Button("Close sample chats") { dismiss() }.padding()
            NativeChatList(model: model)
        }
        .task { model.openSamples() }
    }
}

private struct NativeChatList: View {
    @Bindable var model: NativeChatModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter chats", selection: $model.filter) {
                        Text("All").tag(NativeChatModel.Filter.all)
                        Text("Unread").tag(NativeChatModel.Filter.unread)
                        Text("Groups").tag(NativeChatModel.Filter.groups)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    if model.isSample {
                        Label("Local sample chats · Nothing is sent", systemImage: "testtube.2")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.visibleChats, id: \.id) { chat in
                    NavigationLink(value: chat.id) {
                        NativeChatRow(chat: chat, preview: model.preview(for: chat.id))
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Chats")
            .searchable(text: $model.search, prompt: "Search chats")
            .overlay {
                if model.chats.isEmpty {
                    ContentUnavailableView {
                        Label("Native chats", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text(model.connectionNotice ?? "Connection: \(model.connectionState.rawValue)")
                    } actions: {
                        Button("Connect saved WhatsApp session") { Task { await model.reconnect() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isConnecting)
                        if model.isConnecting { ProgressView("Connecting privately…") }
                    }
                } else if model.visibleChats.isEmpty {
                    ContentUnavailableView.search(text: model.search)
                }
            }
            .navigationDestination(for: String.self) { chatID in
                NativeConversation(model: model, chatID: chatID)
            }
        }
    }
}

private struct NativeChatRow: View {
    let chat: WhatsAppTransportChat
    let preview: String

    var body: some View {
        HStack(spacing: 12) {
            NativeAvatar(title: chat.title, isGroup: chat.isGroup)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(chat.title).font(.headline).lineLimit(1)
                    Spacer()
                    if let time = chat.lastMessageTimestampMilliseconds {
                        Text(Date(timeIntervalSince1970: Double(time) / 1_000), format: .dateTime.hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    if chat.unreadCount > 0 {
                        Text(chat.unreadCount, format: .number)
                            .font(.caption.bold()).padding(6)
                            .foregroundStyle(.black).background(.green, in: Capsule())
                            .accessibilityLabel("\(chat.unreadCount) unread messages")
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct NativeAvatar: View {
    let title: String
    let isGroup: Bool
    @ScaledMetric private var size = 48.0

    var body: some View {
        ZStack {
            Circle().fill(.green.opacity(0.15))
            if isGroup {
                Image(systemName: "person.2.fill")
            } else {
                Text(String(title.prefix(1)).uppercased()).font(.title3.bold())
            }
        }
        .foregroundStyle(.green)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct NativeConversation: View {
    @Bindable var model: NativeChatModel
    let chatID: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if model.historyCursors[chatID] != nil {
                        Button("Load older messages") { Task { await model.load(chatID: chatID, older: true) } }
                            .disabled(model.loadingHistory.contains(chatID))
                    }
                    Text(model.isSample ? "LOCAL SAMPLE · NO NETWORK" : "Translation disabled")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical)
                    ForEach(model.messages[chatID] ?? [], id: \.id) { message in
                        NativeMessageBubble(message: message, translations: model.translations,
                                            translationKey: model.translationKey(chatID: chatID, messageID: message.id))
                            .contextMenu {
                                Button("Reply", systemImage: "arrowshape.turn.up.left") {
                                    model.quotes[chatID] = message
                                }
                            }
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .padding(.horizontal)
            }
            .background(.green.opacity(0.035))
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages[chatID]?.last?.id) {
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
            .safeAreaInset(edge: .bottom) { NativeComposer(model: model, chatID: chatID) }
            .navigationTitle(model.title(for: chatID))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .tabBar)
            #endif
            .task { await model.load(chatID: chatID) }
        }
    }
}

private struct NativeMessageBubble: View {
    let message: WhatsAppTransportMessage
    let translations: NativeTranslationModel
    let translationKey: NativeTranslationKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quote = message.quote {
                Text(quote.body ?? "Quoted message")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
            }
            if let body = message.body {
                NativeTranslationCard(model: translations, key: translationKey, original: body)
            } else {
                Text("Unsupported attachment")
            }
            HStack(spacing: 4) {
                Text(Date(timeIntervalSince1970: Double(message.timestampMilliseconds) / 1_000),
                     format: .dateTime.hour().minute())
                if message.fromMe { Text("Accepted") }
            }
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(message.fromMe ? Color.green.opacity(0.20) : Color.secondary.opacity(0.10),
                    in: .rect(cornerRadius: 16))
        .containerRelativeFrame(.horizontal, count: 6, span: 5, spacing: 0)
        .frame(maxWidth: .infinity, alignment: message.fromMe ? .trailing : .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct NativeComposer: View {
    @Bindable var model: NativeChatModel
    let chatID: String

    var body: some View {
        VStack(spacing: 8) {
            if let quote = model.quotes[chatID] {
                HStack {
                    Label(quote.body ?? "Message", systemImage: "arrowshape.turn.up.left")
                        .lineLimit(2).font(.footnote)
                    Spacer()
                    Button("Cancel reply", systemImage: "xmark.circle.fill") { model.quotes[chatID] = nil }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
            }
            if let error = model.errors[chatID] {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $model[draft: chatID], axis: .vertical)
                    .lineLimit(1...6).padding(12)
                    .background(.quaternary, in: .rect(cornerRadius: 22))
                    .accessibilityIdentifier("native-message-composer")
                Button {
                    Task { await model.send(chatID: chatID) }
                } label: {
                    Image(systemName: model.sending.contains(chatID) ? "hourglass" : "arrow.up")
                        .font(.headline).frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .disabled(!model.canSend(chatID: chatID))
                .accessibilityLabel(model.isSample ? "Send local sample message" : "Send message")
            }
        }
        .padding(.horizontal).padding(.vertical, 8).background(.regularMaterial)
    }
}
