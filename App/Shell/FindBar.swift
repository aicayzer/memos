import SwiftUI

struct FindBar: View {
    @Bindable var model: AppModel

    private var matches: EditorSearchState { model.editor.searchState }
    private var hasMatches: Bool { matches.query == model.findText && matches.total > 0 }
    private var canReplace: Bool { hasMatches && model.editor.caret.commands["replace"] == true }

    var body: some View {
        HStack(spacing: 4) {
            iconButton(model.showingReplacement ? "Hide Replacement" : "Show Replacement", symbol: "chevron.right") {
                withAnimation(.easeInOut(duration: 0.16)) { model.showingReplacement.toggle() }
            }
            .rotationEffect(.degrees(model.showingReplacement ? 90 : 0))
            .accessibilityValue(model.showingReplacement ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("find.disclosure")

            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    HStack(spacing: 6) {
                        OverlaySearchField(placeholder: "Find", text: $model.findText, fontSize: 13,
                                           isCurrent: { model.overlay == .find }, submit: { model.moveFind(1) },
                                           dismiss: model.dismissOverlay, previousSubmit: { model.moveFind(-1) })
                            .onChange(of: model.findText) { _, _ in model.find() }
                        if !model.findText.isEmpty {
                            Text("\(matches.current)/\(matches.total)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .accessibilityLabel("\(matches.current) of \(matches.total) matches")
                        }
                    }
                    .modifier(FindFieldStyle())
                    iconButton("Previous Match", symbol: "chevron.up") { model.moveFind(-1) }
                        .disabled(!hasMatches)
                    iconButton("Next Match", symbol: "chevron.down") { model.moveFind(1) }
                        .disabled(!hasMatches)
                    iconButton("Close Find", symbol: "xmark", action: model.dismissOverlay)
                }
                if model.showingReplacement {
                    GridRow {
                        OverlaySearchField(placeholder: "Replace with", text: $model.replacementText, fontSize: 13,
                                           isCurrent: { model.overlay == .find && model.showingReplacement },
                                           submit: { if canReplace { model.replaceFound(all: false) } },
                                           dismiss: model.dismissOverlay, initiallyFocused: false)
                            .modifier(FindFieldStyle())
                        iconButton("Replace", symbol: "arrow.uturn.right") { model.replaceFound(all: false) }
                            .disabled(!canReplace)
                        iconButton("Replace All", symbol: "arrow.triangle.2.circlepath") { model.replaceFound(all: true) }
                            .disabled(!canReplace)
                        Color.clear.frame(width: 26, height: 26).accessibilityHidden(true)
                    }
                }
            }
        }
        .font(.system(size: 13))
        .padding(8)
        .frame(maxWidth: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Find and Replace")
    }

    private func iconButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct FindFieldStyle: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: 28)
            .padding(.horizontal, 8)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.primary.opacity(0.22), lineWidth: 1 / displayScale)
                    .allowsHitTesting(false)
            }
    }
}
