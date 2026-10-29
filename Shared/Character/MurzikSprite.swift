import SwiftUI
import UIKit

/// Pre-rendered full-body poses of 3D Murzik.
///
/// CONTRACT (shared by the 3D renderer, the Live Activity and the in-app island walker):
/// - Each case is an image set in `Shared/Sprites.xcassets` named by its raw value.
/// - Images are square, transparent PNGs exported at `exportPoints` × `exportScale` pixels.
/// - Side-view poses face RIGHT (mirror with `scaleEffect(x: -1)` to face left).
/// - The cat stands on the bottom edge of the canvas (feet ~4% above the bottom), centered horizontally.
/// - `peek` shows only the head and front paws rising from the bottom edge (for peeking out of the island).
/// When an image is missing (e.g. before sprites are exported), `SpriteImage` falls back to the 2D drawing.
enum MurzikSprite: String, CaseIterable, Sendable {
    // Walk cycle, side view facing right, 8 frames.
    case walk0 = "murzik_walk_0"
    case walk1 = "murzik_walk_1"
    case walk2 = "murzik_walk_2"
    case walk3 = "murzik_walk_3"
    case walk4 = "murzik_walk_4"
    case walk5 = "murzik_walk_5"
    case walk6 = "murzik_walk_6"
    case walk7 = "murzik_walk_7"
    // Poses (3/4 front view unless noted).
    case sitFront = "murzik_sit_front"
    case sitSide = "murzik_sit_side"      // side view, facing right
    case happy = "murzik_happy"
    case loving = "murzik_loving"
    case hungry = "murzik_hungry"
    case sleepy = "murzik_sleepy"          // loaf, half-closed eyes
    case sleeping = "murzik_sleeping"      // curled up
    case playful = "murzik_playful"        // pounce crouch, side view facing right
    case surprised = "murzik_surprised"    // arched back
    case excited = "murzik_excited"        // jumping
    case groom = "murzik_groom"            // licking a paw
    case stretch = "murzik_stretch"        // side view facing right
    case peek = "murzik_peek"              // head + paws from the bottom edge

    static let walkCycle: [MurzikSprite] = [.walk0, .walk1, .walk2, .walk3, .walk4, .walk5, .walk6, .walk7]

    static let exportPoints: CGFloat = 64
    static let exportScale: CGFloat = 3

    static func forMood(_ mood: MurzikMood) -> MurzikSprite {
        switch mood {
        case .idle, .blinking: return .sitFront
        case .happy: return .happy
        case .sleepy: return .sleepy
        case .sleeping: return .sleeping
        case .playful: return .playful
        case .hungry: return .hungry
        case .loving: return .loving
        case .surprised: return .surprised
        case .excited: return .excited
        }
    }

    /// The image if it has been exported into the asset catalog.
    var uiImage: UIImage? { UIImage(named: rawValue) }
}

/// Shows a sprite, or the 2D vector cat when the sprite image is not available.
struct SpriteImage: View {
    var sprite: MurzikSprite
    /// Mood used by the 2D fallback.
    var fallbackMood: MurzikMood = .idle
    var facingLeft = false

    var body: some View {
        Group {
            if let image = sprite.uiImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                CatFace(mood: fallbackMood, detail: .compact)
            }
        }
        .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}
