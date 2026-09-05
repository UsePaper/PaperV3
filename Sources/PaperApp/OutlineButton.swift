import SwiftUI

/// The outline toggle in the title bar, beside the mode button. It shows
/// whether the panel is out, and it dims in source mode, where the outline
/// has nothing to point into.
struct OutlineButton: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        Button {
            model.isOutlineVisible.toggle()
        } label: {
            Image(systemName: "list.bullet.indent")
                .imageScale(.medium)
                .foregroundStyle(model.isOutlineVisible ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .disabled(model.showsSource)
        .help("Outline")
        .accessibilityLabel("Outline")
        .padding(.leading, 8)
    }
}
