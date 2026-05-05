import Combine
import Foundation

/// Fetches supported languages from Soniox /v1/models, cached in UserDefaults so the
/// picker is populated instantly on the next launch.
final class SonioxLanguageService: ObservableObject {
    private struct ModelsResponse: Decodable {
        let models: [Model]
    }

    private struct Model: Decodable {
        let id: String
        let name: String?
        let transcriptionMode: String?
        let languages: [LanguageEntry]?

        enum CodingKeys: String, CodingKey {
            case id, name, languages
            case transcriptionMode = "transcription_mode"
        }
    }

    private struct LanguageEntry: Decodable {
        let code: String
        let name: String
    }

    @Published private(set) var languages: [LanguageOption]

    private let defaults = UserDefaults.standard
    private let cacheKey = "soniox.languages.cache.v1"
    private let modelKey = "soniox.languages.cacheModel"

    init() {
        self.languages = Self.loadCache(defaults: defaults, key: cacheKey) ?? []
    }

    var isLoaded: Bool { !languages.isEmpty }

    func refresh(apiKey: String) {
        guard !apiKey.isEmpty else { return }

        var request = URLRequest(url: SonioxConstants.modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard
                let self,
                error == nil,
                let data,
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else { return }

            do {
                let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
                let preferredModel = decoded.models.first(where: { $0.id == SonioxConstants.model })
                    ?? decoded.models.first(where: { $0.transcriptionMode == "real_time" })
                    ?? decoded.models.first

                guard let entries = preferredModel?.languages, !entries.isEmpty else { return }

                let options: [LanguageOption] = entries
                    .map { LanguageOption(id: $0.code, displayName: $0.name) }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

                Self.persistCache(options, defaults: self.defaults, key: self.cacheKey)
                DispatchQueue.main.async {
                    self.languages = options
                }
            } catch {}
        }.resume()
    }

    private static func loadCache(defaults: UserDefaults, key: String) -> [LanguageOption]? {
        guard
            let data = defaults.data(forKey: key),
            let raw = try? JSONDecoder().decode([CachedLanguage].self, from: data)
        else { return nil }
        return raw.map { LanguageOption(id: $0.id, displayName: $0.name) }
    }

    private static func persistCache(_ options: [LanguageOption], defaults: UserDefaults, key: String) {
        let raw = options.map { CachedLanguage(id: $0.id, name: $0.displayName) }
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: key)
        }
    }

    private struct CachedLanguage: Codable {
        let id: String
        let name: String
    }
}
