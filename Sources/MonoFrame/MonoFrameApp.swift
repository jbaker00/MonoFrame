import SwiftUI

@main
struct MonoFrameApp: App {
    @StateObject private var frameStore = FrameStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(frameStore)
        }
    }
}
