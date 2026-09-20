import SwiftUI

struct FindBar: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in memo", text: $model.findText)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { model.find() }
                .onChange(of: model.findText) { _, _ in model.find() }
                .onKeyPress(.escape) { model.dismissOverlay(); return .handled }
            Button {
                model.dismissOverlay()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 280)
        .glassEffect(.regular, in: .capsule)
        .onAppear { focused = true }
    }
}
