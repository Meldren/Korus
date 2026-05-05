import AVFoundation
import Foundation

final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let onPCM: (Data) -> Void

    init(onPCM: @escaping (Data) -> Void) {
        self.onPCM = onPCM
        // 16-bit signed little-endian, 16 kHz, mono, interleaved.
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(SonioxConstants.sampleRate),
            channels: AVAudioChannelCount(SonioxConstants.channels),
            interleaved: true
        )!
    }

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw NSError(
                domain: "Korus.Microphone",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone is unavailable. Check Privacy & Security → Microphone."]
            )
        }

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        let bufferSize: AVAudioFrameCount = 4096
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.convertAndEmit(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func convertAndEmit(buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let inputSampleRate = buffer.format.sampleRate
        let outputSampleRate = outputFormat.sampleRate
        let ratio = outputSampleRate / inputSampleRate
        let outFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)

        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outFrameCapacity) else {
            return
        }

        var inputProvided = false
        let inputBlock: AVAudioConverterInputBlock = { _, inputStatus in
            if inputProvided {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            inputStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, error == nil else { return }

        guard let int16Channel = outBuffer.int16ChannelData else { return }
        let frameCount = Int(outBuffer.frameLength)
        guard frameCount > 0 else { return }

        let byteCount = frameCount * MemoryLayout<Int16>.size * Int(outputFormat.channelCount)
        let data = Data(bytes: int16Channel[0], count: byteCount)
        onPCM(data)
    }
}
