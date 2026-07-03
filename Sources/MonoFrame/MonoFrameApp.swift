import SwiftUI

@main
struct MonoFrameApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var ads = AdsManager()
    @StateObject private var frameStore = FrameStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ads)
                .environmentObject(frameStore)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { ads.activate() }
                }
                .task {
                    // Covers the case where the scene is already active by
                    // the time the view hierarchy exists; activate() is
                    // idempotent so double-firing is harmless.
                    if scenePhase == .active { ads.activate() }
                }
        }
    }
}
