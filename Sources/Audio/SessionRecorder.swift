import Foundation

/// Streams every Soniox commit AND the raw audio we send to Soniox to disk inside
/// `~/Library/Application Support/Korus/sessions/<timestamp>/`. Each Listen session
/// gets its own folder; nothing is lost if the app crashes mid-stream because every
/// text write is flushed and the WAV header is patched on graceful end.
final class SessionRecorder {
    private let queue = DispatchQueue(label: "com.meldren.korus.session-recorder")

    private var sessionFolder: URL?
    private var originalHandle: FileHandle?
    private var translationHandle: FileHandle?
    private var audioHandle: FileHandle?
    /// 64-bit so we never wrap during multi-day sessions. The WAV format itself caps
    /// data length at UInt32 (~4 GB ≈ 37h at 16 kHz mono Int16); past that the header
    /// can't accurately describe the file. We saturate the patched-in size at UInt32.max
    /// — any decent audio editor will then truncate or refuse, but the raw PCM is intact.
    private var audioBytesWritten: UInt64 = 0

    // Audio shape we hand to Soniox — same shape we record locally.
    private static let audioSampleRate: UInt32 = 16_000
    private static let audioChannels: UInt16 = 1
    private static let audioBitsPerSample: UInt16 = 16

    /// Starts a new session. Returns the folder URL so callers can surface it.
    @discardableResult
    func begin(translationEnabled: Bool, customRootPath: String) throws -> URL {
        let timestamp = SessionRecorder.timestampFormatter.string(from: Date())
        let folder = try SessionRecorder.sessionsRoot(customPath: customRootPath)
            .appendingPathComponent(timestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Track handles locally so we can close all of them if any later step throws.
        // Without this, a failed translation.txt or audio.wav open would leak the
        // already-opened original.txt handle until the next session.
        var openedHandles: [FileHandle] = []
        do {
            let original = try makeHandle(folder: folder, name: "original.txt")
            openedHandles.append(original)

            var translation: FileHandle?
            if translationEnabled {
                let h = try makeHandle(folder: folder, name: "translation.txt")
                openedHandles.append(h)
                translation = h
            }

            // Open audio.wav with a placeholder header; sizes are patched in `end()` once
            // we know the total bytes written. If the app crashes before end(), the .wav
            // still contains valid PCM data — header just reports 0 length.
            let audioURL = folder.appendingPathComponent("audio.wav")
            FileManager.default.createFile(atPath: audioURL.path, contents: nil)
            let audio = try FileHandle(forWritingTo: audioURL)
            openedHandles.append(audio)
            try audio.write(contentsOf: SessionRecorder.wavHeader(dataLength: 0))
            try audio.synchronize()

            sessionFolder = folder
            originalHandle = original
            translationHandle = translation
            audioHandle = audio
            audioBytesWritten = 0
            return folder
        } catch {
            for handle in openedHandles { try? handle.close() }
            throw error
        }
    }

    /// Appends a single Soniox commit to disk. Both fields are written verbatim — the
    /// store also handles `<end>` markers as newlines, so paragraph breaks land naturally.
    func appendCommit(original: String, translated: String) {
        if !original.isEmpty {
            try? writeUTF8(original, to: originalHandle)
        }
        if !translated.isEmpty, let translationHandle {
            try? writeUTF8(translated, to: translationHandle)
        }
    }

    /// Appends raw PCM frames (16 kHz / mono / Int16 LE) — exactly what we hand to
    /// Soniox — to the session's `audio.wav`. Safe to call from background queues.
    func appendAudio(_ pcm: Data) {
        queue.async { [weak self] in
            guard let self, let h = self.audioHandle else { return }
            do {
                try h.write(contentsOf: pcm)
                self.audioBytesWritten &+= UInt64(pcm.count)
            } catch {
                // Silently drop — losing one buffer of audio is better than crashing.
            }
        }
    }

    func end() {
        try? originalHandle?.close()
        try? translationHandle?.close()
        originalHandle = nil
        translationHandle = nil

        // Patch the WAV header sizes now that we know how many PCM bytes were written.
        // Drain pending writes by hopping through the queue first.
        queue.sync { [self] in
            guard let h = audioHandle else { return }
            // WAV format limits each size field to 32 bits; saturate past that.
            let dataLen32 = UInt32(min(audioBytesWritten, UInt64(UInt32.max)))
            let fileLen32 = UInt32(min(UInt64(36) &+ audioBytesWritten, UInt64(UInt32.max)))
            do {
                try h.seek(toOffset: 4)
                try h.write(contentsOf: SessionRecorder.uint32LE(fileLen32))
                try h.seek(toOffset: 40)
                try h.write(contentsOf: SessionRecorder.uint32LE(dataLen32))
                try h.synchronize()
                try h.close()
            } catch {
                try? h.close()
            }
            audioHandle = nil
            audioBytesWritten = 0
        }
        sessionFolder = nil
    }

    static func sessionsRoot(customPath: String) throws -> URL {
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = (trimmed as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Korus/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeHandle(folder: URL, name: String) throws -> FileHandle {
        let url = folder.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try FileHandle(forWritingTo: url)
    }

    private func writeUTF8(_ text: String, to handle: FileHandle?) throws {
        guard let handle, let data = text.data(using: .utf8) else { return }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - WAV helpers

    private static func wavHeader(dataLength: UInt32) -> Data {
        let byteRate = audioSampleRate * UInt32(audioChannels) * UInt32(audioBitsPerSample) / 8
        let blockAlign = audioChannels * audioBitsPerSample / 8
        let fileSize = 36 &+ dataLength

        var d = Data()
        d.append(contentsOf: Array("RIFF".utf8))
        d.append(uint32LE(fileSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        d.append(uint32LE(16))
        d.append(uint16LE(1))                   // PCM
        d.append(uint16LE(audioChannels))
        d.append(uint32LE(audioSampleRate))
        d.append(uint32LE(byteRate))
        d.append(uint16LE(blockAlign))
        d.append(uint16LE(audioBitsPerSample))
        d.append(contentsOf: Array("data".utf8))
        d.append(uint32LE(dataLength))
        return d
    }

    private static func uint32LE(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }

    private static func uint16LE(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }
}
