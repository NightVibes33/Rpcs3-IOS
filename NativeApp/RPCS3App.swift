import SwiftUI

@main
struct RPCS3App: App {
    @StateObject private var controller = CoreController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .background:
                        controller.sceneDidEnterBackground()
                    case .active:
                        controller.sceneDidBecomeActive()
                    default:
                        break
                    }
                }
        }
    }
}
