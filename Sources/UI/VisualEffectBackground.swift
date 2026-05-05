import AppKit
import SwiftUI

/// SwiftUI bridge to NSVisualEffectView — used as the overlay's frosted backdrop so the
/// panel feels like a Big Sur+ HUD floating over content rather than a flat dark rectangle.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Marks a region as "not the window's drag handle" — AppKit's `isMovableByWindowBackground`
/// otherwise lets the user drag the whole panel by clicking anywhere transparent.
struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        BlockerView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class BlockerView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}
