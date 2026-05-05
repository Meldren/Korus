import AppKit
import SwiftUI

/// AppKit-backed split between two SwiftUI views with a draggable vertical divider.
/// SwiftUI's GeometryReader+@State approach re-lays out the entire text on every
/// pixel of mouse travel, which makes long transcripts flicker. NSSplitView handles
/// live resize natively and smoothly, so we host our two columns inside it.
struct SplitColumnsView<Left: View, Right: View>: NSViewRepresentable {
    let left: Left
    let right: Right
    /// Minimum width (in pt) for each column.
    let minSide: CGFloat

    init(minSide: CGFloat = 140, @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.minSide = minSide
        self.left = left()
        self.right = right()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(minSide: minSide)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let split = ManualSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = context.coordinator
        split.autosaveName = "Korus.SplitColumns"

        let leftHost = NSHostingView(rootView: left)
        leftHost.translatesAutoresizingMaskIntoConstraints = false
        let rightHost = NSHostingView(rootView: right)
        rightHost.translatesAutoresizingMaskIntoConstraints = false

        split.addArrangedSubview(leftHost)
        split.addArrangedSubview(rightHost)
        return split
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        let subs = nsView.arrangedSubviews
        if let lv = subs.first as? NSHostingView<Left> {
            lv.rootView = left
        }
        if subs.count > 1, let rv = subs[1] as? NSHostingView<Right> {
            rv.rootView = right
        }
        context.coordinator.minSide = minSide
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var minSide: CGFloat
        init(minSide: CGFloat) { self.minSide = minSide }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMin: CGFloat, ofSubviewAt _: Int) -> CGFloat {
            max(proposedMin, minSide)
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMax: CGFloat, ofSubviewAt _: Int) -> CGFloat {
            min(proposedMax, splitView.bounds.width - minSide)
        }
    }
}

/// NSSplitView subclass that hides its background and tints the divider for the dark
/// HUD overlay. Without this override, NSSplitView paints a thick light divider that
/// stands out against the visual-effect material.
private final class ManualSplitView: NSSplitView {
    override var dividerColor: NSColor { NSColor.white.withAlphaComponent(0.10) }
    override var dividerThickness: CGFloat { 1 }

    override func drawDivider(in rect: NSRect) {
        // Inset a few points top/bottom so the line doesn't touch the rounded
        // corners of the HUD panel.
        let inset = rect.insetBy(dx: 0, dy: 6)
        dividerColor.setFill()
        inset.fill()
    }
}
