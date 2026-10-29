import SwiftUI

// MARK: - Particles

struct Particle: Identifiable {
    let id = UUID()
    let symbol: String
    let color: Color
    let x: CGFloat
    let delay: Double
    let size: CGFloat
}

struct FloatingSymbol: View {
    let particle: Particle
    @State private var flying = false

    init(particle: Particle) {
        self.particle = particle
    }

    var body: some View {
        Image(systemName: particle.symbol)
            .font(.system(size: particle.size, weight: .bold))
            .foregroundStyle(particle.color)
            .shadow(color: particle.color.opacity(0.35), radius: 4)
            .scaleEffect(flying ? 1.15 : 0.5)
            .opacity(flying ? 0 : 1)
            .offset(x: particle.x, y: flying ? -170 : -20)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).delay(particle.delay)) { flying = true }
            }
    }
}

// MARK: - Speech bubble

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.midX - rect.width * 0.1, y: rect.minY + rect.height * 0.5))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX + rect.width * 0.2, y: rect.minY + rect.height * 0.4))
        p.closeSubpath()
        return p
    }
}

struct SpeechBubble: View {
    let text: String
    var symbol: String?
    var tint: Color = MurzikPalette.amber

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(MurzikPalette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .overlay(alignment: .bottom) {
                    BubbleTail().fill(Color.white).frame(width: 22, height: 12).offset(y: 11)
                }
                .shadow(color: MurzikPalette.ink.opacity(0.12), radius: 12, y: 5)
        )
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - Chips & buttons

struct MoodChip: View {
    let mood: MurzikMood

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mood.symbolName)
                .foregroundStyle(MurzikPalette.accent(for: mood))
                .contentTransition(.symbolEffect(.replace))
            Text(Strings.moodTitle(mood))
                .foregroundStyle(MurzikPalette.ink)
                .contentTransition(.opacity)
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.white.opacity(0.9)))
        .shadow(color: MurzikPalette.ink.opacity(0.08), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mood.chip")
    }
}

struct RoundIconButton: View {
    let symbol: String
    let label: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(MurzikPalette.ink)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.white.opacity(0.9)))
                .shadow(color: MurzikPalette.ink.opacity(0.08), radius: 6, y: 3)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier ?? "")
    }
}

struct ActionButton: View {
    let action: PetAction
    let tint: Color
    var highlighted = false
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            VStack(spacing: 7) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(tint.gradient))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: tint.opacity(0.4), radius: 8, y: 4)
                    .overlay(alignment: .topTrailing) {
                        if highlighted {
                            Circle().fill(MurzikPalette.heart).frame(width: 13, height: 13)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                .offset(x: 2, y: -2)
                        }
                    }
                Text(Strings.actionTitle(action))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MurzikPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("action.\(action.rawValue)")
        .accessibilityLabel(Text(Strings.actionTitle(action)))
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Needs

struct NeedGauge: View {
    let symbol: String
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MurzikPalette.inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.16))
                    Capsule().fill(tint.gradient)
                        .frame(width: max(geo.size.height, geo.size.width * PersonalityEngine.clamp(value)))
                }
            }
            .frame(height: 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(Int((PersonalityEngine.clamp(value) * 100).rounded()))%"))
    }
}

// MARK: - Bond

struct BondPill: View {
    let symbol: String
    let value: String
    let label: String
    let tint: Color
    let theme: RoomTheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(MurzikPalette.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(MurzikPalette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(theme.card))
        .shadow(color: MurzikPalette.ink.opacity(0.07), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Moment cards

/// A floating card for greetings and surprises.
struct MomentCard<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let accessory: Accessory
    @State private var glow = false

    init(symbol: String, tint: Color, title: String, subtitle: String, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 58, height: 58)
                    .scaleEffect(glow ? 1.12 : 0.95)
                Circle().fill(tint.gradient).frame(width: 46, height: 46)
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(MurzikPalette.ink)
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(MurzikPalette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.96))
                .shadow(color: MurzikPalette.ink.opacity(0.16), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Island preview

/// A tiny replica of the compact Dynamic Island.
struct IslandPreview: View {
    let mood: MurzikMood

    var body: some View {
        HStack(spacing: 0) {
            CatFace(mood: mood, detail: .compact)
                .frame(width: 20, height: 20)
            Spacer(minLength: 0)
            Image(systemName: mood.symbolName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MurzikPalette.accent(for: mood))
        }
        .padding(.horizontal, 7)
        .frame(width: 76, height: 26)
        .background(Capsule().fill(Color.black))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}
