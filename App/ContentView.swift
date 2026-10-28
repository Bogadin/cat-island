import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: PetModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var blink = false
    @State private var bounce: CGFloat = 1
    @State private var particles: [Particle] = []

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let mood = model.mood
        ZStack {
            LinearGradient(colors: [MurzikPalette.cream, MurzikPalette.sand], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header(mood: mood)
                    stage(mood: mood)
                    NeedsCard(state: model.state)
                    actions
                    IslandCard()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .onReceive(clock) { _ in model.tick() }
        .task { await blinkLoop() }
        .sensoryFeedback(.impact(weight: .light), trigger: model.lastAction?.date)
    }

    // MARK: Header

    private func header(mood: MurzikMood) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Strings.name)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(MurzikPalette.ink)
            Spacer()
            MoodChip(mood: mood)
        }
        .padding(.top, 8)
    }

    // MARK: Stage

    private func stage(mood: MurzikMood) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white, Color.white.opacity(0)], center: .center, startRadius: 10, endRadius: 170))
                .frame(width: 320, height: 320)

            Ellipse()
                .fill(MurzikPalette.ink.opacity(0.13))
                .frame(width: 150, height: 18)
                .blur(radius: 4)
                .offset(y: 122)

            animatedCat(mood: mood)
                .frame(width: 190, height: 250)
                .scaleEffect(bounce, anchor: .bottom)
                .contentShape(Rectangle())
                .onTapGesture { perform(.pet) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text(Strings.tapToPet))

            ForEach(particles) { particle in
                FloatingSymbol(particle: particle)
            }

            SpeechBubble(text: Strings.moodMessage(mood))
                .id(mood)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .offset(y: -150)
        }
        .frame(height: 340)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: mood)
    }

    @ViewBuilder
    private func animatedCat(mood: MurzikMood) -> some View {
        if reduceMotion {
            CatFigure(mood: mood, eyesClosed: blink)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let sleeping = mood == .sleeping
                let excited = mood == .excited || mood == .playful
                CatFigure(
                    mood: mood,
                    eyesClosed: blink,
                    tailAngle: sin(t * (sleeping ? 0.7 : (excited ? 4.0 : 2.0))) * (sleeping ? 3 : (excited ? 14 : 8)),
                    breath: 1 + CGFloat(sin(t * (sleeping ? 1.4 : 2.4))) * (sleeping ? 0.018 : 0.010)
                )
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 12) {
            ActionButton(action: .pet, tint: MurzikPalette.heart) { perform(.pet) }
            ActionButton(action: .feed, tint: MurzikPalette.amber) { perform(.feed) }
            ActionButton(action: .play, tint: MurzikPalette.mint) { perform(.play) }
            if model.state.isSleeping {
                ActionButton(action: .wake, tint: Color(red: 0.98, green: 0.72, blue: 0.20)) { perform(.wake) }
            } else {
                ActionButton(action: .sleep, tint: MurzikPalette.sky) { perform(.sleep) }
            }
        }
    }

    private func perform(_ action: PetAction) {
        model.perform(action)
        spawnParticles(for: action)
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { bounce = 1.07 }
        Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { bounce = 1 }
        }
    }

    private func spawnParticles(for action: PetAction) {
        let (symbol, color): (String, Color) = {
            switch action {
            case .pet: return ("heart.fill", MurzikPalette.heart)
            case .feed: return ("fish.fill", MurzikPalette.amber)
            case .play: return ("sparkle", MurzikPalette.mint)
            case .sleep: return ("moon.zzz.fill", MurzikPalette.sky)
            case .wake: return ("sun.max.fill", MurzikPalette.amber)
            }
        }()
        let burst = (0..<6).map { index in
            Particle(
                symbol: symbol,
                color: color,
                x: CGFloat.random(in: -90...90),
                delay: Double(index) * 0.07,
                size: CGFloat.random(in: 16...26)
            )
        }
        particles.append(contentsOf: burst)
        let ids = Set(burst.map(\.id))
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            particles.removeAll { ids.contains($0.id) }
        }
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2.5...5.5) * 1_000_000_000))
            blink = true
            try? await Task.sleep(nanoseconds: 140_000_000)
            blink = false
        }
    }
}

// MARK: - Components

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

    var body: some View {
        Image(systemName: particle.symbol)
            .font(.system(size: particle.size, weight: .bold))
            .foregroundStyle(particle.color)
            .scaleEffect(flying ? 1.15 : 0.5)
            .opacity(flying ? 0 : 1)
            .offset(x: particle.x, y: flying ? -170 : -30)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 1.5).delay(particle.delay)) { flying = true }
            }
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(MurzikPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: MurzikPalette.ink.opacity(0.10), radius: 10, y: 4)
            )
    }
}

struct MoodChip: View {
    let mood: MurzikMood

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mood.symbolName)
                .foregroundStyle(MurzikPalette.accent(for: mood))
            Text(Strings.moodTitle(mood))
                .foregroundStyle(MurzikPalette.ink)
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.85)))
        .contentTransition(.opacity)
    }
}

struct ActionButton: View {
    let action: PetAction
    let tint: Color
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            VStack(spacing: 8) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(tint.gradient))
                    .shadow(color: tint.opacity(0.35), radius: 8, y: 4)
                Text(Strings.actionTitle(action))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MurzikPalette.ink)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("action.\(action.rawValue)")
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct NeedsCard: View {
    let state: PetState

    var body: some View {
        VStack(spacing: 12) {
            NeedBar(symbol: "fish.fill", title: Strings.fullness, value: state.fullness, tint: MurzikPalette.amber)
            NeedBar(symbol: "bolt.fill", title: Strings.energy, value: state.energy, tint: MurzikPalette.sky)
            NeedBar(symbol: "heart.fill", title: Strings.happiness, value: state.happiness, tint: MurzikPalette.heart)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.8)))
    }
}

struct NeedBar: View {
    let symbol: String
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MurzikPalette.ink)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))
                    Capsule().fill(tint.gradient)
                        .frame(width: max(geo.size.height, geo.size.width * PersonalityEngine.clamp(value)))
                }
            }
            .frame(height: 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(Int((PersonalityEngine.clamp(value) * 100).rounded()))%"))
    }
}

struct IslandCard: View {
    @EnvironmentObject private var model: PetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IslandPreview(mood: model.mood)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.islandTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(MurzikPalette.ink)
                    statusText
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MurzikPalette.inkSoft)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { model.islandEnabled },
                    set: { model.setIslandEnabled($0) }
                ))
                .labelsHidden()
                .tint(MurzikPalette.amber)
            }
            Text(Strings.islandRestartNote)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(MurzikPalette.inkSoft)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.8)))
    }

    @ViewBuilder
    private var statusText: some View {
        switch model.islandStatus {
        case let .running(endsAt):
            if let endsAt, endsAt > model.now {
                HStack(spacing: 4) {
                    Text(Strings.islandEndsIn)
                    Text(timerInterval: model.now...endsAt, countsDown: true)
                        .monospacedDigit()
                }
            } else {
                Text(Strings.islandOn)
            }
        case .off:
            Text(Strings.islandOff)
        case .disabledBySystem:
            Text(Strings.islandDisabledBySystem)
        case .failed:
            Text(Strings.islandStartFailed)
        }
    }
}

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
    }
}
