import SwiftUI

/// Environment values the main screen passes down to the room, the toys and the island walker.
private struct MurzikPetActionKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

private struct MurzikAnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Pets Murzik the same way as a tap on the stage (through `StageDirector`: 3D reaction,
    /// ignored in toy mode). Nil outside the main screen.
    var murzikPet: (@MainActor () -> Void)? {
        get { self[MurzikPetActionKey.self] }
        set { self[MurzikPetActionKey.self] = newValue }
    }

    /// True while the room is covered (settings sheet) or the app is not active:
    /// continuous animations (timelines, the 3D view) stop to save battery.
    var murzikAnimationsPaused: Bool {
        get { self[MurzikAnimationsPausedKey.self] }
        set { self[MurzikAnimationsPausedKey.self] = newValue }
    }
}
