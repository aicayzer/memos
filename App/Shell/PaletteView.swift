import SwiftUI

struct PaletteItem: Identifiable {
    let id: String
    var title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var shortcut: String? = nil
    var accented = false
    var section = 0
    var enabled = true
    let action: () -> Void
}

struct PaletteView: View {
    let placeholder: String
    let items: [PaletteItem]
    @Binding var query: String
    let dismiss: () -> Void

    @State private var selected = 0
    @State private var rowsHeight: CGFloat = 0
    @FocusState private var focused: Bool

    /// Set rather than padded, so the palette's height at its tallest is known to whatever places it.
    static let fieldHeight: CGFloat = 42
    /// The rows' padding, eight rows of actions with the divider between their sections, and a sliver of the
    /// ninth, so a longer list reads as one that scrolls. The memo list, with its taller rows, is cut at the
    /// same height, so both palettes are one size at their tallest.
    static let listHeight: CGFloat = 317
    static let maxHeight = fieldHeight + 1 + listHeight

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .frame(height: Self.fieldHeight)
                .focused($focused)
                .onSubmit(run)
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
            Divider()
            if items.isEmpty {
                Text("No results")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index > 0, items[index - 1].section != item.section {
                                    Divider().padding(.vertical, 6)
                                }
                                row(item, selected: index == selected && item.enabled)
                                    .id(item.id)
                                    .onTapGesture {
                                        guard item.enabled else { return }
                                        selected = index
                                        run()
                                    }
                            }
                        }
                        .padding(8)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                    }
                    // A scroll view fills what it is offered, so a short list is held to its rows.
                    .frame(maxHeight: min(rowsHeight, Self.listHeight))
                    .onChange(of: selected) { _, index in
                        if items.indices.contains(index) { proxy.scrollTo(items[index].id) }
                    }
                }
            }
        }
        .frame(maxWidth: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .onAppear {
            focused = true
            selected = items.firstIndex(where: \.enabled) ?? 0
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { dismiss() } }
        .onChange(of: items.map(\.id)) { _, _ in selected = items.firstIndex(where: \.enabled) ?? 0 }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let symbol = item.symbol {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(item.accented ? AnyShapeStyle(.tint) : AnyShapeStyle(item.subtitle == nil ? .primary : .secondary))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if let shortcut = item.shortcut {
                HStack(spacing: 3) {
                    ForEach(Array(shortcut.enumerated()), id: \.offset) { _, key in
                        Text(String(key))
                            .font(.system(size: 11, weight: .medium))
                            .frame(minWidth: 18, minHeight: 18)
                            .background(.quaternary, in: .rect(cornerRadius: 4))
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 35)
        .background(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .opacity(item.enabled ? 1 : 0.4)
    }

    private func move(_ delta: Int) {
        guard items.contains(where: \.enabled) else { return }
        var index = selected
        repeat {
            index = (index + delta + items.count) % items.count
        } while !items[index].enabled
        selected = index
    }

    private func run() {
        guard items.indices.contains(selected), items[selected].enabled else { return }
        let item = items[selected]
        dismiss()
        item.action()
    }
}
