import SwiftUI

/// The memo list beside the editor: a search field, then the memos in sections by recency.
struct SidePane: View {
    @Environment(AppModel.self) private var model
    let active: Bool
    @State private var query = ""
    @State private var groups: [MemoGroup] = []
    @State private var day = 0

    var body: some View {
        VStack(spacing: 0) {
            // The window buttons sit in this strip, so it drags and double-clicks as the top row does.
            Color.clear
                .contentShape(.rect)
                .gesture(WindowDragGesture())
                .onTapGesture(count: 2) { model.toggleSidePane() }
                .overlay(alignment: .trailing) {
                    Button { model.toggleSidePane() } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: Chrome.closeSize, height: Chrome.closeSize)
                            .glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    // Goes with the actions while the window is not key, as the top row's do.
                    .opacity(active ? 1 : 0)
                    .allowsHitTesting(active)
                    .animation(.easeOut(duration: 0.15), value: active)
                    .accessibilityLabel("Hide Side Pane")
                    .help("Hide Side Pane")
                }
                .frame(height: Chrome.rowHeight)
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
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.memos) { memo in
                                Button { open(memo) } label: { HoverHighlight { row(memo) } }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(memo.id == model.current?.id ? .isSelected : [])
                            }
                        } header: {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(width: Chrome.paneWidth)
        // The store changes on save, on favoriting and from outside, so those and the query drive the list, and
        // the day, since the sections follow it; the title of the memo being edited comes from the model until then.
        .task(id: RefreshKey(query: query, memo: model.current, day: day, store: model.storeGeneration)) {
            let listed = await model.memos(matching: query)
            guard !Task.isCancelled else { return }
            groups = MemoGroup.grouped(listed)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in day += 1 }
    }

    private struct RefreshKey: Equatable {
        let query: String
        let id: Memo.ID?
        let updatedAt: Date?
        let favorite: Bool?
        let day: Int
        let store: Int

        init(query: String, memo: Memo?, day: Int, store: Int) {
            self.query = query
            id = memo?.id
            updatedAt = memo?.updatedAt
            favorite = memo?.favorite
            self.day = day
            self.store = store
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
