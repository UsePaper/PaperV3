import SwiftUI

/// The settings, as one grouped form: eight settings in two groups, no
/// tabs, no search. Keep this short. A ninth setting needs a reason.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var confirmingReset = false

    /// The form covers no document, but it floats over one, so the font and
    /// the size still cannot be judged anywhere else: the specimen shows them.
    private static let specimenText = "The quick brown fox jumps over the lazy dog."

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: binding(\.theme)) {
                        Text("System").tag(Theme.system)
                        Text("Light").tag(Theme.light)
                        Text("Dark").tag(Theme.dark)
                    }
                    .pickerStyle(.segmented)

                    Picker("Font", selection: binding(\.font)) {
                        ForEach(Settings.bodyFonts) { choice in
                            Text(choice.label).tag(choice.id)
                        }
                    }

                    textSizeRow

                    Picker("Line width", selection: measureBinding) {
                        ForEach(Settings.measurePresets, id: \.id) { preset in
                            Text(preset.label).tag(preset.id)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Line height", selection: leadingBinding) {
                        ForEach(Settings.leadingPresets, id: \.id) { preset in
                            Text(preset.label).tag(preset.id)
                        }
                    }
                    .pickerStyle(.segmented)

                    specimen
                }

                Section("Behavior") {
                    Toggle("Status bar", isOn: binding(\.statusbar))

                    // Named "Opens in" rather than "Default mode" because the
                    // difference that matters is when it takes effect: the
                    // next window, not this one.
                    Picker("Opens in", selection: binding(\.defaultMode)) {
                        Text(ViewMode.presentation.label).tag(ViewMode.presentation)
                        Text(ViewMode.reading.label).tag(ViewMode.reading)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Spellcheck", isOn: binding(\.spellcheck))
                }
            }
            .formStyle(.grouped)

            Divider()

            // Asked about first. The settings are cheap to set again, but
            // not to remember, and a form has no undo.
            HStack {
                Button("Reset…") { confirmingReset = true }
                Spacer()
            }
            .padding(12)
        }
        // Tall enough that all eight rows show without scrolling.
        .frame(width: 400, height: 560)
        .alert("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every setting goes back to its default. Your documents are not touched.")
        }
    }

    /// The small and large A are the standard text size affordance.
    private var textSizeRow: some View {
        LabeledContent("Text size") {
            HStack(spacing: 8) {
                Text("A").font(.system(size: 11))
                Slider(value: fontSizeBinding, in: sizeRange, step: 1)
                Text("A").font(.system(size: 17))
            }
            .foregroundStyle(.secondary)
        }
    }

    private var specimen: some View {
        Text(Self.specimenText)
            .font(.custom(
                store.settings.fontChoice.postScriptName,
                size: CGFloat(store.settings.fontSize)
            ))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bindings

    private func binding<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }

    private var sizeRange: ClosedRange<Double> {
        Double(Settings.fontSizeRange.lowerBound)...Double(Settings.fontSizeRange.upperBound)
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(store.settings.fontSize) },
            set: { value in store.update { $0.fontSize = Int(value.rounded()) } }
        )
    }

    /// The stored number stays a number; the control offers the named
    /// presets and shows the one closest to what is stored.
    private var measureBinding: Binding<String> {
        Binding(
            get: { store.settings.measurePreset.id },
            set: { id in
                guard let preset = Settings.measurePresets.first(where: { $0.id == id }) else { return }
                store.update { $0.measure = preset.chars }
            }
        )
    }

    private var leadingBinding: Binding<String> {
        Binding(
            get: { store.settings.leadingPreset.id },
            set: { id in
                guard let preset = Settings.leadingPresets.first(where: { $0.id == id }) else { return }
                store.update { $0.leading = preset.height }
            }
        )
    }
}
