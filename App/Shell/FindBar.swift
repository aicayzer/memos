import SwiftUI

struct FindBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            OverlaySearchField(placeholder: "Find in memo", text: $model.findText, fontSize: 13,
                               isCurrent: { model.overlay == .find }, submit: model.find,
                               dismiss: model.dismissOverlay)
                .onChange(of: model.findText) { _, _ in model.find() }
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
    }
}
