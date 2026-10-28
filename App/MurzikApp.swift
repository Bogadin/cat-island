import SwiftUI

@main
struct MurzikApp: App {
    @StateObject private var model = PetModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.light)
                .onOpenURL { _ in model.reload() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.becameActive()
            }
        }
    }
}
