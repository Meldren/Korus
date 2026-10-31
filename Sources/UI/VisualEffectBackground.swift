import AppKit
import SwiftUI

/// SwiftUI bridge to NSVisualEffectView for the overlay's frosted HUD backdrop.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = DraggableVisualEffectView()
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

    private final class DraggableVisualEffectView: NSVisualEffectView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Dedicated draggable view that can be attached to toolbars/headers to initiate window dragging.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Opts a region out of `isMovableByWindowBackground` so clicks here don't drag the panel.
struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        BlockerView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class BlockerView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}
