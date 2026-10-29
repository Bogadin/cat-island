import Combine
import SwiftUI

/// CONTRACT between the 3D character (owned by the 3D team) and the app screen (owned by the app team).
/// The app screen only uses this public API; everything behind it may change freely.
///
/// This file currently contains a placeholder implementation (2D figure) so the app builds
/// before the 3D model lands. The 3D team replaces the internals, keeping the API.
@MainActor
final class Murzik3DController: ObservableObject {
    /// Current mood (drives idle behaviour, expressions and posture).
    @Published private(set) var mood: MurzikMood = .idle
    /// Called when the user pets Murzik directly in the 3D view (tap or stroke on the cat).
    var onPetted: (() -> Void)?

    init() {}

    func setMood(_ mood: MurzikMood) {
        self.mood = mood
    }

    /// Plays the animation for an action (eat from a bowl, play with a toy, purr, curl up, wake up…).
    func perform(_ action: PetAction) {}

    /// Makes Murzik look toward a point in the view (0...1 in both axes), e.g. the user's finger. `nil` = stop.
    func lookAt(normalizedPoint: CGPoint?) {}
}

/// The 3D stage. Transparent background, fills its frame.
struct Murzik3DView: View {
    @ObservedObject var controller: Murzik3DController

    var body: some View {
        CatFigure(mood: controller.mood)
            .padding(30)
            .contentShape(Rectangle())
            .onTapGesture { controller.onPetted?() }
    }
}
