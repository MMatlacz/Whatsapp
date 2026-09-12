import SwiftUI

@MainActor
struct WhatsAppRootView: View {
    @State private var model = NativeChatModel()

    var body: some View {
        TabView {
            Tab("Chats", systemImage: "bubble.left.and.bubble.right.fill") {
                NativeChatList(model: model)
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    Form {
                        Section("Connection") {
                            Text("Native transport not connected")
                            Text("Your saved linking profile is preserved. This interface does not load an embedded web page.")
                                .foregroundStyle(.secondary)
                        }
                        Section("Translation") {
                            Label("Translation disabled", systemImage: "hand.raised")
                            Text("Model quality must pass validation before real messages can be translated.")
                        }
                        Section("Interface testing") {
                            Button("Open local sample chats") { model.openSamples() }
                            Text("Sample messages stay in memory and are never sent to WhatsApp.")
                                .font(.footnote)
                        }
                    }
                    .navigationTitle("Settings")
                }
            }
        }
        .tint(.green)
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
                        Text("The native interface is ready for a transport connection. Your linked profile is kept safely on this device.")
                    } actions: {
                        Button("Explore local sample chats") { model.openSamples() }
                            .buttonStyle(.borderedProminent)
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
                    Text(model.isSample ? "LOCAL SAMPLE · NO NETWORK" : "Translation disabled")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical)
                    ForEach(model.messages[chatID] ?? [], id: \.id) { message in
                        NativeMessageBubble(message: message)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quote = message.quote {
                Text(quote.body ?? "Quoted message")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
            }
            Text(message.body ?? "Unsupported attachment")
                .textSelection(.enabled)
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
        .accessibilityElement(children: .combine)
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
