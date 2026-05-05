import Combine
import Foundation

final class AppActions: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var isShowingSettings: Bool = false

    var onToggle: () -> Void = {}
    var onQuit: () -> Void = {}
    var onHideOverlay: () -> Void = {}
    var onClearTranscript: () -> Void = {}

    func toggle() { onToggle() }
    func quit() { onQuit() }
    func hideOverlay() { onHideOverlay() }
    func clearTranscript() { onClearTranscript() }
    func toggleSettings() { isShowingSettings.toggle() }
    func showSettings() { isShowingSettings = true }
    func hideSettings() { isShowingSettings = false }
}
