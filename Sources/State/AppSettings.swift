import Foundation
import Combine

enum AudioSource: String, CaseIterable, Identifiable {
    case microphone
    case systemAudio
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System audio"
        case .both: return "Both (mic + system)"
        }
    }
}

struct LanguageOption: Identifiable, Hashable {
    let id: String       // BCP-47 code, "auto" for autodetect
    let displayName: String

    static let autoDetect = LanguageOption(id: "auto", displayName: "Auto-detect")
}

final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var sonioxAPIKey: String {
        didSet { defaults.set(sonioxAPIKey, forKey: Keys.sonioxAPIKey) }
    }

    @Published var sourceLanguage: String {
        didSet { defaults.set(sourceLanguage, forKey: Keys.sourceLanguage) }
    }

    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) }
    }

    @Published var audioSource: AudioSource {
        didSet { defaults.set(audioSource.rawValue, forKey: Keys.audioSource) }
    }

    @Published var showOriginal: Bool {
        didSet { defaults.set(showOriginal, forKey: Keys.showOriginal) }
    }

    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }

    @Published var overlayOpacity: Double {
        didSet { defaults.set(overlayOpacity, forKey: Keys.overlayOpacity) }
    }

    @Published var showOverlayOnLaunch: Bool {
        didSet { defaults.set(showOverlayOnLaunch, forKey: Keys.showOverlayOnLaunch) }
    }

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }

    @Published var translationEnabled: Bool {
        didSet { defaults.set(translationEnabled, forKey: Keys.translationEnabled) }
    }

    /// Optional override for the sessions folder. Empty = default
    /// `~/Library/Application Support/Korus/sessions`. Tilde expansion is applied at use time.
    @Published var sessionsCustomPath: String {
        didSet { defaults.set(sessionsCustomPath, forKey: Keys.sessionsCustomPath) }
    }

    init() {
        self.sonioxAPIKey = defaults.string(forKey: Keys.sonioxAPIKey) ?? ""
        self.sourceLanguage = defaults.string(forKey: Keys.sourceLanguage) ?? "auto"
        self.targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "ru"
        self.audioSource = AudioSource(
            rawValue: defaults.string(forKey: Keys.audioSource) ?? AudioSource.systemAudio.rawValue
        ) ?? .systemAudio
        self.showOriginal = defaults.object(forKey: Keys.showOriginal) as? Bool ?? true
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 22
        self.overlayOpacity = defaults.object(forKey: Keys.overlayOpacity) as? Double ?? 0.85
        self.showOverlayOnLaunch = defaults.object(forKey: Keys.showOverlayOnLaunch) as? Bool ?? true
        self.alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        self.translationEnabled = defaults.object(forKey: Keys.translationEnabled) as? Bool ?? true
        self.sessionsCustomPath = defaults.string(forKey: Keys.sessionsCustomPath) ?? ""
    }

    private enum Keys {
        static let sonioxAPIKey = "soniox.apiKey"
        static let sourceLanguage = "sourceLanguage"
        static let targetLanguage = "targetLanguage"
        static let audioSource = "audioSource"
        static let showOriginal = "showOriginal"
        static let fontSize = "fontSize"
        static let overlayOpacity = "overlayOpacity"
        static let showOverlayOnLaunch = "showOverlayOnLaunch"
        static let alwaysOnTop = "alwaysOnTop"
        static let translationEnabled = "translationEnabled"
        static let sessionsCustomPath = "sessionsCustomPath"
    }
}
