import SwiftUI

struct SettingsView: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 15
    @AppStorage("theme") private var theme: String = "auto"
    @AppStorage("defaultViewMode") private var defaultMode: String = ViewMode.dual.rawValue

    private let defaultFontSize: Double = 15

    var body: some View {
        Form {
            // ── App header ──────────────────────────────────────────────────
            Section {
                HStack(spacing: 14) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("True Markdown")
                            .font(.headline)
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                            Text("Version \(version) (\(build))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // ── Editor ─────────────────────────────────────────────────────
            Section("Editor") {
                HStack(spacing: 12) {
                    Text("Font Size")
                    Slider(value: $fontSize, in: 12...24, step: 1)
                    Text("\(Int(fontSize))pt")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                        .foregroundStyle(fontSize == defaultFontSize ? .secondary : .primary)

                    Button("Reset") {
                        fontSize = defaultFontSize
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(fontSize == defaultFontSize)
                }
            }

            // ── Appearance ─────────────────────────────────────────────────
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Auto (follows macOS)").tag("auto")
                }
                .pickerStyle(.radioGroup)
            }

            // ── Default View ───────────────────────────────────────────────
            Section("Default View") {
                Picker("Default Mode", selection: $defaultMode) {
                    ForEach(ViewMode.allCases, id: \.rawValue) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 400)
        .navigationTitle("Settings")
    }
}
