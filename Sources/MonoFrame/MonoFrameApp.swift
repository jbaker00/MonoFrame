import SwiftUI
import FirebaseCore

@main
struct MonoFrameApp: App {
    @StateObject private var frameStore = FrameStore()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(frameStore)
        }
    }
}
