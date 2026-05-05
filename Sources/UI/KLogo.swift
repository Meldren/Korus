import AppKit
import SwiftUI

struct KLogoView: View {
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        Text("K")
            .font(.system(size: size, weight: .black, design: .rounded))
            .kerning(-0.5)
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.35), radius: max(1, size * 0.06), x: 0, y: max(1, size * 0.04))
    }
}

private struct KDockIconView: View {
    let dimension: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: dimension * 0.225, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.11, blue: 0.16),
                            Color(red: 0.05, green: 0.05, blue: 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: dimension * 0.225, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: dimension * 0.012)
                )

            Text("K")
                .font(.system(size: dimension * 0.62, weight: .black, design: .rounded))
                .kerning(-dimension * 0.012)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: dimension * 0.05, x: 0, y: -dimension * 0.018)
                .offset(y: -dimension * 0.015)
        }
        .frame(width: dimension, height: dimension)
    }
}

enum KLogoRenderer {
    @MainActor
    static func makeDockIcon(size: CGFloat = 1024) -> NSImage {
        let renderer = ImageRenderer(content: KDockIconView(dimension: size))
        renderer.scale = 1
        if let cg = renderer.cgImage {
            return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
        }
        return NSImage(size: NSSize(width: size, height: size))
    }
}
