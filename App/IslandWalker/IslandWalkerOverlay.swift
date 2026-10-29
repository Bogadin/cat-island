import SwiftUI
import UIKit

/// Settings for the in-app island walker.
enum IslandWalkerSettings {
    /// `@AppStorage(IslandWalkerSettings.enabledKey) var walkerEnabled = true` — bind a Toggle to it.
    static let enabledKey = "murzik.walker.enabled"
}

/// Murzik walking around the real Dynamic Island while the app is open.
///
/// Add once on the root view: `ContentView().overlay { IslandWalkerOverlay() }`. Needs `PetModel`
/// in the environment. Only the cat itself receives touches; everything else passes through.
struct IslandWalkerOverlay: View {
    @AppStorage(IslandWalkerSettings.enabledKey) private var enabled = true

    var body: some View {
        if enabled {
            IslandWalkerStage()
        }
    }
}

/// Reads the window's top safe-area inset (the overlay itself ignores the safe area).
enum WalkerScreen {
    @MainActor
    static func safeTop() -> CGFloat {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        return window?.safeAreaInsets.top ?? 0
    }

    @MainActor
    static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
}

private struct IslandWalkerStage: View {
    @EnvironmentObject private var model: PetModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var simulation = WalkerSimulation(seed: IslandWalkerStage.launchSeed)
    @State private var safeTop: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let geo = IslandGeometry(screen: proxy.size, safeTop: safeTop, isPhone: WalkerScreen.isPhone)
            Group {
                if safeTop <= 0 {
                    Color.clear.allowsHitTesting(false)
                } else if reduceMotion {
                    StaticWalker(geometry: geo, mood: model.mood) { model.perform(.pet) }
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active)) { context in
                        let snapshot = simulation.advance(to: context.date, mood: model.mood, geometry: geo)
                        WalkerScene(
                            snapshot: snapshot,
                            geometry: geo,
                            touchable: simulation.isTouchable,
                            onTap: {
                                simulation.pet()
                                model.perform(.pet)
                            },
                            onDrag: { simulation.drag(to: $0) },
                            onDrop: { simulation.release() }
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            safeTop = WalkerScreen.safeTop()
            simulation.forcedMood = Self.forcedMood
            #if DEBUG
            let hold = UserDefaults.standard.double(forKey: "walker-reaction-hold")
            if hold > 0 { simulation.reactionHold = hold }
            #endif
        }
        .onChange(of: scenePhase) { _, _ in
            safeTop = WalkerScreen.safeTop()
        }
        .task {
            // The key window may not be ready on the very first frame.
            try? await Task.sleep(nanoseconds: 300_000_000)
            safeTop = WalkerScreen.safeTop()
        }
    }

    /// UI tests: `-walker-mood <mood>` and `-walker-seed <n>` launch arguments.
    private static var forcedMood: MurzikMood? {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "walker-mood") { return MurzikMood(rawValue: raw) }
        #endif
        return nil
    }

    private static var launchSeed: UInt64 {
        #if DEBUG
        let seed = UserDefaults.standard.integer(forKey: "walker-seed")
        if seed > 0 { return UInt64(seed) }
        #endif
        return UInt64(Date().timeIntervalSince1970)
    }
}

/// One frame of the walker: cat, island occluder, butterfly, bubbles and hearts.
private struct WalkerScene: View {
    let snapshot: WalkerSimulation.Snapshot
    let geometry: IslandGeometry
    let touchable: Bool
    let onTap: () -> Void
    let onDrag: (CGPoint) -> Void
    let onDrop: () -> Void

    private var box: CGFloat { IslandGeometry.catBox }

    var body: some View {
        let frame = snapshot.frame
        let center = frame.boxCenter(size: box)
        ZStack(alignment: .topLeading) {
            if frame.pose != .hidden {
                shadow(for: frame)
            }

            WalkerCatView(frame: frame, mood: snapshot.mood, time: snapshot.time, size: box)
                .padding(8)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
                        .onChanged { value in
                            // Hold him by the scruff: the finger is at his shoulders.
                            onDrag(CGPoint(x: value.location.x, y: value.location.y + box * 0.55))
                        }
                        .onEnded { _ in onDrop() }
                )
                .allowsHitTesting(touchable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Strings.name))
                .accessibilityHint(Text(Strings.tapToPet))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("walker.cat")
                .accessibilityAction { onTap() }
                .position(center)

            if geometry.hasIsland {
                // Drawn exactly under the hardware island, so on a device it is invisible; it hides
                // Murzik when he slips "inside" (and shows the island in simulator screenshots).
                Capsule()
                    .fill(Color.black)
                    .frame(width: geometry.pill.width - 1, height: geometry.pill.height - 1)
                    .position(x: geometry.pill.midX, y: geometry.pill.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if let butterfly = snapshot.butterfly {
                WalkerButterflyView(time: snapshot.time)
                    .opacity(snapshot.butterflyAlpha)
                    .position(butterfly)
                    .allowsHitTesting(false)
            }

            decorations(for: frame)
                .allowsHitTesting(false)
        }
        .frame(width: geometry.screen.width, height: geometry.screen.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
    }

    static let space = "murzik.walker"

    @ViewBuilder
    private func shadow(for frame: WalkerFrame) -> some View {
        // Soft contact shadow on the floor he is above (not while hanging or on the status-bar line).
        let floorY = geometry.underFloorY
        if !frame.upsideDown, frame.feet.y <= floorY + 1, frame.feet.y > geometry.pill.maxY + 2 {
            let height = max(0, floorY - frame.feet.y)
            let k = max(0.3, 1 - height / 60)
            Ellipse()
                .fill(MurzikPalette.ink.opacity(0.16 * k))
                .frame(width: box * 0.62 * k, height: 5 * k)
                .blur(radius: 1.5)
                .position(x: frame.feet.x, y: floorY - 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func decorations(for frame: WalkerFrame) -> some View {
        let t = snapshot.time
        ZStack(alignment: .topLeading) {
            if let bubble = frame.bubble {
                // Beside his head, on the side away from the island when he is on the status-bar line.
                let onLedge = geometry.hasIsland && frame.feet.y < geometry.pill.maxY + 6
                let toRight = onLedge ? frame.feet.x > geometry.pill.midX : frame.feet.x < geometry.screen.width - 70
                WalkerBubble(text: bubble, tailOnLeft: toRight)
                    .position(x: frame.feet.x + (toRight ? 34 : -34), y: frame.feet.y - 24)
                    .transition(.scale)
            }

            if frame.pose == .sleep {
                ForEach(0..<3, id: \.self) { i in
                    let p = (t / 2.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Text("z")
                        .font(.system(size: 9 + 4 * CGFloat(p), weight: .heavy, design: .rounded))
                        .foregroundStyle(MurzikPalette.sky)
                        .opacity(sin(.pi * p))
                        .position(
                            x: frame.feet.x - 12 - 18 * CGFloat(p) + 3 * CGFloat(sin(t * 2 + Double(i))),
                            y: frame.feet.y - 16 - 22 * CGFloat(p)
                        )
                }
            }

            if snapshot.mood == .loving, frame.pose == .sitFront || frame.pose == .sitSide {
                let p = (t / 1.8).truncatingRemainder(dividingBy: 1)
                Image(systemName: "heart.fill")
                    .font(.system(size: 8 + 3 * CGFloat(p), weight: .bold))
                    .foregroundStyle(MurzikPalette.heart)
                    .opacity(sin(.pi * p))
                    .position(x: frame.feet.x + 14, y: frame.feet.y - 30 - 16 * CGFloat(p))
            }

            ForEach(snapshot.effects) { effect in
                let age = t - effect.start
                let p = min(max(age / 1.3, 0), 1)
                Image(systemName: "heart.fill")
                    .font(.system(size: 13 + 6 * CGFloat(p), weight: .bold))
                    .foregroundStyle(MurzikPalette.heart)
                    .shadow(color: MurzikPalette.heart.opacity(0.4), radius: 3)
                    .scaleEffect(p < 0.15 ? CGFloat(p / 0.15) : 1)
                    .opacity(1 - p * p)
                    .position(
                        x: effect.origin.x + 6 * CGFloat(sin(age * 7)),
                        y: effect.origin.y - 26 * CGFloat(p)
                    )
            }
        }
        .frame(width: geometry.screen.width, height: geometry.screen.height, alignment: .topLeading)
    }
}

/// Tiny speech bubble ("מיאו").
private struct WalkerBubble: View {
    let text: String
    let tailOnLeft: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(text == WalkerPlanner.heart ? MurzikPalette.heart : MurzikPalette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: MurzikPalette.ink.opacity(0.18), radius: 3, y: 1)
            )
            .overlay(alignment: tailOnLeft ? .bottomLeading : .bottomTrailing) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .offset(x: tailOnLeft ? -3 : 3, y: 3)
            }
            .fixedSize()
    }
}

/// A small fluttering butterfly with a soft glow.
private struct WalkerButterflyView: View {
    let time: Double

    var body: some View {
        let flap = 0.25 + 0.75 * abs(sin(time * 19))
        ZStack {
            Circle()
                .fill(MurzikPalette.amber.opacity(0.25))
                .frame(width: 22, height: 22)
                .blur(radius: 4)
            HStack(spacing: 0) {
                wing.scaleEffect(x: CGFloat(flap), y: 1, anchor: .trailing)
                wing.scaleEffect(x: -CGFloat(flap), y: 1, anchor: .leading)
            }
            Capsule()
                .fill(MurzikPalette.ink)
                .frame(width: 2, height: 9)
        }
        .rotationEffect(.degrees(sin(time * 2.3) * 12))
        .accessibilityHidden(true)
    }

    private var wing: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [MurzikPalette.heart, MurzikPalette.amber],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 8, height: 11)
    }
}

/// Reduce Motion: Murzik simply sits (or sleeps) beside the island; a tap pets him.
private struct StaticWalker: View {
    let geometry: IslandGeometry
    let mood: MurzikMood
    let onPet: () -> Void
    @State var showHeart = false

    var body: some View {
        let feet = geometry.hasIsland
            ? CGPoint(x: geometry.leftLedgeX, y: geometry.ledgeY)
            : CGPoint(x: geometry.patrolRange.lowerBound, y: geometry.underFloorY)
        let pose: WalkerPose = mood == .sleeping ? .sleep : (mood == .sleepy ? .loaf : .sitFront)
        let frame = WalkerFrame(feet: feet, pose: pose)
        ZStack(alignment: .topLeading) {
            WalkerCatView(frame: frame, mood: mood, time: 0)
                .padding(8)
                .contentShape(Rectangle())
                .onTapGesture {
                    onPet()
                    showHeart = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        showHeart = false
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Strings.name))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("walker.cat")
                .position(frame.boxCenter())
            if showHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MurzikPalette.heart)
                    .position(x: feet.x + 16, y: feet.y - 34)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: geometry.screen.width, height: geometry.screen.height, alignment: .topLeading)
    }
}
