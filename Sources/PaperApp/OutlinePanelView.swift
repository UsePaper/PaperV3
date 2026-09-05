import PaperCore
import SwiftUI

/// What the panel shows, owned by the controller and observed by the view.
final class OutlinePanelState: ObservableObject {
    @Published var entries: [OutlineHeading] = []
    /// The entry whose section is under the top of the page, or the one
    /// just clicked.
    @Published var activeIndex: Int?
}

/// The floating card that lists the headings. Geometry and withdrawal live
/// in `OutlinePanelController`; this view only renders and reports.
struct OutlinePanelView: View {
    @ObservedObject var state: OutlinePanelState
    var onSelect: (Int) -> Void
    var onHoverChange: (Bool) -> Void

    @State private var hoveredIndex: Int?

    var body: some View {
        card
            .frame(width: 220)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .onHover(perform: onHoverChange)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityLabel("Outline")
    }

    @ViewBuilder
    private var card: some View {
        if state.entries.isEmpty {
            Text("No headings")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        } else {
            // The card hugs its content until the window runs out of room,
            // then the same list scrolls instead.
            ViewThatFits(in: .vertical) {
                list
                ScrollView { list }
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(state.entries.enumerated()), id: \.offset) { index, entry in
                entryRow(index: index, entry: entry)
            }
        }
        .padding(6)
    }

    private func entryRow(index: Int, entry: OutlineHeading) -> some View {
        let isActive = index == state.activeIndex
        let isHovered = index == hoveredIndex
        return Button {
            onSelect(index)
        } label: {
            HStack(spacing: 7) {
                // A quiet tick marks the section being read; the text alone
                // carries the rest, the way the find bar stays wordless.
                Capsule()
                    .fill(isActive ? Color.accentColor : .clear)
                    .frame(width: 2.5, height: 11)
                Text(entry.text.isEmpty ? "\u{2014}" : entry.text)
                    .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The indent carries the level, the way the hashes do.
            .padding(.leading, 6 + CGFloat(entry.level - 1) * 11)
            .padding(.trailing, 8)
            .padding(.vertical, 4.5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isActive
                ? AnyShapeStyle(.primary)
                : isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
        )
        .background(
            isHovered ? AnyShapeStyle(Color.primary.opacity(0.06)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { hovering in
            hoveredIndex = hovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
        }
        .animation(.easeOut(duration: 0.12), value: hoveredIndex)
        .animation(.easeOut(duration: 0.12), value: state.activeIndex)
    }
}
