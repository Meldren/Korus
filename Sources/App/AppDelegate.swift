import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings = AppSettings()
    let transcript = TranscriptStore()
    let actions = AppActions()
    let languages = SonioxLanguageService()

    private var overlayController: OverlayController?
    private var coordinator: AudioCaptureCoordinator?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = KLogoRenderer.makeDockIcon()

        let coordinator = AudioCaptureCoordinator(settings: settings, transcript: transcript)
        self.coordinator = coordinator

        actions.onToggle = { [weak self] in self?.toggle() }
        actions.onQuit = { NSApp.terminate(nil) }
        actions.onHideOverlay = { [weak self] in self?.overlayController?.hide() }

        let overlay = OverlayController(
            transcript: transcript,
            settings: settings,
            actions: actions,
            languages: languages
        )
        self.overlayController = overlay

        coordinator.isRunningPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in self?.actions.isRunning = running }
            .store(in: &cancellables)

        languages.refresh(apiKey: settings.sonioxAPIKey)
        settings.$sonioxAPIKey
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] key in self?.languages.refresh(apiKey: key) }
            .store(in: &cancellables)

        if settings.showOverlayOnLaunch || settings.sonioxAPIKey.isEmpty {
            overlay.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlayController?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    private func toggle() {
        guard let coordinator else { return }
        if coordinator.isRunning {
            coordinator.stop()
        } else {
            coordinator.start()
        }
    }
}
