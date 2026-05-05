import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayController {
    private enum ExpandDirection { case down, up }

    private let window: KorusOverlayWindow
    private let transcript: TranscriptStore
    private let settings: AppSettings
    private let actions: AppActions

    private var cancellables = Set<AnyCancellable>()
    private var lastExpandDirection: ExpandDirection = .down

    private static let captionsHeight: CGFloat = 240
    private static let settingsHeight: CGFloat = 600
    private static let width: CGFloat = 820
    private static let edgePadding: CGFloat = 12

    init(transcript: TranscriptStore, settings: AppSettings, actions: AppActions, languages: SonioxLanguageService) {
        self.transcript = transcript
        self.settings = settings
        self.actions = actions

        let initialSize = NSSize(width: Self.width, height: Self.captionsHeight)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // ~22% above the bottom of the visible frame: clear of player controls,
        // low enough to read like a subtitle.
        let origin = NSPoint(
            x: visible.midX - initialSize.width / 2,
            y: visible.minY + visible.height * 0.22
        )
        let frame = NSRect(origin: origin, size: initialSize)

        self.window = KorusOverlayWindow(contentRect: frame)
        let hosting = NSHostingView(
            rootView: OverlayRoot()
                .environmentObject(transcript)
                .environmentObject(settings)
                .environmentObject(actions)
                .environmentObject(languages)
        )
        window.contentView = hosting

        actions.$isShowingSettings
            .removeDuplicates()
            .sink { [weak self] showing in
                self?.resize(toSettings: showing)
            }
            .store(in: &cancellables)

        applyPinning(settings.alwaysOnTop)
        settings.$alwaysOnTop
            .removeDuplicates()
            .sink { [weak self] pinned in
                self?.applyPinning(pinned)
            }
            .store(in: &cancellables)
    }

    private func applyPinning(_ pinned: Bool) {
        if pinned {
            // Float over fullscreen apps, dock, menubar.
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        } else {
            // Pin off → stay on origin space; hide when another app goes fullscreen.
            window.level = .normal
            window.collectionBehavior = [.stationary]
        }
        window.orderFrontRegardless()
    }

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    private func resize(toSettings showing: Bool) {
        let targetHeight: CGFloat = showing ? Self.settingsHeight : Self.captionsHeight
        let current = window.frame
        let visible = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let newOriginY: CGFloat
        if showing {
            // Grow downward (top edge fixed) if there's room, otherwise upward
            // (bottom edge fixed). Centred only when neither side fits.
            let topY = current.origin.y + current.height
            let proposedBottomDown = topY - targetHeight
            let fitsDown = proposedBottomDown >= visible.minY + Self.edgePadding

            if fitsDown {
                newOriginY = proposedBottomDown
                lastExpandDirection = .down
            } else {
                let bottomY = current.origin.y
                let proposedTopUp = bottomY + targetHeight
                if proposedTopUp <= visible.maxY - Self.edgePadding {
                    newOriginY = bottomY
                    lastExpandDirection = .up
                } else {
                    newOriginY = visible.minY + (visible.height - targetHeight) / 2
                    lastExpandDirection = .down
                }
            }
        } else {
            // Collapse along the same edge we expanded from.
            switch lastExpandDirection {
            case .down:
                let topY = current.origin.y + current.height
                newOriginY = topY - targetHeight
            case .up:
                newOriginY = current.origin.y
            }
        }

        let clampedX = max(visible.minX + Self.edgePadding,
                           min(current.origin.x, visible.maxX - current.width - Self.edgePadding))
        let clampedY = max(visible.minY + Self.edgePadding,
                           min(newOriginY, visible.maxY - targetHeight - Self.edgePadding))

        let newFrame = NSRect(
            origin: NSPoint(x: clampedX, y: clampedY),
            size: NSSize(width: current.width, height: targetHeight)
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(newFrame, display: true)
        }
    }

    static let resizeDuration: CFTimeInterval = 0.26
}

/// Toggles captions ↔ settings inside the overlay. The explicit `onReceive` instead of
/// reading the EnvironmentObject directly works around unreliable redraws inside NSHostingView.
struct OverlayRoot: View {
    @EnvironmentObject private var actions: AppActions
    @EnvironmentObject private var settings: AppSettings
    @State private var showingSettings: Bool = false

    private static let cornerRadius: CGFloat = 20

    var body: some View {
        // Shared background sits here; child views MUST NOT paint their own — two
        // semi-transparent layers would compound opacity during cross-fade.
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))

            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.black.opacity(settings.overlayOpacity * 0.7))

            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)

            SubtitleView()
                .opacity(showingSettings ? 0 : 1)
                .allowsHitTesting(!showingSettings)
            InlineSettingsView()
                .opacity(showingSettings ? 1 : 0)
                .allowsHitTesting(showingSettings)
        }
        .animation(.easeInOut(duration: 0.18), value: showingSettings)
        .onAppear { showingSettings = actions.isShowingSettings }
        .onReceive(actions.$isShowingSettings) { newValue in
            showingSettings = newValue
        }
    }
}

final class KorusOverlayWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            // .nonactivatingPanel lets the overlay float over other apps' fullscreen
            // windows without stealing their focus.
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.hasShadow = true
        self.backgroundColor = .clear
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.ignoresMouseEvents = false
        self.minSize = NSSize(width: 320, height: 100)
        self.animationBehavior = .utilityWindow
        self.acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
