import PaperCore
import SwiftUI

/// The thin bar along the bottom of a window: the file on the left, the
/// word count on the right. The same bar in every mode, because what it
/// reports is the document, not the way it is being looked at.
struct StatusBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack {
            Text(fileText)
            Spacer()
            Text(wordText)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var fileText: String {
        var parts = [model.fileName ?? "Not saved"]
        if model.isDirty {
            parts.append("unsaved changes")
        }
        return parts.joined(separator: " · ")
    }

    private var wordText: String {
        let words = WordCount.count(model.content)
        return words == 1 ? "1 word" : "\(words) words"
    }
}
