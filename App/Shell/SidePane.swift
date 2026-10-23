import SwiftUI

/// The memo list beside the editor: a search field, then the memos in sections by recency.
struct SidePane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.chrome) private var chrome
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
                            .font(.system(size: chrome.iconSize - 3, weight: .semibold))
                            .frame(width: chrome.circleSize, height: chrome.circleSize)
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
                LazyVStack(spacing: 4) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.memos) { memo in
                                Button { open(memo) } label: { row(memo) }
                                    .contextMenu {
                                        Button(memo.favorite ? "Unfavorite Memo" : "Favorite Memo") {
                                            Task { await model.toggleFavorite(memo) }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(memo.id == model.current?.id ? .isSelected : [])
                            }
                        } header: {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold))
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
        return TimelineView(.periodic(from: .now, by: 60)) { context in
            MemoSidebarRow(title: isCurrent ? model.title : memo.title, updatedAt: memo.updatedAt, selected: isCurrent, now: context.date)
        }
    }

    private func open(_ memo: Memo) {
        Task {
            await model.open(memo.id)
        }
    }
}
