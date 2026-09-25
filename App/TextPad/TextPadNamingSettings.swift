import SwiftUI

struct TextPadNamingSettings: View {
    @Bindable var files: TextPad
    @State private var editingLiteral: Int?
    @State private var literalDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Default name")
                Spacer()
                Menu {
                    ForEach(TextPadNameToken.allCases) { token in
                        Button(token.title) { files.nameParts.append(.token(token)) }
                    }
                    Button("Text…") { editLiteral(at: files.nameParts.count, value: "") }
                    Divider()
                    Button("Reset") { files.nameParts = TextPadFilename.defaultParts }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Add name element")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(files.nameParts.enumerated()), id: \.offset) { index, part in
                        Menu {
                            switch part {
                            case let .literal(value):
                                Button("Edit Text…") { editLiteral(at: index, value: value) }
                            case .token:
                                ForEach(TextPadNameToken.allCases) { token in
                                    Button(token.title) { files.nameParts[index] = .token(token) }
                                }
                            }
                            Divider()
                            Button("Move Left") { files.nameParts.swapAt(index, index - 1) }
                                .disabled(index == 0)
                            Button("Move Right") { files.nameParts.swapAt(index, index + 1) }
                                .disabled(index == files.nameParts.count - 1)
                            Button("Remove", role: .destructive) { files.nameParts.remove(at: index) }
                        } label: {
                            switch part {
                            case let .token(token):
                                Text(token.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.tint.opacity(0.12), in: Capsule())
                            case let .literal(value):
                                Text(value).padding(.horizontal, 2).padding(.vertical, 4)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
                .frame(minHeight: 28)
            }
            .scrollIndicators(.hidden)
            HStack(alignment: .firstTextBaseline) {
                Text("Preview").foregroundStyle(.secondary)
                Text(files.namePreview).monospacedDigit().lineLimit(1).truncationMode(.middle)
            }
            .font(.caption)
        }
        .popover(isPresented: Binding(get: { editingLiteral != nil }, set: { if !$0 { editingLiteral = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Text", text: $literalDraft)
                    .onSubmit(saveLiteral)
                HStack {
                    Button("Cancel") { editingLiteral = nil }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Done", action: saveLiteral)
                        .keyboardShortcut(.defaultAction)
                        .disabled(literalDraft.isEmpty)
                }
            }
            .padding(16)
            .frame(width: 240)
        }
    }

    private func editLiteral(at index: Int, value: String) {
        literalDraft = value
        editingLiteral = index
    }

    private func saveLiteral() {
        guard let index = editingLiteral, !literalDraft.isEmpty else { return }
        if index == files.nameParts.count {
            files.nameParts.append(.literal(literalDraft))
        } else if files.nameParts.indices.contains(index) {
            files.nameParts[index] = .literal(literalDraft)
        }
        editingLiteral = nil
    }
}
