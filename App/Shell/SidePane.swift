import SwiftUI

/// The memo list beside the editor: a search field, then favorites and the rest by recency.
struct SidePane: View {
    @Environment(AppModel.self) private var model
    let active: Bool
    @State private var query = ""
    @State private var memos: [Memo] = []

    var body: some View {
        VStack(spacing: 0) {
            // The window buttons sit in this strip, so it drags and double-clicks as the top row does.
            Color.clear
                .frame(height: Chrome.rowHeight)
                .contentShape(.rect)
                .gesture(WindowDragGesture())
                .onTapGesture(count: 2) { model.toggleSidePane() }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { if let memo = await model.memos(matching: query).first { open(memo) } } }
                    .onKeyPress(.escape) {
                        query = ""
                        model.editor.focus()
                        return .handled
                    }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(memos) { memo in
                        Button { open(memo) } label: { HoverHighlight { row(memo) } }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(memo.id == model.current?.id ? .isSelected : [])
                    }
                }
                .padding(8)
            }
        }
        .frame(width: Chrome.paneWidth)
        // The store changes only on save and on favoriting, so those and the query drive the list; the title
        // of the memo being edited comes from the model until then.
        .task(id: RefreshKey(query: query, memo: model.current)) {
            let listed = await model.memos(matching: query)
            guard !Task.isCancelled else { return }
            memos = listed
        }
    }

    private struct RefreshKey: Equatable {
        let query: String
        let id: Memo.ID?
        let updatedAt: Date?
        let favorite: Bool?

        init(query: String, memo: Memo?) {
            self.query = query
            id = memo?.id
            updatedAt = memo?.updatedAt
            favorite = memo?.favorite
        }
    }

    private func row(_ memo: Memo) -> some View {
        let isCurrent = memo.id == model.current?.id
        return HStack(spacing: 8) {
            Image(systemName: memo.favorite ? "star.fill" : "doc.text")
                .frame(width: 16)
                .foregroundStyle(memo.favorite && active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(isCurrent ? model.title : memo.title)
                    .lineLimit(1)
                Text(memo.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }

    private func open(_ memo: Memo) {
        Task {
            await model.open(memo.id)
            model.editor.focus()
        }
    }
}
