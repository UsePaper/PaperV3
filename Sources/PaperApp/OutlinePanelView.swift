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

    var body: some View {
        card
            .frame(width: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .onHover(perform: onHoverChange)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityLabel("Outline")
    }

    @ViewBuilder
    private var card: some View {
        if state.entries.isEmpty {
            Text("No headings")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(12)
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
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(state.entries.enumerated()), id: \.offset) { index, entry in
                entryButton(index: index, entry: entry)
            }
        }
        .padding(8)
    }

    private func entryButton(index: Int, entry: OutlineHeading) -> some View {
        let isActive = index == state.activeIndex
        return Button {
            onSelect(index)
        } label: {
            Text(entry.text.isEmpty ? "\u{2014}" : entry.text)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The indent carries the level, the way the hashes do.
                .padding(.leading, CGFloat(entry.level - 1) * 12)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background(
            isActive ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
