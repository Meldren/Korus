#!/usr/bin/env swift
import AppKit
import SwiftUI

// Mirrors KDockIconView in Sources/UI/KLogo.swift so the static AppIcon and the
// runtime Dock icon look identical. Run once and commit the resulting PNGs:
//   swift Tools/generate_appicon.swift Resources/Assets.xcassets/AppIcon.appiconset
struct KDockIconView: View {
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

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/Assets.xcassets/AppIcon.appiconset"

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

@MainActor
func render(pixelSize: CGFloat) -> Data? {
    let renderer = ImageRenderer(content: KDockIconView(dimension: pixelSize))
    renderer.scale = 1
    guard
        let cg = renderer.cgImage,
        case let rep = NSBitmapImageRep(cgImage: cg),
        let data = rep.representation(using: .png, properties: [:])
    else { return nil }
    return data
}

let entries: [(base: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

DispatchQueue.main.async {
    for entry in entries {
        let pixels = entry.base * entry.scale
        let suffix = entry.scale > 1 ? "@2x" : ""
        let name = "icon_\(entry.base)x\(entry.base)\(suffix).png"
        guard let data = render(pixelSize: CGFloat(pixels)) else {
            print("failed: \(name)")
            continue
        }
        let url = URL(fileURLWithPath: "\(outDir)/\(name)")
        try? data.write(to: url)
        print("wrote \(name) (\(pixels)px)")
    }

    let contents = #"""
    {
      "images" : [
        { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16.png", "scale" : "1x" },
        { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16@2x.png", "scale" : "2x" },
        { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32.png", "scale" : "1x" },
        { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32@2x.png", "scale" : "2x" },
        { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png", "scale" : "1x" },
        { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128@2x.png", "scale" : "2x" },
        { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png", "scale" : "1x" },
        { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256@2x.png", "scale" : "2x" },
        { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png", "scale" : "1x" },
        { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512@2x.png", "scale" : "2x" }
      ],
      "info" : { "version" : 1, "author" : "xcode" }
    }
    """#
    try? contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
    print("wrote Contents.json")
    exit(0)
}

RunLoop.main.run()
