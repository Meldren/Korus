import AppKit
import SwiftUI

struct InlineSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var actions: AppActions
    @EnvironmentObject private var languageService: SonioxLanguageService

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(.white.opacity(0.06))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    sonioxSection
                    translationSection
                    overlaySection
                    sessionsSection
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            KLogoView(size: 22)
                .frame(width: 28, height: 28)

            Text("Settings")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button {
                actions.hideSettings()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    // MARK: - Sections

    private var sonioxSection: some View {
        section(title: "Soniox API key") {
            VStack(alignment: .leading, spacing: 10) {
                SecureFieldRow(text: $settings.sonioxAPIKey, placeholder: "Paste your Soniox API key")
                Link(destination: URL(string: "https://console.soniox.com")!) {
                    HStack(spacing: 5) {
                        Text("Get a key at console.soniox.com")
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var translationSection: some View {
        section(title: "Translation") {
            VStack(alignment: .leading, spacing: 12) {
                ToggleRow(label: "Translate captions to a target language", isOn: $settings.translationEnabled)

                Text("Off — Korus only transcribes (cheaper). On — every line is also translated to the target language picked in the overlay toolbar (extra cost ≈ +$0.06/hour).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sessionsSection: some View {
        section(title: "Session backup") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Every Listen session is auto-saved as a folder containing original.txt, translation.txt and audio.wav. If Korus crashes mid-stream, nothing is lost.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Save folder")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.55))

                    HStack(spacing: 8) {
                        Text(currentSessionsPathLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.white.opacity(0.07))
                            )

                        darkPillButton(title: "Choose…") { chooseSessionsFolder() }

                        if !settings.sessionsCustomPath.isEmpty {
                            darkPillButton(systemImage: "arrow.uturn.backward", help: "Reset to default location") {
                                settings.sessionsCustomPath = ""
                            }
                        }
                    }
                }

                Button {
                    if let url = try? SessionRecorder.sessionsRoot(customPath: settings.sessionsCustomPath) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Reveal sessions folder")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule().stroke(.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currentSessionsPathLabel: String {
        if !settings.sessionsCustomPath.isEmpty {
            return settings.sessionsCustomPath
        }
        return "~/Library/Application Support/Korus/sessions"
    }

    private func chooseSessionsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.title = "Choose Korus sessions folder"
        // Open the picker already pointing at the current sessions folder (or its parent
        // if it doesn't exist yet) so the user lands in a familiar place.
        if let current = try? SessionRecorder.sessionsRoot(customPath: settings.sessionsCustomPath) {
            panel.directoryURL = current
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.sessionsCustomPath = url.path
        }
    }

    @ViewBuilder
    private func darkPillButton(
        title: String? = nil,
        systemImage: String? = nil,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(.white.opacity(0.10))
            )
            .overlay(
                Capsule().stroke(.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }

    private var overlaySection: some View {
        section(title: "Overlay") {
            VStack(alignment: .leading, spacing: 18) {
                if settings.translationEnabled {
                    ToggleRow(label: "Show original next to translation", isOn: $settings.showOriginal)
                }
                ToggleRow(label: "Open overlay on launch", isOn: $settings.showOverlayOnLaunch)

                SliderRow(
                    label: "Font size",
                    value: $settings.fontSize,
                    range: 14...44,
                    valueLabel: "\(Int(settings.fontSize))"
                )

                SliderRow(
                    label: "Background opacity",
                    value: $settings.overlayOpacity,
                    range: 0.3...1.0,
                    valueLabel: String(format: "%.0f%%", settings.overlayOpacity * 100)
                )
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.42))
            content()
        }
    }
}

// MARK: - Atoms

private struct SecureFieldRow: View {
    @Binding var text: String
    let placeholder: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white)

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

struct DarkPicker: View {
    @Binding var selection: String
    let options: [LanguageOption]
    let placeholder: String

    init(selection: Binding<String>, options: [LanguageOption], placeholder: String = "Select…") {
        self._selection = selection
        self.options = options
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )

            Menu {
                if options.isEmpty {
                    Text(placeholder)
                } else {
                    ForEach(options) { option in
                        Button(option.displayName) { selection = option.id }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(currentLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
    }

    private var currentLabel: String {
        if let match = options.first(where: { $0.id == selection }) {
            return match.displayName
        }
        return options.isEmpty ? placeholder : selection
    }
}

private struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(valueLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
                .tint(.white.opacity(0.75))
        }
    }
}
