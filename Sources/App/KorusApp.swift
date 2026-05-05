import AppKit
import SwiftUI

@main
struct KorusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings live inline inside the overlay; the SwiftUI App protocol just needs a scene.
        Settings { EmptyView() }
    }
}
