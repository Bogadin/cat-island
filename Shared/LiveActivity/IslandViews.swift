import AppIntents
import SwiftUI

// Presentation views for the Live Activity. They live in Shared (and take plain values,
// not an ActivityViewContext) so the app's tests can render them to images.

// MARK: Compact & minimal

struct CompactLeadingView: View {
    var mood: MurzikMood

    var body: some View {
        CatFace(mood: mood, detail: .compact)
            .frame(width: 30, height: 30)
            .padding(.leading, 2)
    }
}

struct CompactTrailingView: View {
    var mood: MurzikMood

    var body: some View {
        Image(systemName: mood.symbolName)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(MurzikPalette.accent(for: mood))
            .frame(minWidth: 24)
            .padding(.trailing, 2)
            .accessibilityLabel(Text(Strings.moodTitle(mood)))
    }
}

struct MinimalView: View {
    var mood: MurzikMood

    var body: some View {
        CatFace(mood: mood, detail: .compact)
            .frame(width: 26, height: 26)
    }
}

// MARK: Expanded

struct ExpandedLeadingView: View {
    var mood: MurzikMood

    var body: some View {
        CatFace(mood: mood)
            .frame(width: 62, height: 62)
            .padding(.leading, 4)
    }
}

struct ExpandedTrailingView: View {
    var mood: MurzikMood

    var body: some View {
        Image(systemName: mood.symbolName)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(MurzikPalette.accent(for: mood))
            .frame(width: 40, height: 40)
            .background(Circle().fill(MurzikPalette.accent(for: mood).opacity(0.18)))
            .padding(.trailing, 4)
    }
}

struct ExpandedCenterView: View {
    var name: String
    var mood: MurzikMood

    var body: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(Strings.moodMessage(mood))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct ExpandedBottomView: View {
    var state: MurzikAttributes.ContentState
    var isStale: Bool

    var body: some View {
        VStack(spacing: 10) {
            NeedsRow(state: state, isStale: isStale)
            HStack(spacing: 8) {
                HungerLabel(state: state, isStale: isStale)
                Spacer(minLength: 4)
                IslandActionButton(intent: PetMurzikIntent(), action: .pet, tint: MurzikPalette.heart)
                IslandActionButton(intent: FeedMurzikIntent(), action: .feed, tint: MurzikPalette.amber)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: Lock Screen

struct LockScreenView: View {
    var name: String
    var state: MurzikAttributes.ContentState
    var isStale: Bool

    var body: some View {
        let mood = state.displayMood(isStale: isStale)
        HStack(alignment: .center, spacing: 14) {
            CatFace(mood: mood)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Image(systemName: mood.symbolName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MurzikPalette.accent(for: mood))
                    Spacer(minLength: 0)
                    HungerLabel(state: state, isStale: isStale)
                }
                Text(Strings.moodMessage(mood))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    NeedsRow(state: state, isStale: isStale)
                    IslandActionButton(intent: PetMurzikIntent(), action: .pet, tint: MurzikPalette.heart, compact: true)
                    IslandActionButton(intent: FeedMurzikIntent(), action: .feed, tint: MurzikPalette.amber, compact: true)
                }
            }
            .foregroundStyle(.white)
        }
        .padding(16)
        .environment(\.layoutDirection, .rightToLeft)
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
                        .frame(width: 34, height: 30)
                } else {
                    Label(Strings.actionTitle(action), systemImage: action.symbolName)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Strings.actionTitle(action)))
    }
}
