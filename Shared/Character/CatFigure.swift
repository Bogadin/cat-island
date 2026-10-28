import SwiftUI

/// Murzik sitting: body, paws and tail behind the face. Used in the app and on the Lock Screen.
/// Aspect ratio is 1 : 1.32 (width : height).
struct CatFigure: View {
    static let aspect: CGFloat = 1.32

    var mood: MurzikMood
    var eyesClosed = false
    /// Tail angle in degrees (animated by the app; 0 in widgets).
    var tailAngle: Double = 0
    /// Breathing scale applied to the body (1 = rest).
    var breath: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height / Self.aspect)
            let height = width * Self.aspect
            ZStack(alignment: .top) {
                tail(width: width, height: height)
                bodyShape(width: width)
                    .scaleEffect(x: 1, y: breath, anchor: .bottom)
                CatFace(mood: mood, eyesClosed: eyesClosed)
                    .frame(width: width, height: width)
                    .offset(y: (1 - breath) * width * 0.6)
            }
            .frame(width: width, height: height, alignment: .top)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1 / Self.aspect, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("\(Strings.name), \(Strings.moodTitle(mood))"))
    }

    private func bodyShape(width: CGFloat) -> some View {
        ZStack {
            CatShape(.body).fill(
                LinearGradient(
                    colors: [MurzikPalette.furMid, MurzikPalette.furBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            CatShape(.body).stroke(MurzikPalette.rim, lineWidth: width * 0.02)
        }
    }

    private func tail(width: CGFloat, height: CGFloat) -> some View {
        let anchor = UnitPoint(x: 0.68, y: 1.22 / Self.aspect)
        return ZStack {
            CatShape(.tail).stroke(MurzikPalette.rim, style: StrokeStyle(lineWidth: width * 0.115, lineCap: .round))
            CatShape(.tail).stroke(MurzikPalette.furMid, style: StrokeStyle(lineWidth: width * 0.075, lineCap: .round))
        }
        .rotationEffect(.degrees(tailAngle), anchor: anchor)
    }
}
