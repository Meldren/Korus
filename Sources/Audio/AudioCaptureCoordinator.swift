import Combine
import Foundation

@MainActor
final class AudioCaptureCoordinator {
    private let settings: AppSettings
    private let transcript: TranscriptStore
    private let isRunningSubject = CurrentValueSubject<Bool, Never>(false)
    private(set) var isRunning = false

    private var sonioxClient: SonioxClient?
    private var microphone: MicrophoneCapture?
    private var systemAudio: AnyObject?  // SystemAudioCapture (gated by 14.4)
    private let recorder = SessionRecorder()

    init(settings: AppSettings, transcript: TranscriptStore) {
        self.settings = settings
        self.transcript = transcript
    }

    var isRunningPublisher: AnyPublisher<Bool, Never> {
        isRunningSubject.eraseToAnyPublisher()
    }

    func start() {
        guard !isRunning else { return }
        guard !settings.sonioxAPIKey.isEmpty else {
            transcript.setStatus(.error("Add your Soniox API key in Settings."))
            return
        }

        transcript.setStatus(.connecting)
        transcript.resetSessionUsage()

        let translation: TranslationConfig? = settings.translationEnabled
            ? TranslationConfig.oneWay(target: settings.targetLanguage)
            : nil
        let languageHints: [String]?
        if settings.sourceLanguage == "auto" {
            languageHints = nil
        } else {
            languageHints = [settings.sourceLanguage]
        }

        let config = SonioxConfig(
            apiKey: settings.sonioxAPIKey,
            model: SonioxConstants.model,
            audioFormat: "pcm_s16le",
            sampleRate: SonioxConstants.sampleRate,
            numChannels: SonioxConstants.channels,
            languageHints: languageHints,
            translation: translation,
            enableSpeakerDiarization: true,
            enableLanguageIdentification: true
        )

        do {
            try recorder.begin(
                translationEnabled: settings.translationEnabled,
                customRootPath: settings.sessionsCustomPath
            )
        } catch {
            NSLog("[Korus] SessionRecorder.begin failed: \(error)")
        }

        let client = SonioxClient(config: config)
        client.delegate = self
        self.sonioxClient = client
        client.connect()

        do {
            try startCapture()
        } catch {
            transcript.setStatus(.error(error.localizedDescription))
            stop()
            return
        }

        isRunning = true
        isRunningSubject.send(true)
    }

    func stop() {
        if microphone != nil {
            microphone?.stop()
            microphone = nil
        }
        if #available(macOS 14.4, *) {
            (systemAudio as? SystemAudioCapture)?.stop()
        }
        systemAudio = nil

        sonioxClient?.disconnect()
        sonioxClient = nil

        recorder.end()

        isRunning = false
        isRunningSubject.send(false)
        if case .listening = transcript.status {
            transcript.setStatus(.idle)
        }
    }

    private func startCapture() throws {
        let onPCM: (Data) -> Void = { [weak self] data in
            self?.sonioxClient?.sendPCM(data)
            self?.recorder.appendAudio(data)
        }

        switch settings.audioSource {
        case .microphone:
            try startMicrophone(onPCM: onPCM)
        case .systemAudio:
            try startSystemAudio(onPCM: onPCM)
        case .both:
            try startMicrophone(onPCM: onPCM)
            try startSystemAudio(onPCM: onPCM)
        }
    }

    private func startMicrophone(onPCM: @escaping (Data) -> Void) throws {
        let mic = MicrophoneCapture(onPCM: onPCM)
        try mic.start()
        self.microphone = mic
    }

    private func startSystemAudio(onPCM: @escaping (Data) -> Void) throws {
        if #available(macOS 14.4, *) {
            let capture = SystemAudioCapture(onPCM: onPCM)
            try capture.start()
            self.systemAudio = capture
        } else {
            throw NSError(
                domain: "Korus",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "System audio capture requires macOS 14.4 or later."]
            )
        }
    }
}

extension AudioCaptureCoordinator: SonioxClientDelegate {
    nonisolated func sonioxClientDidConnect(_ client: SonioxClient) {
        Task { @MainActor in
            self.transcript.setStatus(.listening)
        }
    }

    nonisolated func sonioxClient(_ client: SonioxClient, didCommitOriginal original: String, translated: String, speaker: Int?) {
        Task { @MainActor in
            self.transcript.appendCommitted(original: original, translated: translated, speaker: speaker)
            self.recorder.appendCommit(original: original, translated: translated)
        }
    }

    nonisolated func sonioxClient(_ client: SonioxClient, didReceivePartialOriginal original: String, translated: String) {
        Task { @MainActor in
            self.transcript.updatePartial(original: original, translated: translated)
        }
    }

    nonisolated func sonioxClient(_ client: SonioxClient, didReportProcessedAudioMs ms: Int) {
        Task { @MainActor in
            self.transcript.setProcessedAudioSeconds(Double(ms) / 1000.0)
        }
    }

    nonisolated func sonioxClient(_ client: SonioxClient, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            if let error {
                self.transcript.setStatus(.error(error.localizedDescription))
            }
            if self.isRunning {
                self.stop()
            }
        }
    }
}
