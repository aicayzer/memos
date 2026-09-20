import SwiftUI

struct PaletteItem: Identifiable {
    let id: String
    var title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var shortcut: String? = nil
    var section = 0
    let action: () -> Void
}

/// A search field over a list of items, moved with the arrow keys, run with return, closed with escape.
struct PaletteView: View {
    let placeholder: String
    let items: [PaletteItem]
    @Binding var query: String
    let dismiss: () -> Void

    @State private var selected = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index > 0, items[index - 1].section != item.section {
                                    Divider().padding(.vertical, 6)
                                }
                                row(item, selected: index == selected)
                                    .id(item.id)
                                    .onTapGesture {
                                        selected = index
                                        run()
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: 360)
                    .onChange(of: selected) { _, index in
                        if items.indices.contains(index) { proxy.scrollTo(items[index].id) }
                    }
                }
            }
        }
        .frame(width: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .onAppear { focused = true }
        .onChange(of: items.map(\.id)) { _, _ in selected = 0 }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let symbol = item.symbol {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(item.subtitle == nil ? .primary : .secondary)
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
        .padding(.vertical, 7)
        .background(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
    }

    private func run() {
        guard items.indices.contains(selected) else { return }
        let item = items[selected]
        dismiss()
        item.action()
    }
}
