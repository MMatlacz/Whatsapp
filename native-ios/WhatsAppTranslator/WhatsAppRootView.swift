import SwiftUI
import WebKit
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct WhatsAppRootView: View {
    @AppStorage("translation.enabled") private var translationEnabled = true
    @State private var runtime: WhatsAppWebKitBridgeRuntime
    @State private var model: NativeChatModel
    @State private var showingSamples = false
    @State private var showingPairing = false
    @State private var connectionDiagnostic: String?

    init() {
        let runtime = WhatsAppWebKitBridgeRuntime()
        _runtime = State(initialValue: runtime)
        _model = State(initialValue: NativeChatModel.applicationModel(
            transport: WhatsAppWebTransport(runtime: runtime),
            identityProvider: runtime))
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
                            Button("Reconnect saved session") {
                                Task {
                                    runtime.prepareSessionPreservingReload()
                                    await model.reconnect()
                                }
                            }
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
                            Toggle("Translate messages", isOn: $translationEnabled)
                            Text(translationEnabled
                                 ? "Translation stays enabled. Messages run only through a model that has passed the quality and device stability gates."
                                 : "Translation is turned off.")
                                .font(.footnote).foregroundStyle(.secondary)
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
        .task {
            model.translations.experimentalTranslationEnabled = translationEnabled
            await model.reconnect()
        }
        .onChange(of: translationEnabled) { _, enabled in
            model.translations.experimentalTranslationEnabled = enabled
        }
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

@MainActor
private final class PairingBackgroundLease {
    #if canImport(UIKit)
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "WhatsApp phone linking") { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
    #else
    func begin() {}
    func end() {}
    #endif
}

private struct NativePairingView: View {
    let runtime: WhatsAppWebKitBridgeRuntime
    let model: NativeChatModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var phoneNumber = ""
    @State private var linkingCode: String?
    @State private var requestingCode = false
    @State private var notice = "Enter your WhatsApp number including country code."
    @State private var backgroundLease = PairingBackgroundLease()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Link this app with the phone number of your primary WhatsApp account.")
                    TextField("Phone number with country code", text: $phoneNumber)
                        .textFieldStyle(.roundedBorder)
                        .privacySensitive()
                        .textContentType(.telephoneNumber)
                    Button {
                        Task { await requestPhoneCode(refresh: false) }
                    } label: {
                        Label(requestingCode ? "Requesting code…" : "Get linking code", systemImage: "number")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(requestingCode || phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let linkingCode {
                        VStack(spacing: 10) {
                            Text("Enter this code on your primary phone")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(linkingCode)
                                .font(.system(.title2, design: .monospaced).weight(.semibold))
                                .textSelection(.enabled)
                                .privacySensitive()
                                .accessibilityLabel("WhatsApp phone linking code")
                            HStack {
                                Button("Refresh code") {
                                    Task { await requestPhoneCode(refresh: true) }
                                }
                                .disabled(requestingCode)
                                Button("Cancel code") {
                                    self.linkingCode = nil
                                    backgroundLease.end()
                                    Task { await runtime.cancelPhoneNumberLinking() }
                                }
                                .disabled(requestingCode)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.green.opacity(0.12), in: .rect(cornerRadius: 12))
                    }
                    Text("On your primary phone, open WhatsApp → Settings → Linked Devices → Link with phone number, then enter the code above.")
                        .font(.footnote)
                    Text(notice).font(.footnote)
                    Text("Keep your phone number and code private. Linking must be approved on your primary phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Link WhatsApp")
            .toolbar { Button("Close") { dismiss() } }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await refreshUntilLinked()
            }
            .onDisappear {
                linkingCode = nil
                backgroundLease.end()
                Task { await runtime.cancelPhoneNumberLinking() }
            }
        }
    }

    private func refreshUntilLinked() async {
        while !Task.isCancelled {
            if let previousCode = linkingCode,
               let currentCode = try? await runtime.startPhoneNumberLinking(phone: phoneNumber),
               currentCode != previousCode {
                linkingCode = currentCode
                notice = "WhatsApp refreshed the linking code. Enter the code currently shown above."
            }
            await model.refreshConnectionAfterPairing()
            if model.connectionState == .ready {
                linkingCode = nil
                backgroundLease.end()
                dismiss()
                return
            }
            if model.connectionState == .disconnected {
                notice = "Waiting for the saved WhatsApp session. Reconnect if the page is offline."
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func requestPhoneCode(refresh: Bool) async {
        guard !requestingCode else { return }
        requestingCode = true
        defer { requestingCode = false }
        do {
            let code = refresh
                ? try await runtime.refreshPhoneNumberLinking()
                : try await runtime.startPhoneNumberLinking(phone: phoneNumber)
            try Task.checkCancellation()
            linkingCode = code
            backgroundLease.begin()
            notice = "Code ready. Approve linking on your primary phone promptly; the app will keep the handshake active while you switch apps."
        } catch is CancellationError {
            return
        } catch let error as WhatsAppWebTransportError {
            switch error {
            case .invalidArgument:
                notice = "Enter a valid phone number with country code."
            case .bridgeUnavailable:
                notice = "WhatsApp is not ready to create a phone linking code. Reconnect and try again."
            default:
                notice = "WhatsApp could not create a linking code. Try again after reconnecting."
            }
        } catch {
            backgroundLease.end()
            notice = "WhatsApp could not create a linking code. Try again after reconnecting."
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
                        NativeChatRow(chat: chat, preview: model.preview(for: chat.id), identity: model.identities[chat.id])
                            .task(id: model.connectionState) { await model.loadIdentity(for: chat.id) }
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
    let identity: NativeContactIdentity?

    var body: some View {
        HStack(spacing: 12) {
            NativeAvatar(title: chat.title, isGroup: chat.isGroup, photo: identity?.photo)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(chat.isGroup ? chat.title : identity?.name ?? chat.title).font(.headline).lineLimit(1)
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
    var photo: Data? = nil
    var size = 48.0

    var body: some View {
        ZStack {
            Circle().fill(.green.opacity(0.15))
            if let photo, let source = CGImageSourceCreateWithData(photo as CFData, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 192,
                kCGImageSourceCreateThumbnailWithTransform: true
               ] as CFDictionary) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if isGroup {
                Image(systemName: "person.2.fill")
            } else {
                Text(String(title.prefix(1)).uppercased()).font(.title3.bold())
            }
        }
        .foregroundStyle(.green)
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct NativeConversation: View {
    @Bindable var model: NativeChatModel
    let chatID: String

    private func senderName(for message: WhatsAppTransportMessage) -> String? {
        guard !message.fromMe, let senderID = message.senderID,
              model.chats.first(where: { $0.id == chatID })?.isGroup == true else { return nil }
        return model.identities[senderID]?.name ?? "Group participant"
    }

    private func senderIdentity(for message: WhatsAppTransportMessage) -> NativeContactIdentity? {
        guard !message.fromMe, let senderID = message.senderID,
              model.chats.first(where: { $0.id == chatID })?.isGroup == true else { return nil }
        return model.identities[senderID]
    }

    private func quoteSenderName(for message: WhatsAppTransportMessage) -> String? {
        guard let senderID = message.quote?.senderID else { return nil }
        return model.identities[senderID]?.name
            ?? (model.chats.first(where: { $0.id == chatID })?.isGroup == true
                ? "Group participant" : "Contact")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if model.historyCursors[chatID] != nil {
                        Button("Load older messages") { Task { await model.load(chatID: chatID, older: true) } }
                            .disabled(model.loadingHistory.contains(chatID))
                    }
                    Text(model.isSample ? "LOCAL SAMPLE · NO NETWORK"
                         : model.translations.experimentalTranslationEnabled
                            ? "Translation enabled"
                            : "Translation disabled")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical)
                    ForEach(model.messages[chatID] ?? [], id: \.id) { message in
                        NativeMessageBubble(message: message, translations: model.translations,
                                            translationKey: model.translationKey(chatID: chatID, messageID: message.id),
                                            senderName: senderName(for: message),
                                            senderIdentity: senderIdentity(for: message),
                                            quoteSenderName: quoteSenderName(for: message))
                            .task(id: model.connectionState) {
                                if !message.fromMe, let senderID = message.senderID,
                                   model.chats.first(where: { $0.id == chatID })?.isGroup == true {
                                    await model.loadIdentity(for: senderID)
                                }
                                if let quoteSenderID = message.quote?.senderID {
                                    await model.loadIdentity(for: quoteSenderID)
                                }
                            }
                            .contextMenu {
                                Button("Reply", systemImage: "arrowshape.turn.up.left") {
                                    model.setReply(message, chatID: chatID)
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
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        NativeAvatar(title: model.title(for: chatID),
                                     isGroup: model.chats.first { $0.id == chatID }?.isGroup ?? false,
                                     photo: model.identities[chatID]?.photo)
                        Text(model.title(for: chatID)).font(.headline).lineLimit(1)
                    }
                }
            }
            .task(id: model.connectionState) {
                await model.loadIdentity(for: chatID)
                await model.load(chatID: chatID)
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .tabBar)
            #endif
        }
    }
}

private struct NativeMessageBubble: View {
    let message: WhatsAppTransportMessage
    let translations: NativeTranslationModel
    let translationKey: NativeTranslationKey
    let senderName: String?
    let senderIdentity: NativeContactIdentity?
    let quoteSenderName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let senderName {
                NativeAvatar(title: senderName, isGroup: false, photo: senderIdentity?.photo, size: 30)
                    .padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let senderName {
                    Text(senderName).font(.caption.bold()).foregroundStyle(.green)
                }
                if let quote = message.quote {
                    VStack(alignment: .leading, spacing: 2) {
                        if let quoteSenderName {
                            Text(quoteSenderName).font(.caption.bold()).foregroundStyle(.green)
                        }
                        Text(quote.body ?? "Quoted message")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
                }
                if let body = message.body {
                    NativeTranslationCard(model: translations, key: translationKey, original: body)
                }
                if let media = message.media {
                    Label(media.filename ?? media.kind.rawValue.capitalized, systemImage: "paperclip")
                    Text("Attachment preview is not available yet.").font(.caption).foregroundStyle(.secondary)
                } else if message.body == nil {
                    Text("Message content is unavailable")
                }
                HStack(spacing: 4) {
                    Text(Date(timeIntervalSince1970: Double(message.timestampMilliseconds) / 1_000),
                         format: .dateTime.hour().minute())
                    if message.fromMe, let deliveryState = message.deliveryState {
                        Label(deliveryState.displayName, systemImage: deliveryState.systemImage)
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
            .background(message.fromMe ? Color.green.opacity(0.20) : Color.secondary.opacity(0.10),
                        in: .rect(cornerRadius: 16))
        }
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
                    Button("Cancel reply", systemImage: "xmark.circle.fill") {
                        model.setReply(nil, chatID: chatID)
                    }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
            }
            if model.uncertainSends.contains(chatID) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.historyCheckedAfterUncertainSends.contains(chatID)
                         ? "This send is still unconfirmed after refreshing history."
                         : "This send may already have been delivered. Refresh history before retrying.")
                        .font(.footnote).foregroundStyle(.orange)
                    HStack {
                        Button("Refresh conversation") {
                            Task { await model.load(chatID: chatID) }
                        }
                        .disabled(model.loadingHistory.contains(chatID))
                        if model.historyCheckedAfterUncertainSends.contains(chatID) {
                            Button("Allow retry") { model.resolveUncertainSend(chatID: chatID) }
                        }
                    }
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
