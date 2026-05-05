import Foundation

enum SonioxConstants {
    static let websocketURL = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
    static let modelsURL = URL(string: "https://api.soniox.com/v1/models")!
    static let model = "stt-rt-v4"
    static let sampleRate: Int = 16_000
    static let channels: Int = 1
}

struct SonioxConfig: Encodable {
    let apiKey: String
    let model: String
    let audioFormat: String
    let sampleRate: Int
    let numChannels: Int
    let languageHints: [String]?
    let translation: TranslationConfig?
    let enableSpeakerDiarization: Bool
    let enableLanguageIdentification: Bool

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case model
        case audioFormat = "audio_format"
        case sampleRate = "sample_rate"
        case numChannels = "num_channels"
        case languageHints = "language_hints"
        case translation
        case enableSpeakerDiarization = "enable_speaker_diarization"
        case enableLanguageIdentification = "enable_language_identification"
    }
}

struct TranslationConfig: Encodable {
    let type: String                  // "one_way" or "two_way"
    let targetLanguage: String?       // for one_way
    let languageA: String?            // for two_way
    let languageB: String?            // for two_way

    enum CodingKeys: String, CodingKey {
        case type
        case targetLanguage = "target_language"
        case languageA = "language_a"
        case languageB = "language_b"
    }

    static func oneWay(target: String) -> TranslationConfig {
        TranslationConfig(type: "one_way", targetLanguage: target, languageA: nil, languageB: nil)
    }
}

struct SonioxResponse: Decodable {
    let tokens: [SonioxToken]?
    let finished: Bool?
    let errorCode: Int?
    let errorMessage: String?
    let totalAudioProcMs: Int?

    enum CodingKeys: String, CodingKey {
        case tokens
        case finished
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case totalAudioProcMs = "total_audio_proc_ms"
    }
}

struct SonioxToken: Decodable {
    let text: String
    let isFinal: Bool?
    let translationStatus: String?
    let language: String?
    let speaker: String?

    enum CodingKeys: String, CodingKey {
        case text
        case isFinal = "is_final"
        case translationStatus = "translation_status"
        case language
        case speaker
    }

    var isTranslation: Bool {
        translationStatus == "translation"
    }

    var isOriginal: Bool {
        translationStatus == nil || translationStatus == "none" || translationStatus == "original"
    }
}
