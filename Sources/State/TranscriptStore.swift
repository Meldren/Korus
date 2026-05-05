import Foundation

final class TranscriptStore: ObservableObject {
    /// Append-only committed transcripts. Paragraph breaks come from Soniox `<end>`
    /// markers (rewritten upstream as `\n`).
    @Published private(set) var committedOriginal: String = ""
    @Published private(set) var committedTranslated: String = ""

    /// Tentative tail; fully replaced each Soniox frame.
    @Published private(set) var partialOriginal: String = ""
    @Published private(set) var partialTranslated: String = ""

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastError: String?

    /// Billed seconds for the current session (`total_audio_proc_ms` − baseline).
    /// Trash-clearing rolls the baseline so the cost chip drops to zero without a reconnect.
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

    /// Promotes the current tentative tail to committed history and clears it. Returned
    /// tuple lets callers persist the same chunk to disk so on-screen and saved files agree.
    func promotePartialToCommitted() -> (original: String, translated: String) {
        let o = partialOriginal
        let t = partialTranslated
        guard !o.isEmpty || !t.isEmpty else { return ("", "") }
        committedOriginal += o
        committedTranslated += t
        partialOriginal = ""
        partialTranslated = ""
        return (o, t)
    }

    func clear() {
        committedOriginal = ""
        committedTranslated = ""
        partialOriginal = ""
        partialTranslated = ""
        lastError = nil
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
        // Stale tail from the previous connection — Soniox won't re-send it.
        partialOriginal = ""
        partialTranslated = ""
    }

    var displayOriginal: String { committedOriginal + partialOriginal }
    var displayTranslated: String { committedTranslated + partialTranslated }
}
