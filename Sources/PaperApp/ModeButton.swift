import SwiftUI

/// The one control the title bar carries. The shape says which mode the
/// window is in, an eye for presentation and an open book for reading, and
/// pressing it moves to the other one.
struct ModeButton: View {
    @ObservedObject var model: EditorModel

    private var label: String {
        "\(model.mode.label), press for \(model.mode.other.label)"
    }

    var body: some View {
        Button {
            model.mode = model.mode.other
        } label: {
            Image(systemName: model.mode == .presentation ? "eye" : "book")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
        .padding(.horizontal, 8)
    }
}
