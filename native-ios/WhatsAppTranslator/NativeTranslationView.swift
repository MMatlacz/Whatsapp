import SwiftUI

struct NativeTranslationCard: View {
    @Bindable var model: NativeTranslationModel
    let key: NativeTranslationKey
    let original: String
    @State private var sheet: TranslationSheet?

    private enum TranslationSheet: String, Identifiable {
        case correction, retranslate, vocabulary
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Original").font(.caption.bold()).foregroundStyle(.secondary)
            Text(original).textSelection(.enabled)
            Divider()
            Text("Translation · Polish").font(.caption.bold()).foregroundStyle(.secondary)
            if let record = model.record(for: key, original: original), !record.translatedText.isEmpty {
                Text(model.displayText(for: record, language: key.sourceLanguage)).textSelection(.enabled)
                if record.manuallyEdited {
                    Label("Manually corrected", systemImage: "pencil").font(.caption)
                } else if record.isSample {
                    Text("Sample translation · not model-generated").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Keep known words in original", isOn: $model.showKnownWords)
                    .font(.caption)
                if model.showKnownWords, record.parts.allSatisfy({ $0.source == nil }) {
                    Text("Word mappings are unavailable for this translation. Showing the full translation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Not translated. Automatic translation is disabled.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.experimentalTranslationEnabled {
                    Button("Translate experimentally", systemImage: "character.bubble") {
                        Task { await model.translate(key: key, original: original) }
                    }
                    .disabled(model.running.contains(key))
                }
            }
            if model.running.contains(key) { ProgressView("Translating locally…") }
            ViewThatFits(in: .horizontal) {
                HStack { correctionButton; wordsButton }
                VStack(alignment: .leading) { correctionButton; wordsButton }
            }
            Button("Retranslate with comment", systemImage: "arrow.clockwise") { sheet = .retranslate }
                .font(.caption).disabled(model.running.contains(key))
            if let notice = model.notices[key] { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let error = model.storageError { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .sheet(item: $sheet) { selected in
            switch selected {
            case .correction: NativeCorrectionEditor(model: model, key: key, original: original)
            case .retranslate: NativeRetranslationEditor(model: model, key: key, original: original)
            case .vocabulary: NativeKnownWordsEditor(model: model, key: key, original: original)
            }
        }
    }

    private var correctionButton: some View {
        Button("Fix translation", systemImage: "pencil") { sheet = .correction }.font(.caption)
    }

    private var wordsButton: some View {
        Button("Known words", systemImage: "text.badge.checkmark") { sheet = .vocabulary }.font(.caption)
    }
}

private struct NativeCorrectionEditor: View {
    let model: NativeTranslationModel
    let key: NativeTranslationKey
    let original: String
    @Environment(\.dismiss) private var dismiss
    @State private var parts: [NativeTranslationPart] = []
    @State private var revision = 0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Original — never changed") { Text(original) }
                Section {
                    ForEach($parts) { $part in
                        VStack(alignment: .leading) {
                            if let source = part.source { Text(source).font(.caption).foregroundStyle(.secondary) }
                            if part.id != "manual", part.source == nil,
                               part.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Word spacing (preserved)").font(.caption).foregroundStyle(.secondary)
                            } else {
                                TextField("Translation", text: $part.translation, axis: .vertical)
                                    .lineLimit(1...8)
                            }
                        }
                    }
                } header: {
                    Text("Correct the Polish translation")
                } footer: {
                    Text("Edit each mapped phrase to keep known-word display working. Changes stay on this device and never edit or send the WhatsApp message.")
                }
                if let error = model.storageError { Text(error).foregroundStyle(.red) }
                if let notice = model.notices[key] { Text(notice).font(.footnote) }
            }
            .navigationTitle("Fix translation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save correction") {
                        if model.saveCorrection(key: key, original: original, parts: parts, expectedRevision: revision) {
                            dismiss()
                        }
                    }
                    .disabled(parts.map(\.translation).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                guard !loaded else { return }
                let record = model.record(for: key, original: original)
                parts = record?.parts.isEmpty == false ? record?.parts ?? []
                    : [.init(id: "manual", source: nil, translation: "")]
                revision = record?.revision ?? 0
                loaded = true
            }
        }
    }
}

private struct NativeRetranslationEditor: View {
    let model: NativeTranslationModel
    let key: NativeTranslationKey
    let original: String
    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Original") { Text(original) }
                Section("What should change?") {
                    TextField("For example: keep the informal tone; this refers to tomorrow", text: $comment, axis: .vertical)
                        .lineLimit(3...8).accessibilityIdentifier("translation-comment")
                    Text("Your comment is saved locally. Until a validated engine is enabled, no retranslation runs and your existing translation is kept.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let notice = model.notices[key] { Text(notice).font(.footnote) }
                if let error = model.storageError { Text(error).foregroundStyle(.red) }
                Button("Retranslate with comment") {
                    Task { await model.retranslate(key: key, original: original, comment: comment) }
                }
                .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.running.contains(key))
            }
            .navigationTitle("Retranslate")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                guard !loaded else { return }
                comment = model.record(for: key, original: original)?.comment ?? ""
                loaded = true
            }
        }
    }
}

private struct NativeKnownWordsEditor: View {
    @Bindable var model: NativeTranslationModel
    let key: NativeTranslationKey
    let original: String
    @Environment(\.dismiss) private var dismiss

    private var selectableParts: [NativeTranslationPart] {
        model.record(for: key, original: original)?.parts.filter { $0.source != nil } ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Keep known words in original", isOn: $model.showKnownWords)
                } footer: {
                    Text("Select words or phrases you know. Their original-language form replaces only the corresponding mapped translation. Preferences apply to this source language.")
                }
                ForEach(selectableParts) { part in
                    if let source = part.source {
                        Button {
                            model.toggleKnown(source, language: key.sourceLanguage)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(source).foregroundStyle(.primary)
                                    Text(part.translation).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: model.isKnown(source, language: key.sourceLanguage)
                                      ? "checkmark.circle.fill" : "circle")
                            }
                        }
                        .accessibilityLabel("\(source), \(model.isKnown(source, language: key.sourceLanguage) ? "known" : "not known")")
                    }
                }
                if selectableParts.isEmpty {
                    Text("No validated word mappings yet. A plain translation cannot safely be split into word equivalents.")
                }
                if let error = model.storageError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Known words")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
