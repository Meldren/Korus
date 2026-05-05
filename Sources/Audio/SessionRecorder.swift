import Foundation

/// Writes each Listen session to its own folder under
/// `~/Library/Application Support/Korus/sessions/<timestamp>/`: original.txt,
/// translation.txt, audio.wav. Text is flushed on every write so a crash leaves a
/// readable file; the WAV header is patched in `end()`.
final class SessionRecorder {
    private let queue = DispatchQueue(label: "com.meldren.korus.session-recorder")

    private var sessionFolder: URL?
    private var originalHandle: FileHandle?
    private var translationHandle: FileHandle?
    private var audioHandle: FileHandle?
    /// 64-bit so we never wrap mid-session; clamped to UInt32 when patching the WAV
    /// header (the format itself caps at ~4 GB ≈ 37h of 16 kHz mono Int16).
    private var audioBytesWritten: UInt64 = 0

    private var openConfig: (translationEnabled: Bool, customRootPath: String)?

    /// True while a session folder is open. Audio + text writes append to it across
    /// Listen→Stop→Listen cycles; the trash button (or app quit) closes it.
    var hasOpenSession: Bool { originalHandle != nil }

    func canResume(translationEnabled: Bool, customRootPath: String) -> Bool {
        guard let cfg = openConfig else { return false }
        return cfg.translationEnabled == translationEnabled
            && cfg.customRootPath == customRootPath
    }

    private static let audioSampleRate: UInt32 = 16_000
    private static let audioChannels: UInt16 = 1
    private static let audioBitsPerSample: UInt16 = 16

    @discardableResult
    func begin(translationEnabled: Bool, customRootPath: String) throws -> URL {
        let timestamp = SessionRecorder.timestampFormatter.string(from: Date())
        let folder = try SessionRecorder.sessionsRoot(customPath: customRootPath)
            .appendingPathComponent(timestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Close every handle if any later step throws — otherwise a failed
        // translation.txt / audio.wav open leaks the already-opened original.txt.
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

            // Placeholder header; real sizes are patched in `end()`. On crash the .wav
            // still has valid PCM but reports zero length (any editor can repair).
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
            openConfig = (translationEnabled, customRootPath)
            return folder
        } catch {
            for handle in openedHandles { try? handle.close() }
            throw error
        }
    }

    func appendCommit(original: String, translated: String) {
        if !original.isEmpty {
            try? writeUTF8(original, to: originalHandle)
        }
        if !translated.isEmpty, let translationHandle {
            try? writeUTF8(translated, to: translationHandle)
        }
    }

    /// Background-safe; expects 16 kHz mono Int16 LE PCM.
    func appendAudio(_ pcm: Data) {
        queue.async { [weak self] in
            guard let self, let h = self.audioHandle else { return }
            do {
                try h.write(contentsOf: pcm)
                self.audioBytesWritten &+= UInt64(pcm.count)
            } catch {}
        }
    }

    func end() {
        try? originalHandle?.close()
        try? translationHandle?.close()
        originalHandle = nil
        translationHandle = nil

        // queue.sync drains pending appendAudio writes before we patch the header.
        queue.sync { [self] in
            guard let h = audioHandle else { return }
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
        openConfig = nil
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
