import SwiftUI

@main
struct MurzikApp: App {
    @StateObject private var model = PetModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // UI tests start from a known state.
        if CommandLine.arguments.contains("-uitest-hungry") {
            PetStorage().save(PetState(fullness: 0.1, energy: 0.8, happiness: 0.5, lastUpdated: .now))
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay { IslandWalkerOverlay() }
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.light)
                .onOpenURL { _ in model.reload() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.becameActive()
            } else if phase == .background {
                IslandChoreographer.appDidEnterBackground()
            }
        }
    }
}
