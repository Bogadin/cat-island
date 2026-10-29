import SwiftUI

/// The main screen: Murzik's room with the big 3D stage, his speech bubble, the love strip and the action dock.
struct ContentView: View {
    @EnvironmentObject private var model: PetModel
    @StateObject private var director = StageDirector()
    @AppStorage(ExperienceSettings.showNameKey) private var showName = true
    @AppStorage(ExperienceSettings.hapticsKey) private var hapticsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSettings = false
    @State private var stageFrame: CGRect = .zero
    @State private var bounce: CGFloat = 1
    @GestureState private var touching = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let mood = model.mood
        let phase = model.dayPhase
        let theme = RoomTheme.for(phase)

        ZStack {
            RoomBackdrop(phase: phase, stageFrame: stageFrame, animated: !reduceMotion)
                .ignoresSafeArea()
                .transition(.opacity)
                .id(phase)

            VStack(spacing: 12) {
                topBar(mood: mood, phase: phase, theme: theme)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                stage(mood: mood)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: StageFrameKey.self, value: geo.frame(in: .global))
                        }
                    )

                bondStrip(theme: theme)
                    .padding(.horizontal, 16)

                Group {
                    if director.toyMode {
                        toyDock(theme: theme)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        actionDock(theme: theme)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 6)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: director.toyMode)
        }
        .overlay(alignment: .top) {
            momentOverlay
                .padding(.horizontal, 18)
                .padding(.top, 74)
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: model.greeting)
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: model.surprise)
        }
        .animation(.easeInOut(duration: 1.2), value: phase)
        .onPreferenceChange(StageFrameKey.self) { frame in
            stageFrame = frame
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .onReceive(clock) { _ in model.tick() }
        .onAppear { director.attach(model) }
        .onChange(of: mood) { _, newMood in director.syncMood(newMood) }
        .onChange(of: director.pulse) { _, _ in bounceStage() }
        .onChange(of: model.surprise) { _, moment in
            if case .gift = moment { director.burst(symbol: "gift.fill", color: MurzikPalette.mint, count: 4, spread: 90) }
        }
        .sensoryFeedback(trigger: model.lastAction?.date) { _, _ in
            hapticsEnabled ? .impact(weight: .light) : nil
        }
    }

    // MARK: Top bar

    private func topBar(mood: MurzikMood, phase: DayPhase, theme: RoomTheme) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                if showName {
                    Text(Strings.name)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                Label(Strings.phaseTitle(phase), systemImage: phaseSymbol(phase))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer(minLength: 8)
            MoodChip(mood: mood)
            RoundIconButton(symbol: "gearshape.fill", label: Strings.settingsOpen, identifier: "settings.open") {
                showSettings = true
            }
            .overlay(alignment: .topTrailing) {
                if islandNeedsAttention {
                    Circle()
                        .fill(MurzikPalette.heart)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .offset(x: 1, y: -1)
                        .accessibilityHidden(true)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: mood)
    }

    private var islandNeedsAttention: Bool {
        guard model.islandEnabled else { return false }
        switch model.islandStatus {
        case .disabledBySystem, .failed: return true
        default: return false
        }
    }

    private func phaseSymbol(_ phase: DayPhase) -> String {
        switch phase {
        case .morning: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    // MARK: Stage

    private func stage(mood: MurzikMood) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let catWidth = min(size.width * 0.8, 330)
            let catHeight = size.height * 0.8
            ZStack {
                if director.isPurring {
                    PurrRings()
                        .frame(width: min(size.width * 0.95, 400), height: min(size.width * 0.95, 400))
                        .position(x: size.width / 2, y: size.height * 0.6)
                        .transition(.opacity)
                }

                Murzik3DView(controller: director.cat)
                    .frame(width: catWidth, height: catHeight)
                    .scaleEffect(bounce, anchor: .bottom)
                    .position(x: size.width / 2, y: size.height - catHeight / 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(Strings.catLabel), \(Strings.moodTitle(mood))"))
                    .accessibilityValue(Text(Strings.moodMessage(mood)))
                    .accessibilityHint(Text(Strings.tapToPet))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { director.pet() }
                    .accessibilityIdentifier("stage.cat")

                ForEach(director.bursts) { particle in
                    FloatingSymbol(particle: particle)
                        .position(x: size.width / 2, y: size.height * 0.42)
                }

                if let bubble = bubble(mood: mood) {
                    SpeechBubble(text: bubble.text, symbol: bubble.symbol, tint: bubble.tint)
                        .frame(maxWidth: size.width - 48)
                        .id(bubble.text)
                        .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                        .position(x: size.width / 2, y: max(34, size.height - catHeight - 4))
                        .allowsHitTesting(false)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                if director.toyMode {
                    ToyLayer(director: director)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(touchGesture(size: size), including: director.toyMode ? .subviews : .all)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: bubble(mood: mood)?.text)
            .animation(.easeInOut(duration: 0.35), value: director.isPurring)
        }
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: touching) { _, isTouching in
            if !isTouching { director.touchEnded() }
        }
    }

    private func touchGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                let point = CGPoint(x: value.location.x / max(size.width, 1), y: value.location.y / max(size.height, 1))
                director.touchChanged(at: point, translation: value.translation)
            }
            .onEnded { _ in director.touchEnded() }
    }

    private struct Bubble {
        var text: String
        var symbol: String?
        var tint: Color
    }

    private func bubble(mood: MurzikMood) -> Bubble? {
        if model.greeting != nil || model.surprise != nil { return nil }
        if director.toyMode {
            if let caught = director.caughtAt, model.now.timeIntervalSince(caught) < 1.6 {
                return Bubble(text: Strings.toyCaught, symbol: "sparkles", tint: MurzikPalette.amber)
            }
            return nil
        }
        if director.isPurring {
            return Bubble(text: Strings.purring, symbol: "heart.fill", tint: MurzikPalette.heart)
        }
        if model.isBedtime, mood == .sleepy || mood == .idle || mood == .happy {
            return Bubble(text: Strings.bedtimeMessage, symbol: "moon.stars.fill", tint: MurzikPalette.sky)
        }
        return Bubble(text: Strings.moodMessage(mood), symbol: mood.symbolName, tint: MurzikPalette.accent(for: mood))
    }

    private func bounceStage() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { bounce = 1.04 }
        Task {
            try? await Task.sleep(nanoseconds: 170_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { bounce = 1 }
        }
    }

    // MARK: Love strip

    private func bondStrip(theme: RoomTheme) -> some View {
        HStack(spacing: 8) {
            BondPill(symbol: "heart.fill", value: "\(model.loveToday)", label: Strings.loveToday,
                     tint: MurzikPalette.heart, theme: theme)
            BondPill(symbol: "flame.fill", value: "\(model.streak)", label: Strings.streak,
                     tint: MurzikPalette.amber, theme: theme)
            BondPill(symbol: "gift.fill", value: "\(model.bond.giftsReceived)", label: Strings.gifts,
                     tint: MurzikPalette.mint, theme: theme)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.loveToday)
    }

    // MARK: Docks

    private func dockBackground(_ theme: RoomTheme) -> some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(theme.card)
            .shadow(color: MurzikPalette.ink.opacity(theme.isDark ? 0.3 : 0.1), radius: 18, y: 8)
    }

    private func actionDock(theme: RoomTheme) -> some View {
        let state = model.state
        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                NeedGauge(symbol: "fish.fill", title: Strings.fullness, value: state.fullness, tint: MurzikPalette.amber)
                NeedGauge(symbol: "bolt.fill", title: Strings.energy, value: state.energy, tint: MurzikPalette.sky)
                NeedGauge(symbol: "heart.fill", title: Strings.happiness, value: state.happiness, tint: MurzikPalette.heart)
            }
            HStack(spacing: 4) {
                ActionButton(action: .pet, tint: MurzikPalette.heart) { director.perform(.pet) }
                ActionButton(action: .feed, tint: MurzikPalette.amber,
                             highlighted: state.fullness < PersonalityEngine.hungryThreshold) { director.perform(.feed) }
                ActionButton(action: .play, tint: MurzikPalette.mint) { director.perform(.play) }
                if state.isSleeping {
                    ActionButton(action: .wake, tint: Color(red: 0.98, green: 0.72, blue: 0.20)) { director.perform(.wake) }
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ActionButton(action: .sleep, tint: MurzikPalette.sky, highlighted: model.isBedtime) { director.perform(.sleep) }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: state.isSleeping)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(dockBackground(theme))
    }

    private func toyDock(theme: RoomTheme) -> some View {
        VStack(spacing: 14) {
            Label(Strings.toyHint, systemImage: "hand.draw.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MurzikPalette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                ForEach(ToyKind.allCases) { kind in
                    let selected = director.toyKind == kind
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { director.toyKind = kind }
                    } label: {
                        Label(kind.title, systemImage: kind.symbolName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? .white : MurzikPalette.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(selected ? AnyShapeStyle(MurzikPalette.mint.gradient) : AnyShapeStyle(MurzikPalette.cream)))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("toy.\(kind.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Button {
                    director.exitToyMode()
                } label: {
                    Text(Strings.toyDone)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(MurzikPalette.ink))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("toy.done")
            }
        }
        .padding(18)
        .background(dockBackground(theme))
    }

    // MARK: Moments

    @ViewBuilder
    private var momentOverlay: some View {
        if let greeting = model.greeting {
            MomentCard(
                symbol: Strings.greetingSymbol(greeting),
                tint: MurzikPalette.heart,
                title: Strings.greetingTitle(greeting),
                subtitle: Strings.greetingSubtitle(greeting)
            ) { EmptyView() }
            .accessibilityIdentifier("moment.greeting")
            .onTapGesture { model.dismissGreeting() }
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: greeting) {
                try? await Task.sleep(nanoseconds: 6_500_000_000)
                guard !Task.isCancelled else { return }
                model.dismissGreeting()
            }
        } else if let surprise = model.surprise {
            surpriseCard(surprise)
                .accessibilityIdentifier("moment.surprise")
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: surprise) {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled else { return }
                    model.dismissSurprise()
                }
        }
    }

    @ViewBuilder
    private func surpriseCard(_ surprise: Surprise) -> some View {
        switch surprise {
        case let .gift(gift):
            MomentCard(symbol: gift.symbolName, tint: MurzikPalette.mint, title: Strings.giftTitle, subtitle: Strings.giftName(gift)) {
                thanksButton
            }
        case let .message(index):
            MomentCard(symbol: "heart.text.square.fill", tint: MurzikPalette.heart, title: Strings.surpriseTitle,
                       subtitle: Strings.surpriseMessage(index)) {
                thanksButton
            }
        }
    }

    private var thanksButton: some View {
        Button {
            model.dismissSurprise()
            director.burst(symbol: "heart.fill", color: MurzikPalette.heart, count: 5, spread: 90)
        } label: {
            Text(Strings.thanks)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(MurzikPalette.heart.gradient))
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 6)
        .accessibilityIdentifier("surprise.thanks")
    }
}

private struct StageFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
