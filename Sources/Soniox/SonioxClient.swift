import Foundation

protocol SonioxClientDelegate: AnyObject {
    func sonioxClientDidConnect(_ client: SonioxClient)
    func sonioxClient(_ client: SonioxClient, didCommitOriginal original: String, translated: String, speaker: Int?)
    func sonioxClient(_ client: SonioxClient, didReceivePartialOriginal original: String, translated: String)
    func sonioxClient(_ client: SonioxClient, didReportProcessedAudioMs ms: Int)
    func sonioxClient(_ client: SonioxClient, didDisconnectWithError error: Error?)
}

/// Soniox real-time WebSocket: send one JSON config, then stream PCM frames; receive JSON
/// frames with `tokens`. Per Soniox semantics, `is_final: true` tokens are append-only
/// commitments while `is_final: false` is the full tentative tail re-sent each frame.
final class SonioxClient: NSObject {
    weak var delegate: SonioxClientDelegate?

    private let config: SonioxConfig
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    private var lastSpeaker: Int?

    init(config: SonioxConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 0
        self.session = URLSession(configuration: configuration)
        super.init()
    }

    func connect() {
        let task = session.webSocketTask(with: SonioxConstants.websocketURL)
        self.task = task
        task.resume()
        sendConfig()
        receiveLoop()
    }

    func disconnect() {
        sendEmptyTerminator()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func sendPCM(_ data: Data) {
        guard let task else { return }
        task.send(.data(data)) { [weak self] error in
            if let error {
                self?.notifyDisconnect(error)
            }
        }
    }

    private func sendConfig() {
        guard let task else { return }
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(config)
            guard let string = String(data: data, encoding: .utf8) else { return }
            task.send(.string(string)) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.notifyDisconnect(error)
                } else {
                    self.delegate?.sonioxClientDidConnect(self)
                }
            }
        } catch {
            notifyDisconnect(error)
        }
    }

    private func sendEmptyTerminator() {
        task?.send(.data(Data())) { _ in }
    }

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.notifyDisconnect(error)
            case .success(let message):
                self.handle(message)
                self.receiveLoop()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let payload: Data
        switch message {
        case .data(let data):
            payload = data
        case .string(let string):
            payload = Data(string.utf8)
        @unknown default:
            return
        }
        guard let response = try? JSONDecoder().decode(SonioxResponse.self, from: payload) else {
            return
        }

        if let errorMessage = response.errorMessage {
            notifyDisconnect(NSError(
                domain: "Soniox",
                code: response.errorCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            ))
            return
        }

        if let processedMs = response.totalAudioProcMs {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.sonioxClient(self, didReportProcessedAudioMs: processedMs)
            }
        }

        if response.finished == true {
            notifyDisconnect(nil)
            return
        }

        guard let tokens = response.tokens, !tokens.isEmpty else { return }
        process(tokens: tokens)
    }

    private func process(tokens: [SonioxToken]) {
        var committedOriginal = ""
        var committedTranslated = ""
        var pendingOriginal = ""
        var pendingTranslated = ""

        for token in tokens {
            if let speakerString = token.speaker, let speaker = Int(speakerString) {
                lastSpeaker = speaker
            }
            // Soniox emits "<end>" between utterances; surface as paragraph break.
            let text = token.text == "<end>" ? "\n" : token.text

            if token.isFinal == true {
                if token.isTranslation {
                    committedTranslated += text
                } else if token.isOriginal {
                    committedOriginal += text
                }
            } else {
                if token.isTranslation {
                    pendingTranslated += text
                } else if token.isOriginal {
                    pendingOriginal += text
                }
            }
        }

        let speaker = lastSpeaker
        if !committedOriginal.isEmpty || !committedTranslated.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.sonioxClient(
                    self,
                    didCommitOriginal: committedOriginal,
                    translated: committedTranslated,
                    speaker: speaker
                )
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.sonioxClient(
                self,
                didReceivePartialOriginal: pendingOriginal,
                translated: pendingTranslated
            )
        }
    }

    private func notifyDisconnect(_ error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.sonioxClient(self, didDisconnectWithError: error)
        }
    }
}
