import Foundation

final class TranscriptStore: ObservableObject {
    /// One growing committed paragraph of original/translated text. Soniox commits tokens
    /// append-only; we keep them in a single string per stream and break paragraphs only
    /// when an explicit `<end>` marker arrives (encoded as `\n` upstream).
    @Published private(set) var committedOriginal: String = ""
    @Published private(set) var committedTranslated: String = ""

    /// Tail of non-final tokens — fully replaced on every Soniox frame.
    @Published private(set) var partialOriginal: String = ""
    @Published private(set) var partialTranslated: String = ""

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastError: String?

    /// Audio seconds Soniox has actually billed for in the current session, derived from
    /// `total_audio_proc_ms` it returns on every keepalive frame. We subtract a baseline
    /// so the user can hit Trash mid-session and have the cost chip drop back to zero.
    @Published private(set) var sessionProcessedSeconds: Double = 0
    private var lastSonioxMs: Int = 0
    private var baselineMs: Int = 0

    enum Status: Equatable {
        case idle
        case connecting
        case listening
        case error(String)
    }

    func setStatus(_ status: Status) {
        self.status = status
        if case let .error(message) = status {
            self.lastError = message
        }
    }

    func appendCommitted(original: String, translated: String, speaker: Int?) {
        committedOriginal += original
        committedTranslated += translated
    }

    func updatePartial(original: String, translated: String) {
        partialOriginal = original
        partialTranslated = translated
    }

    func clear() {
        committedOriginal = ""
        committedTranslated = ""
        partialOriginal = ""
        partialTranslated = ""
        lastError = nil
        // Treat the current Soniox total as the new zero so the cost chip drops to $0.000.
        baselineMs = lastSonioxMs
        sessionProcessedSeconds = 0
    }

    func setProcessedAudioSeconds(_ seconds: Double) {
        let ms = Int(seconds * 1000)
        lastSonioxMs = ms
        sessionProcessedSeconds = max(0, Double(ms - baselineMs) / 1000.0)
    }

    func resetSessionUsage() {
        baselineMs = 0
        lastSonioxMs = 0
        sessionProcessedSeconds = 0
        // The previous session's tentative tail will never be replaced by the new
        // connection, so wipe it. Committed text stays — that's the running history.
        partialOriginal = ""
        partialTranslated = ""
    }

    /// Combined view used by the captions UI.
    var displayOriginal: String { committedOriginal + partialOriginal }
    var displayTranslated: String { committedTranslated + partialTranslated }
}
