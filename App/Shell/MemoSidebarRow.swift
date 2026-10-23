import SwiftUI

struct MemoSidebarRow: View {
    let title: String
    let updatedAt: Date
    let selected: Bool
    let now: Date
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Self.relativeDate(updatedAt, now: now))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(selected ? 0.085 : hovering ? 0.045 : 0), in: .rect(cornerRadius: 9))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .help("\(title)\n\(updatedAt.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(updatedAt.formatted(.relative(presentation: .named)))
    }

    static func relativeDate(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        for (unit, suffix) in [(31_536_000.0, "y"), (2_592_000, "mo"), (604_800, "w"), (86_400, "d"), (3_600, "h"), (60, "m")] {
            if seconds >= unit { return "\(Int(seconds / unit))\(suffix)" }
        }
        return "now"
    }
}
