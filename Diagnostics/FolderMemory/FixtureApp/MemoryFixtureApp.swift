import SwiftUI

/// Simulator-only source of synthetic Files-provider documents. Never in Orivyn's target.
@main
struct MemoryFixtureApp: App {
    var body: some Scene {
        WindowGroup { Text("Synthetic folder-import test documents") }
    }
}
