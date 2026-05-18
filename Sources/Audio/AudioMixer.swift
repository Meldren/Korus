import Foundation

/// Combines microphone and system-audio PCM streams into a single 16 kHz mono Int16
/// stream for Soniox. Each capture pushes its frames via `appendMic` / `appendSystem`
/// at its own cadence; a 50 ms timer pulls equal slices from both ring buffers,
/// sums them sample-wise (with /2 normalisation to dodge Int16 overflow), and emits
/// one merged chunk to `onPCM`. If a source stalls (Bluetooth hiccup, silence) the
/// missing side is filled with zeros so the stream stays continuous.
final class AudioMixer {
    private let onPCM: (Data) -> Void
    private let bytesPerTick: Int
    private let tickInterval: TimeInterval

    private var micBuffer = Data()
    private var sysBuffer = Data()
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.meldren.korus.mixer", qos: .userInitiated)

    init(sampleRate: Int, onPCM: @escaping (Data) -> Void) {
        self.onPCM = onPCM
        // 50 ms tick. Smaller = lower latency, more wakeups; larger = more memory pressure.
        let samplesPerTick = sampleRate / 20
        self.bytesPerTick = samplesPerTick * MemoryLayout<Int16>.size
        self.tickInterval = 0.05
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        self.timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        lock.lock()
        micBuffer.removeAll(keepingCapacity: false)
        sysBuffer.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    func appendMic(_ data: Data) {
        lock.lock()
        micBuffer.append(data)
        trim(&micBuffer)
        lock.unlock()
    }

    func appendSystem(_ data: Data) {
        lock.lock()
        sysBuffer.append(data)
        trim(&sysBuffer)
        lock.unlock()
    }

    private func trim(_ buffer: inout Data) {
        // Watchdog: if the timer stalls or one source overruns the other, cap memory
        // at ~2 s of audio (40 ticks) and drop the oldest half. Better to lose history
        // than to balloon RAM unboundedly.
        let limit = bytesPerTick * 40
        if buffer.count > limit {
            buffer.removeSubrange(0..<(buffer.count - bytesPerTick * 20))
        }
    }

    private func tick() {
        let need = bytesPerTick
        lock.lock()
        let micReady = micBuffer.count >= need
        let sysReady = sysBuffer.count >= need
        guard micReady || sysReady else {
            lock.unlock()
            return
        }
        let mic: Data = micReady ? micBuffer.prefix(need) : Data(count: need)
        let sys: Data = sysReady ? sysBuffer.prefix(need) : Data(count: need)
        if micReady { micBuffer.removeSubrange(0..<need) }
        if sysReady { sysBuffer.removeSubrange(0..<need) }
        lock.unlock()

        onPCM(Self.mix(mic, sys))
    }

    private static func mix(_ a: Data, _ b: Data) -> Data {
        precondition(a.count == b.count)
        let sampleCount = a.count / MemoryLayout<Int16>.size
        var output = Data(count: a.count)
        a.withUnsafeBytes { aRaw in
            b.withUnsafeBytes { bRaw in
                output.withUnsafeMutableBytes { outRaw in
                    let aBuf = aRaw.bindMemory(to: Int16.self)
                    let bBuf = bRaw.bindMemory(to: Int16.self)
                    let outBuf = outRaw.bindMemory(to: Int16.self)
                    for i in 0..<sampleCount {
                        let sum = Int32(aBuf[i]) + Int32(bBuf[i])
                        outBuf[i] = Int16(clamping: sum / 2)
                    }
                }
            }
        }
        return output
    }
}
