import CoreGraphics
import Foundation

/// Where the Dynamic Island cutout is on screen and the little "floors" Murzik walks on around it.
///
/// All values are in screen points with the origin at the top-left corner of the screen.
struct IslandGeometry: Equatable {
    /// Size of the hardware island on every Dynamic Island iPhone (14 Pro … 17 Pro Max).
    static let pillSize = CGSize(width: 126, height: 37.33)
    /// Side of the square box a cat pose is drawn in (sprites are square, see `MurzikSprite`).
    static let catBox: CGFloat = 44
    /// Approximate height of a standing / sitting cat inside `catBox`.
    static let catHeight: CGFloat = 31

    let screen: CGSize
    let safeTop: CGFloat
    let hasIsland: Bool
    /// The island cutout, or a virtual pill whose bottom edge is the bottom of the status bar
    /// when the device has no island.
    let pill: CGRect

    init(screen: CGSize, safeTop: CGFloat, isPhone: Bool = true) {
        self.screen = screen
        self.safeTop = safeTop
        let island = Self.detectsIsland(safeTop: safeTop, isPhone: isPhone, screenWidth: screen.width)
        hasIsland = island
        let size = Self.pillSize
        let x = (screen.width - size.width) / 2
        if island {
            // 14 Pro / 15 / 15 Pro: safe top 59, island top 11.33.
            // 16 Pro / 17 Pro / 17 Pro Max: safe top 62, island top ≈ 14.33.
            let top = min(max(safeTop - 47.67, 10), 18)
            pill = CGRect(x: x, y: top, width: size.width, height: size.height)
        } else {
            let bottom = max(safeTop, 20)
            pill = CGRect(x: x, y: bottom - size.height, width: size.width, height: size.height)
        }
    }

    /// Dynamic Island iPhones have a top safe-area inset of 59 pt or more in portrait;
    /// notch iPhones have 44–50 pt, home-button iPhones 20 pt.
    static func detectsIsland(safeTop: CGFloat, isPhone: Bool, screenWidth: CGFloat) -> Bool {
        isPhone && safeTop >= 58.5 && screenWidth >= 370 && screenWidth <= 480
    }

    // MARK: Floors

    /// Floor under the island: Murzik's ears just clear the island's bottom edge.
    var underFloorY: CGFloat { pill.maxY + Self.catHeight + 3 }
    /// Floor beside the island, on the status-bar line: feet level with the island's bottom edge.
    var ledgeY: CGFloat { pill.maxY - 1 }
    /// Feet height when Murzik has hopped up "into" the island (completely hidden).
    var insideFeetY: CGFloat { pill.maxY - 3 }

    var leftLedgeX: CGFloat { pill.minX - 17 }
    var rightLedgeX: CGFloat { pill.maxX + 15 }
    /// Where a walking cat is completely hidden behind the island, near each end.
    var insideLeftX: CGFloat { pill.minX + 34 }
    var insideRightX: CGFloat { pill.maxX - 34 }
    /// Where Murzik stands when only his head pokes out of the island's end.
    var peekLeftX: CGFloat { pill.minX + 5 }
    var peekRightX: CGFloat { pill.maxX - 5 }

    /// Horizontal range Murzik patrols under the island.
    var patrolRange: ClosedRange<CGFloat> {
        let margin = Self.catBox / 2 + 6
        let lower = max(pill.minX - 56, margin)
        let upper = min(pill.maxX + 56, screen.width - margin)
        return lower...max(lower, upper)
    }

    /// Range under the island from which he can hop straight up into it.
    var underPillRange: ClosedRange<CGFloat> {
        (pill.minX + 30)...(pill.maxX - 30)
    }

    func clampToPatrol(_ x: CGFloat) -> CGFloat {
        min(max(x, patrolRange.lowerBound), patrolRange.upperBound)
    }

    func clampUnderPill(_ x: CGFloat) -> CGFloat {
        min(max(x, underPillRange.lowerBound), underPillRange.upperBound)
    }

    /// Which surface a cat whose feet are at `point` is on.
    func surface(at point: CGPoint, hidden: Bool = false) -> WalkerSurface {
        if hidden { return hasIsland ? .inside : .under }
        if abs(point.y - underFloorY) < 3 { return .under }
        if hasIsland, point.y > pill.minY, point.y < pill.maxY + 0.5 {
            if point.x > pill.minX + 12, point.x < pill.maxX - 12 { return .inside }
            if abs(point.y - ledgeY) < 3 { return point.x < pill.midX ? .ledgeLeft : .ledgeRight }
        }
        return .air
    }

    /// The cat's visible box (feet at the bottom centre) — used by tests to check hiding.
    func catRect(feet: CGPoint, width: CGFloat = 30) -> CGRect {
        CGRect(x: feet.x - width / 2, y: feet.y - Self.catHeight + 1, width: width, height: Self.catHeight - 2)
    }
}

/// The surfaces Murzik can be on.
enum WalkerSurface: Equatable, Sendable {
    case under, ledgeLeft, ledgeRight, inside, air
}
