import SwiftUI

struct SubtitleView: View {
    @EnvironmentObject private var transcript: TranscriptStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var actions: AppActions
    @EnvironmentObject private var languageService: SonioxLanguageService


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar

            if isOnboarding {
                onboarding
                    .padding(.horizontal, 26)
                    .padding(.bottom, 24)
            } else {
                captions
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isOnboarding: Bool {
        settings.sonioxAPIKey.isEmpty
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            KLogoView(size: 22)
                .frame(width: 28, height: 28)

            statusChip

            if !isOnboarding {
                if transcript.sessionProcessedSeconds > 0 {
                    sessionCostChip
                }
                playStopButton

                Divider()
                    .frame(height: 16)
                    .overlay(.white.opacity(0.12))

                quickSourceLanguagePicker
                if settings.translationEnabled {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                    quickTargetLanguagePicker
                }
                quickAudioSourcePicker

                Spacer(minLength: 8)

                iconButton(systemName: "doc.on.doc", help: copyHelp, disabled: actions.isRunning) {
                    copyTranscript()
                }
                iconButton(systemName: "trash", help: trashHelp, disabled: actions.isRunning) {
                    actions.clearTranscript()
                }

                Divider()
                    .frame(height: 16)
                    .overlay(.white.opacity(0.12))
            } else {
                Spacer()
            }

            pinButton
            iconButton(systemName: "gearshape", help: settingsHelp, disabled: actions.isRunning) {
                actions.toggleSettings()
            }
            iconButton(systemName: "eye.slash", help: "Hide overlay") {
                actions.hideOverlay()
            }
            iconButton(systemName: "power", help: "Quit Korus") {
                actions.quit()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var copyHelp: String {
        actions.isRunning ? "Stop listening to copy" : "Copy transcript"
    }

    private var trashHelp: String {
        actions.isRunning ? "Stop listening to clear" : "Clear transcript"
    }

    private var settingsHelp: String {
        actions.isRunning ? "Stop listening to change settings" : "Settings"
    }

    /// Local estimate from `total_audio_proc_ms`; Soniox doesn't expose balance via API.
    private var sessionCostChip: some View {
        let hours = transcript.sessionProcessedSeconds / 3600.0
        let rate = settings.translationEnabled ? 0.18 : 0.12
        let cost = hours * rate
        let formatted = cost < 1 ? String(format: "$%.3f", cost) : String(format: "$%.2f", cost)
        return HStack(spacing: 4) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(formatted)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.05)))
        .fixedSize()
        .help("Estimated cost of this session. Click to open Soniox Console.")
        .onTapGesture {
            if let url = URL(string: "https://console.soniox.com") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: 3)
            Text(statusLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(.white.opacity(0.06))
        )
        .fixedSize()
    }

    private var playStopButton: some View {
        Button(action: { actions.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: actions.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(actions.isRunning ? "Stop" : "Listen")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(actions.isRunning ? Color.red.opacity(0.95) : Color.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(actions.isRunning ? Color.red.opacity(0.18) : Color.white.opacity(0.10))
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private var quickSourceLanguagePicker: some View {
        toolbarPicker(
            icon: "waveform",
            label: currentSourceLabel
        ) {
            Button(LanguageOption.autoDetect.displayName) {
                settings.sourceLanguage = LanguageOption.autoDetect.id
            }
            if languageService.isLoaded {
                Divider()
                ForEach(languageService.languages) { option in
                    Button(option.displayName) {
                        settings.sourceLanguage = option.id
                    }
                }
            }
        }
    }

    private var quickTargetLanguagePicker: some View {
        toolbarPicker(
            icon: "globe",
            label: currentTargetLabel
        ) {
            if languageService.isLoaded {
                ForEach(languageService.languages) { option in
                    Button(option.displayName) {
                        settings.targetLanguage = option.id
                    }
                }
            } else {
                Text("Loading languages…")
            }
        }
    }

    private var quickAudioSourcePicker: some View {
        toolbarPicker(
            icon: audioSourceIcon,
            label: audioSourceShortLabel
        ) {
            ForEach(AudioSource.allCases) { source in
                Button(source.displayName) {
                    settings.audioSource = source
                }
            }
        }
    }

    @ViewBuilder
    private func toolbarPicker<Content: View>(
        icon: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(.white.opacity(0.09))
            )
            .overlay(
                Capsule().stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var currentTargetLabel: String {
        if let match = languageService.languages.first(where: { $0.id == settings.targetLanguage }) {
            return match.displayName
        }
        return settings.targetLanguage.isEmpty ? "Language" : settings.targetLanguage.uppercased()
    }

    private var currentSourceLabel: String {
        if settings.sourceLanguage == LanguageOption.autoDetect.id {
            return "Auto"
        }
        if let match = languageService.languages.first(where: { $0.id == settings.sourceLanguage }) {
            return match.displayName
        }
        return settings.sourceLanguage.uppercased()
    }

    private var audioSourceIcon: String {
        switch settings.audioSource {
        case .microphone: return "mic"
        case .systemAudio: return "speaker.wave.2"
        case .both: return "rectangle.on.rectangle"
        }
    }

    private var audioSourceShortLabel: String {
        switch settings.audioSource {
        case .microphone: return "Mic"
        case .systemAudio: return "System"
        case .both: return "Both"
        }
    }

    private var statusColor: Color {
        switch transcript.status {
        case .listening: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .idle: return .gray
        }
    }

    private var statusLabel: String {
        switch transcript.status {
        case .listening: return "Listening"
        case .connecting: return "Connecting"
        case .idle: return "Idle"
        case .error: return "Error"
        }
    }

    private func iconButton(
        systemName: String,
        help: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(disabled ? 0.25 : 0.65))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help ?? "")
    }

    private func copyTranscript() {
        let text = composedTranscriptText()
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func composedTranscriptText() -> String {
        let original = (transcript.committedOriginal + transcript.partialOriginal)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = (transcript.committedTranslated + transcript.partialTranslated)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if settings.translationEnabled {
            return translated.isEmpty ? original : translated
        }
        return original
    }

    private var pinButton: some View {
        Button {
            settings.alwaysOnTop.toggle()
        } label: {
            Image(systemName: settings.alwaysOnTop ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .medium))
                .rotationEffect(.degrees(settings.alwaysOnTop ? 0 : 35))
                .foregroundStyle(settings.alwaysOnTop ? Color.white.opacity(0.95) : Color.white.opacity(0.55))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(settings.alwaysOnTop ? Color.white.opacity(0.14) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(settings.alwaysOnTop ? "Pinned (always on top)" : "Pin overlay on top")
    }

    @ViewBuilder
    private var captions: some View {
        if settings.translationEnabled && settings.showOriginal {
            splitCaptions
        } else {
            singleColumnCaptions
        }
    }

    /// EnvironmentObjects are re-injected on each side: NSHostingView starts a fresh
    /// SwiftUI environment, so the parent's `@EnvironmentObject` chain doesn't propagate.
    @ViewBuilder
    private var splitCaptions: some View {
        SplitColumnsView(minSide: 140) {
            column(
                primary: false,
                committed: transcript.committedOriginal,
                partial: transcript.partialOriginal
            )
            .environmentObject(transcript)
            .environmentObject(settings)
            .environmentObject(actions)
            .environmentObject(languageService)
        } right: {
            column(
                primary: true,
                committed: transcript.committedTranslated,
                partial: transcript.partialTranslated
            )
            .environmentObject(transcript)
            .environmentObject(settings)
            .environmentObject(actions)
            .environmentObject(languageService)
        }
        .overlay(alignment: .topLeading) {
            if isTranscriptEmpty {
                emptyHint
                    .padding(.leading, 22)
            }
        }
    }

    @ViewBuilder
    private func column(primary: Bool, committed: String, partial: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !committed.isEmpty || !partial.isEmpty {
                        let committedColor: Color = primary ? .white : .white.opacity(0.55)
                        let partialColor: Color = primary ? .white.opacity(0.7) : .white.opacity(0.4)
                        let size = primary ? settings.fontSize : settings.fontSize - 2
                        let weight: Font.Weight = primary ? .medium : .regular

                        (Text(committed).foregroundStyle(committedColor)
                         + Text(partial).foregroundStyle(partialColor))
                            .font(.system(size: size, weight: weight))
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("tail")
                }
                .padding(.horizontal, primary ? 16 : 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: committed) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("tail", anchor: .bottom)
                }
            }
            .onChange(of: partial) { _, _ in
                withAnimation(.linear(duration: 0.10)) {
                    proxy.scrollTo("tail", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var singleColumnCaptions: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if settings.translationEnabled {
                        translatedLine
                    } else {
                        originalLine(secondary: false)
                    }

                    if isTranscriptEmpty {
                        emptyHint
                    }

                    Color.clear.frame(height: 1).id("tail")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: transcript.committedTranslated) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("tail", anchor: .bottom) }
            }
            .onChange(of: transcript.partialTranslated) { _, _ in
                withAnimation(.linear(duration: 0.10)) { proxy.scrollTo("tail", anchor: .bottom) }
            }
            .onChange(of: transcript.committedOriginal) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("tail", anchor: .bottom) }
            }
            .onChange(of: transcript.partialOriginal) { _, _ in
                withAnimation(.linear(duration: 0.10)) { proxy.scrollTo("tail", anchor: .bottom) }
            }
        }
    }

    private var isTranscriptEmpty: Bool {
        transcript.committedOriginal.isEmpty
            && transcript.committedTranslated.isEmpty
            && transcript.partialOriginal.isEmpty
            && transcript.partialTranslated.isEmpty
    }

    @ViewBuilder
    private func originalLine(secondary: Bool) -> some View {
        let committed = transcript.committedOriginal
        let partial = transcript.partialOriginal
        if !committed.isEmpty || !partial.isEmpty {
            let committedColor: Color = secondary ? .white.opacity(0.5) : .white
            let partialColor: Color = secondary ? .white.opacity(0.35) : .white.opacity(0.7)
            let size = secondary ? settings.fontSize - 4 : settings.fontSize
            let weight: Font.Weight = secondary ? .regular : .medium

            (Text(committed).foregroundStyle(committedColor)
             + Text(partial).foregroundStyle(partialColor))
                .font(.system(size: size, weight: weight))
                .lineSpacing(secondary ? 2 : 3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var translatedLine: some View {
        let committed = transcript.committedTranslated
        let partial = transcript.partialTranslated
        if !committed.isEmpty || !partial.isEmpty {
            (Text(committed).foregroundStyle(.white)
             + Text(partial).foregroundStyle(.white.opacity(0.7)))
                .font(.system(size: settings.fontSize, weight: .medium))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var emptyHint: some View {
        switch transcript.status {
        case .idle:
            Text(actions.isRunning ? "Listening for audio…" : "Click Listen to start.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
        case .connecting:
            Text("Connecting to Soniox…")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
        case .error(let msg):
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(.red.opacity(0.8))
        case .listening:
            Text("Listening for audio…")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to Korus")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("Live captions and translation for any audio on your Mac.\nAdd your Soniox API key to start.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))

            Button(action: { actions.showSettings() }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                    Text("Open settings")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(.white.opacity(0.95))
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
