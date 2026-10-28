import SwiftUI

/// Maps a 0...1 design space onto the largest centered square of a rect.
struct UnitSpace {
    let origin: CGPoint
    let size: CGFloat

    init(_ rect: CGRect) {
        size = min(rect.width, rect.height)
        origin = CGPoint(x: rect.midX - size / 2, y: rect.midY - size / 2)
    }

    /// Width-based mapping for tall drawings (the full-body figure).
    init(widthOf rect: CGRect) {
        size = rect.width
        origin = rect.origin
    }

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * size, y: origin.y + y * size)
    }

    func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
        CGRect(x: origin.x + x0 * size, y: origin.y + y0 * size, width: (x1 - x0) * size, height: (y1 - y0) * size)
    }

    func rect(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        rect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
    }
}

enum EyeSide: Sendable {
    case left, right

    var cx: CGFloat { self == .left ? CatGeometry.leftEyeX : 1 - CatGeometry.leftEyeX }
    /// Mirrors an x coordinate designed for the left side.
    func x(_ v: CGFloat) -> CGFloat { self == .left ? v : 1 - v }
}

enum CatGeometry {
    static let leftEyeX: CGFloat = 0.33
    static let eyeY: CGFloat = 0.62
    static let eyeWidth: CGFloat = 0.21
    static let eyeHeight: CGFloat = 0.21
}

/// Every part of Murzik as a resolution-independent shape in the unit square.
struct CatShape: Shape {
    enum Part {
        case head
        case innerEars
        case eyeball(EyeSide, scale: CGFloat)
        case halfEyeball(EyeSide)
        case eyelid(EyeSide)
        case slitPupil(EyeSide, width: CGFloat, dx: CGFloat, scale: CGFloat)
        case roundPupil(EyeSide, diameter: CGFloat, dx: CGFloat, dy: CGFloat)
        case highlight(EyeSide, dx: CGFloat, dy: CGFloat, diameter: CGFloat)
        case happyArc(EyeSide)
        case sleepArc(EyeSide)
        case blinkLine(EyeSide)
        case heartEye(EyeSide)
        case nose
        case mouthW
        case mouthOpen
        case mouthO
        case tongue
        case whiskers
        case blush
        // Full-body figure (width-based space, height ≈ 1.32)
        case body
        case tail
    }

    var part: Part

    init(_ part: Part) { self.part = part }

    func path(in rect: CGRect) -> Path {
        switch part {
        case .body, .tail:
            return Self.figurePath(part, UnitSpace(widthOf: rect))
        default:
            return Self.facePath(part, UnitSpace(rect))
        }
    }

    // MARK: Face

    private static func facePath(_ part: Part, _ u: UnitSpace) -> Path {
        let ey = CatGeometry.eyeY
        let ew = CatGeometry.eyeWidth
        let eh = CatGeometry.eyeHeight

        switch part {
        case .head:
            let head = Path(ellipseIn: u.rect(0.08, 0.30, 0.92, 0.96))
            var ears = Path()
            for side in [EyeSide.left, .right] {
                ears.move(to: u.p(side.x(0.11), 0.62))
                ears.addLine(to: u.p(side.x(0.16), 0.17))
                ears.addQuadCurve(to: u.p(side.x(0.26), 0.13), control: u.p(side.x(0.18), 0.06))
                ears.addLine(to: u.p(side.x(0.48), 0.36))
                ears.closeSubpath()
            }
            return head.union(ears)

        case .innerEars:
            var p = Path()
            for side in [EyeSide.left, .right] {
                p.move(to: u.p(side.x(0.185), 0.43))
                p.addLine(to: u.p(side.x(0.20), 0.23))
                p.addQuadCurve(to: u.p(side.x(0.25), 0.215), control: u.p(side.x(0.21), 0.17))
                p.addLine(to: u.p(side.x(0.38), 0.355))
                p.closeSubpath()
            }
            return p

        case let .eyeball(side, scale):
            return almond(u, cx: side.cx, cy: ey, w: ew * scale, h: eh * scale)

        case let .halfEyeball(side):
            let eye = almond(u, cx: side.cx, cy: ey, w: ew, h: eh)
            let lower = Path(u.rect(side.cx - ew, ey - 0.012, side.cx + ew, ey + eh))
            return eye.intersection(lower)

        case let .eyelid(side):
            var p = Path()
            p.move(to: u.p(side.cx - ew / 2, ey + 0.002))
            p.addQuadCurve(to: u.p(side.cx + ew / 2, ey + 0.002), control: u.p(side.cx, ey - 0.03))
            return p

        case let .slitPupil(side, width, dx, scale):
            return Path(ellipseIn: u.rect(cx: side.cx + dx, cy: ey, w: ew * width * scale, h: eh * 0.9 * scale))

        case let .roundPupil(side, diameter, dx, dy):
            return Path(ellipseIn: u.rect(cx: side.cx + dx, cy: ey + dy, w: diameter, h: diameter))

        case let .highlight(side, dx, dy, diameter):
            return Path(ellipseIn: u.rect(cx: side.cx + dx, cy: ey + dy, w: diameter, h: diameter))

        case let .happyArc(side):
            var p = Path()
            p.move(to: u.p(side.cx - 0.08, ey + 0.03))
            p.addQuadCurve(to: u.p(side.cx + 0.08, ey + 0.03), control: u.p(side.cx, ey - 0.09))
            return p

        case let .sleepArc(side):
            var p = Path()
            p.move(to: u.p(side.cx - 0.08, ey - 0.005))
            p.addQuadCurve(to: u.p(side.cx + 0.08, ey - 0.005), control: u.p(side.cx, ey + 0.075))
            return p

        case let .blinkLine(side):
            var p = Path()
            p.move(to: u.p(side.cx - 0.09, ey + 0.005))
            p.addQuadCurve(to: u.p(side.cx + 0.09, ey + 0.005), control: u.p(side.cx, ey + 0.035))
            return p

        case let .heartEye(side):
            return heart(u, cx: side.cx, cy: ey + 0.005, w: 0.21)

        case .nose:
            var p = Path()
            p.move(to: u.p(0.458, 0.735))
            p.addLine(to: u.p(0.542, 0.735))
            p.addQuadCurve(to: u.p(0.5, 0.782), control: u.p(0.535, 0.765))
            p.addQuadCurve(to: u.p(0.458, 0.735), control: u.p(0.465, 0.765))
            p.closeSubpath()
            return p

        case .mouthW:
            var p = Path()
            p.move(to: u.p(0.5, 0.775))
            p.addLine(to: u.p(0.5, 0.795))
            p.move(to: u.p(0.43, 0.80))
            p.addQuadCurve(to: u.p(0.5, 0.795), control: u.p(0.462, 0.835))
            p.addQuadCurve(to: u.p(0.57, 0.80), control: u.p(0.538, 0.835))
            return p

        case .mouthOpen:
            var p = Path()
            p.move(to: u.p(0.44, 0.795))
            p.addLine(to: u.p(0.56, 0.795))
            p.addQuadCurve(to: u.p(0.44, 0.795), control: u.p(0.5, 0.905))
            p.closeSubpath()
            return p

        case .mouthO:
            return Path(ellipseIn: u.rect(cx: 0.5, cy: 0.84, w: 0.065, h: 0.075))

        case .tongue:
            return Path(roundedRect: u.rect(0.505, 0.80, 0.565, 0.875), cornerSize: CGSize(width: 0.03 * u.size, height: 0.03 * u.size))

        case .whiskers:
            var p = Path()
            for side in [EyeSide.left, .right] {
                p.move(to: u.p(side.x(0.31), 0.765)); p.addLine(to: u.p(side.x(0.03), 0.72))
                p.move(to: u.p(side.x(0.31), 0.79)); p.addLine(to: u.p(side.x(0.02), 0.80))
                p.move(to: u.p(side.x(0.32), 0.815)); p.addLine(to: u.p(side.x(0.06), 0.885))
            }
            return p

        case .blush:
            var p = Path()
            p.addEllipse(in: u.rect(cx: 0.215, cy: 0.75, w: 0.12, h: 0.06))
            p.addEllipse(in: u.rect(cx: 0.785, cy: 0.75, w: 0.12, h: 0.06))
            return p

        case .body, .tail:
            return Path()
        }
    }

    // MARK: Full body (width-based coordinates; head occupies y 0...1)

    private static func figurePath(_ part: Part, _ u: UnitSpace) -> Path {
        switch part {
        case .body:
            let torso = Path(ellipseIn: u.rect(0.17, 0.62, 0.83, 1.30))
            var paws = Path()
            paws.addEllipse(in: u.rect(0.25, 1.17, 0.47, 1.32))
            paws.addEllipse(in: u.rect(0.53, 1.17, 0.75, 1.32))
            return torso.union(paws)
        case .tail:
            var p = Path()
            p.move(to: u.p(0.70, 1.22))
            p.addCurve(to: u.p(1.00, 0.86), control1: u.p(1.00, 1.28), control2: u.p(1.07, 1.02))
            p.addQuadCurve(to: u.p(0.93, 0.68), control: u.p(0.99, 0.70))
            return p
        default:
            return Path()
        }
    }

    // MARK: Helpers

    private static func almond(_ u: UnitSpace, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.move(to: u.p(cx - w / 2, cy))
        p.addCurve(to: u.p(cx + w / 2, cy), control1: u.p(cx - w * 0.40, cy - h * 0.67), control2: u.p(cx + w * 0.40, cy - h * 0.67))
        p.addCurve(to: u.p(cx - w / 2, cy), control1: u.p(cx + w * 0.40, cy + h * 0.67), control2: u.p(cx - w * 0.40, cy + h * 0.67))
        p.closeSubpath()
        return p
    }

    static func heart(_ u: UnitSpace, cx: CGFloat, cy: CGFloat, w: CGFloat) -> Path {
        var p = Path()
        let bottom = u.p(cx, cy + 0.40 * w)
        p.move(to: bottom)
        p.addCurve(to: u.p(cx - 0.5 * w, cy - 0.10 * w), control1: u.p(cx - 0.18 * w, cy + 0.26 * w), control2: u.p(cx - 0.5 * w, cy + 0.12 * w))
        p.addCurve(to: u.p(cx, cy - 0.26 * w), control1: u.p(cx - 0.5 * w, cy - 0.46 * w), control2: u.p(cx - 0.06 * w, cy - 0.48 * w))
        p.addCurve(to: u.p(cx + 0.5 * w, cy - 0.10 * w), control1: u.p(cx + 0.06 * w, cy - 0.48 * w), control2: u.p(cx + 0.5 * w, cy - 0.46 * w))
        p.addCurve(to: bottom, control1: u.p(cx + 0.5 * w, cy + 0.12 * w), control2: u.p(cx + 0.18 * w, cy + 0.26 * w))
        p.closeSubpath()
        return p
    }
}
