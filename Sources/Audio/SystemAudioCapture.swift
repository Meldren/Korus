import AVFoundation
import CoreAudio
import Foundation

/// Captures system-wide output audio on macOS 14.4+ using the new CoreAudio Tap API.
/// Pattern follows the working AudioTee reference implementation: a process tap with an
/// empty `processes` list and `isExclusive = true` (i.e. exclude no one = capture all),
/// fed into an aggregate device that has no real subdevice — just the tap.
@available(macOS 14.4, *)
final class SystemAudioCapture {
    private let onPCM: (Data) -> Void
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateID: AudioDeviceID = kAudioObjectUnknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private var sourceFormat: AVAudioFormat?

    init(onPCM: @escaping (Data) -> Void) {
        self.onPCM = onPCM
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(SonioxConstants.sampleRate),
            channels: AVAudioChannelCount(SonioxConstants.channels),
            interleaved: true
        )!
    }

    func start() throws {
        let (tap, tapUUID) = try createSystemTap()

        // Make sure any failure after this point still releases the tap object.
        var tapToCleanup: AudioObjectID? = tap
        defer {
            if let id = tapToCleanup {
                AudioHardwareDestroyProcessTap(id)
            }
        }

        guard let tapFormat = tapStreamFormat(tapID: tap) else {
            throw NSError(
                domain: "Korus.SystemAudio",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot read tap stream format."]
            )
        }

        let aggregate = try createAggregateDevice(tapUUID: tapUUID)

        var aggregateToCleanup: AudioDeviceID? = aggregate
        defer {
            if let id = aggregateToCleanup {
                AudioHardwareDestroyAggregateDevice(id)
            }
        }

        self.sourceFormat = tapFormat
        self.converter = AVAudioConverter(from: tapFormat, to: outputFormat)

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregate,
            nil
        ) { [weak self] _, inputData, _, _, _ in
            self?.handle(inputData: inputData)
        }
        guard status == noErr, let procID else {
            throw NSError(
                domain: "Korus.SystemAudio",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to install IO proc on aggregate device (status \(status))."]
            )
        }

        let startStatus = AudioDeviceStart(aggregate, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregate, procID)
            throw NSError(
                domain: "Korus.SystemAudio",
                code: Int(startStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to start aggregate device (status \(startStatus))."]
            )
        }

        // Success — keep the tap and aggregate alive past the defers.
        self.tapID = tap
        self.aggregateID = aggregate
        self.deviceProcID = procID
        tapToCleanup = nil
        aggregateToCleanup = nil
    }

    func stop() {
        if let deviceProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, deviceProcID)
            AudioDeviceDestroyIOProcID(aggregateID, deviceProcID)
            self.deviceProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    // MARK: - Tap creation

    private func createSystemTap() throws -> (AudioObjectID, UUID) {
        // Empty-init form + processes=[] + isExclusive=true means "exclude no one" — the
        // tap captures the entire system mix. Pre-set the UUID so we can pass it to the
        // aggregate device dictionary directly (matches the AudioCap reference).
        let description = CATapDescription()
        let uuid = UUID()
        description.uuid = uuid
        description.name = "Korus System Audio Tap"
        description.processes = []
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.isMixdown = true
        description.isMono = false
        description.isExclusive = true
        description.deviceUID = nil
        description.stream = 0

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw NSError(
                domain: "Korus.SystemAudio",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "AudioHardwareCreateProcessTap failed (\(status))."]
            )
        }
        return (tapID, uuid)
    }

    private func tapStreamFormat(tapID: AudioObjectID) -> AVAudioFormat? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        var asbd = AudioStreamBasicDescription()
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else { return nil }
        return AVAudioFormat(streamDescription: &asbd)
    }

    private func createAggregateDevice(tapUUID: UUID) throws -> AudioObjectID {
        // Aggregate device pattern from insidegui/AudioCap. The bundled-app variant
        // requires the system output device as MainSubDevice and SubDeviceList anchor,
        // plus `TapAutoStart=true` so the tap activates with the device. Without these
        // AudioDeviceStart returns kAudioHardwareIllegalOperationError ('nope') on
        // hardened-runtime apps.
        let outputUID = try defaultOutputDeviceUID()
        let aggregateUID = UUID().uuidString

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Korus Capture",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID.uuidString
                ]
            ]
        ]

        var deviceID = AudioObjectID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard status == noErr else {
            throw NSError(
                domain: "Korus.SystemAudio",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "AudioHardwareCreateAggregateDevice failed (\(status))."]
            )
        }
        return deviceID
    }

    private func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout.size(ofValue: deviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else {
            throw NSError(
                domain: "Korus.SystemAudio",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Cannot read default output device."]
            )
        }

        var uidRef: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = withUnsafeMutablePointer(to: &uidRef) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &uidSize, ptr)
        }
        guard status == noErr else {
            throw NSError(
                domain: "Korus.SystemAudio",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Cannot read default output device UID."]
            )
        }
        return uidRef as String
    }

    // MARK: - IO proc

    private func handle(inputData: UnsafePointer<AudioBufferList>) {
        guard let converter, let sourceFormat else { return }
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let firstBuffer = abl.first, firstBuffer.mDataByteSize > 0 else { return }

        let frameCount = AVAudioFrameCount(firstBuffer.mDataByteSize) / sourceFormat.streamDescription.pointee.mBytesPerFrame
        guard frameCount > 0 else { return }

        guard let sourcePCM = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            return
        }
        sourcePCM.frameLength = frameCount

        let bufferList = UnsafeMutableAudioBufferListPointer(sourcePCM.mutableAudioBufferList)
        for index in 0..<min(bufferList.count, abl.count) {
            let dst = bufferList[index]
            let src = abl[index]
            let bytes = min(dst.mDataByteSize, src.mDataByteSize)
            if let dstData = dst.mData, let srcData = src.mData {
                memcpy(dstData, srcData, Int(bytes))
            }
        }

        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frameCount) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else { return }

        var inputProvided = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if inputProvided {
                status.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            status.pointee = .haveData
            return sourcePCM
        }

        var error: NSError?
        let conversionStatus = converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        guard conversionStatus != .error, error == nil else { return }

        guard let int16 = outBuffer.int16ChannelData else { return }
        let outFrames = Int(outBuffer.frameLength)
        guard outFrames > 0 else { return }

        let bytes = outFrames * MemoryLayout<Int16>.size * Int(outputFormat.channelCount)
        let data = Data(bytes: int16[0], count: bytes)
        onPCM(data)
    }
}
