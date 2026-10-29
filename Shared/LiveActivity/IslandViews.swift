import AppIntents
import SwiftUI

// Presentation views for the Live Activity. They live in Shared (and take plain values,
// not an ActivityViewContext) so the app's tests can render them to images.
//
// Murzik is drawn full-body everywhere (`IslandCatPose`). His place and pose come from
// `ContentState.scene`; every content update animates him there (≤ 2 s, as iOS allows).

private let beatAnimation = Animation.easeInOut(duration: IslandChoreography.animationDuration)

// MARK: Compact & minimal

/// One side of the compact island. Murzik is drawn on the side his position is on; the other
/// side shows his reaction (hearts, fish…) or his mood symbol. Switching sides slides him out
/// toward the camera on one side and in from the camera on the other.
struct CompactSideView: View {
    var side: IslandScene.CompactSide
    var state: MurzikAttributes.ContentState
    var mood: MurzikMood

    static let width: CGFloat = 46
    static let height: CGFloat = 34
    static let catSize: CGFloat = 32

    var body: some View {
        let scene = state.scene
        ZStack(alignment: .bottomLeading) {
            if scene.compactSide == side {
                IslandCatPose(scene: scene, mood: mood, size: Self.catSize)
                    .offset(x: (Self.width - Self.catSize) * CGFloat(scene.compactLocalPosition))
                    .transition(.move(edge: side == .leading ? .trailing : .leading).combined(with: .opacity))
            } else {
                companion(scene)
                    .frame(width: Self.width, height: Self.height)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.width, height: Self.height, alignment: .bottomLeading)
        .animation(beatAnimation, value: scene.step)
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private func companion(_ scene: IslandScene) -> some View {
        if scene.effect != .none {
            IslandEffectBadge(effect: scene.effect, size: 20)
                .id(scene.effect)
        } else if scene.isWalking {
            // Fresh paw prints where he just walked by.
            HStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { i in
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(scene.facingLeft ? -90 : 90))
                        .offset(y: i == 0 ? -3 : 3)
                }
            }
            .foregroundStyle(Color.white.opacity(0.35))
        } else {
            Image(systemName: mood.symbolName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MurzikPalette.accent(for: mood))
                .accessibilityLabel(Text(Strings.moodTitle(mood)))
        }
    }
}

struct CompactLeadingView: View {
    var state: MurzikAttributes.ContentState
    var mood: MurzikMood

    var body: some View {
        CompactSideView(side: .leading, state: state, mood: mood)
    }
}

struct CompactTrailingView: View {
    var state: MurzikAttributes.ContentState
    var mood: MurzikMood

    var body: some View {
        CompactSideView(side: .trailing, state: state, mood: mood)
    }
}

struct MinimalView: View {
    var state: MurzikAttributes.ContentState
    var mood: MurzikMood

    var body: some View {
        IslandCatPose(scene: state.scene, mood: mood, size: 26)
            .animation(beatAnimation, value: state.scene.step)
    }
}

// MARK: Expanded

struct ExpandedLeadingView: View {
    var mood: MurzikMood

    var body: some View {
        Image(systemName: mood.symbolName)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(MurzikPalette.accent(for: mood))
            .frame(width: 38, height: 38)
            .background(Circle().fill(MurzikPalette.accent(for: mood).opacity(0.18)))
            .contentTransition(.symbolEffect(.replace))
            .padding(.horizontal, 4)
            .accessibilityLabel(Text(Strings.moodTitle(mood)))
    }
}

struct ExpandedTrailingView: View {
    var state: MurzikAttributes.ContentState
    var isStale: Bool

    var body: some View {
        HungerLabel(state: state, isStale: isStale)
            .frame(height: 38)
            .padding(.horizontal, 4)
    }
}

struct ExpandedCenterView: View {
    var name: String
    var mood: MurzikMood

    var body: some View {
        VStack(spacing: 1) {
            Text(name)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(Strings.moodMessage(mood))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// The stage (ground line, bowl, cushion, Murzik walking) and the controls under it.
struct ExpandedBottomView: View {
    var state: MurzikAttributes.ContentState
    var isStale: Bool

    var body: some View {
        let mood = state.displayMood(isStale: isStale)
        VStack(spacing: 6) {
            IslandSceneView(state: state, mood: mood, isStale: isStale, catSize: 46)
                .frame(height: 56)
            ControlsRow(state: state, isStale: isStale, compactButtons: false)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

// MARK: Lock Screen

struct LockScreenView: View {
    var name: String
    var state: MurzikAttributes.ContentState
    var isStale: Bool

    var body: some View {
        let mood = state.displayMood(isStale: isStale)
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Image(systemName: mood.symbolName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MurzikPalette.accent(for: mood))
                Text(Strings.moodMessage(mood))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                HungerLabel(state: state, isStale: isStale)
            }
            .environment(\.layoutDirection, .rightToLeft)
            IslandSceneView(state: state, mood: mood, isStale: isStale, catSize: 44)
                .frame(height: 52)
            ControlsRow(state: state, isStale: isStale, compactButtons: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: Stage

/// A little stage: a ground line with the bowl on the left and the cushion on the right, a
/// real-time paw-print trail, and full-body Murzik at his position, animated between updates.
struct IslandSceneView: View {
    var state: MurzikAttributes.ContentState
    var mood: MurzikMood
    var isStale: Bool
    var catSize: CGFloat = 46

    var body: some View {
        let scene = state.scene
        let hungry = isStale ? !state.sleepsThroughHunger : state.fullness < PersonalityEngine.hungryThreshold
        let trail = state.showsHungerCountdown(isStale: isStale) ? scene.trailRange : nil
        GeometryReader { geo in
            let w = geo.size.width
            let ground = geo.size.height - 2
            let inset = catSize * 0.5
            let x = inset + (w - 2 * inset) * CGFloat(min(1, max(0, scene.position)))
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.05), .white.opacity(0.3), .white.opacity(0.3), .white.opacity(0.05)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: w, height: 1.5)
                    .position(x: w / 2, y: ground)
                IslandPawTrail(range: trail, hungry: hungry)
                    .frame(width: max(0, w - 76), height: 12)
                    .position(x: w / 2, y: ground - 9)
                IslandFoodBowl(hungry: hungry)
                    .position(x: 13, y: ground - 9)
                IslandCushion()
                    .position(x: w - 15, y: ground - 4)
                ZStack {
                    IslandCatPose(scene: scene, mood: mood, size: catSize)
                    if scene.effect != .none {
                        IslandEffectBadge(effect: scene.effect, size: catSize * 0.42)
                            .offset(y: -catSize * 0.62)
                            .id(scene.effect)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    } else if mood == .sleeping {
                        Image(systemName: "zzz")
                            .font(.system(size: catSize * 0.26, weight: .bold))
                            .foregroundStyle(MurzikPalette.sky)
                            .offset(x: catSize * 0.4, y: -catSize * 0.45)
                            .transition(.opacity)
                    }
                }
                .frame(width: catSize, height: catSize)
                .position(x: x, y: ground - catSize / 2 + 1)
            }
            .animation(beatAnimation, value: scene.step)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// Feed (left, under the bowl) · needs meters · Pet (right, under the cushion).
struct ControlsRow: View {
    var state: MurzikAttributes.ContentState
    var isStale: Bool
    var compactButtons: Bool

    var body: some View {
        HStack(spacing: 8) {
            IslandActionButton(intent: FeedMurzikIntent(), action: .feed, tint: MurzikPalette.amber, compact: compactButtons)
            NeedsRow(state: state, isStale: isStale)
                .environment(\.layoutDirection, .rightToLeft)
            IslandActionButton(intent: PetMurzikIntent(), action: .pet, tint: MurzikPalette.heart, compact: compactButtons)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: Building blocks

struct NeedsRow: View {
    var state: MurzikAttributes.ContentState
    var isStale: Bool

    var body: some View {
        HStack(spacing: 8) {
            MiniMeter(symbol: "fish.fill", value: isStale ? min(state.fullness, PersonalityEngine.hungryThreshold) : state.fullness, tint: MurzikPalette.amber)
            MiniMeter(symbol: "bolt.fill", value: state.energy, tint: MurzikPalette.sky)
            MiniMeter(symbol: "heart.fill", value: state.happiness, tint: MurzikPalette.heart)
        }
    }
}

struct MiniMeter: View {
    var symbol: String
    var value: Double
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(tint)
                        .frame(width: max(geo.size.height, geo.size.width * PersonalityEngine.clamp(value)))
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HungerLabel: View {
    var state: MurzikAttributes.ContentState
    var isStale: Bool

    var body: some View {
        let now = Date.now
        if state.showsHungerCountdown(isStale: isStale, now: now) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 10, weight: .bold))
                Text(timerInterval: now...state.hungryAt, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 62)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .accessibilityLabel(Text(Strings.hungryIn))
        } else if !state.sleepsThroughHunger {
            Text(Strings.hungryNow)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(MurzikPalette.amber)
        }
    }
}

struct IslandActionButton<I: AppIntent>: View {
    var intent: I
    var action: PetAction
    var tint: Color
    var compact = false

    var body: some View {
        Button(intent: intent) {
            Group {
                if compact {
                    Image(systemName: action.symbolName)
                        .frame(width: 40, height: 30)
                } else {
                    Label(Strings.actionTitle(action), systemImage: action.symbolName)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.2)))
            .environment(\.layoutDirection, .rightToLeft)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Strings.actionTitle(action)))
    }
}
