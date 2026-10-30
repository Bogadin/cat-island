import SwiftUI

enum ToyKind: String, CaseIterable, Identifiable {
    case feather
    case laser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feather: return Strings.toyFeather
        case .laser: return Strings.toyLaser
        }
    }

    var symbolName: String {
        switch self {
        case .feather: return "wand.and.rays"
        case .laser: return "light.max"
        }
    }
}

/// Orchestrates the stage: drives the 3D cat through `Murzik3DController` only, and turns touches
/// into pets, purrs (haptics + sound) and toy play.
@MainActor
final class StageDirector: ObservableObject {
    /// Where Murzik roughly is on the stage (normalized), used to tell when the toy is "caught".
    static let catCenter = CGPoint(x: 0.5, y: 0.62)

    let cat = Murzik3DController()

    @Published private(set) var isPurring = false
    @Published private(set) var toyMode = false
    @Published var toyKind: ToyKind = .feather
    /// Toy position on the stage, normalized (0...1, top-left origin).
    @Published private(set) var toyPoint = CGPoint(x: 0.72, y: 0.3)
    @Published private(set) var bursts: [Particle] = []
    /// Increments on every action, to trigger a small bounce of the stage.
    @Published private(set) var pulse = 0
    /// Short text shown when the toy is caught.
    @Published private(set) var caughtAt: Date?

    private weak var model: PetModel?
    private let haptics = PurrHaptics()
    private let sound = PurrSound()

    private var touchStart: Date?
    private var purrStart: Date?
    private var purrDelay: Task<Void, Never>?
    private var purrLoop: Task<Void, Never>?
    private var lastCatch: Date = .distantPast
    private var lastToyPlay: Date = .distantPast

    init() {
        // The room already draws its own rug; keep only the 3D contact shadow.
        cat.setRugVisible(false)
        cat.onPetted = { [weak self] in
            self?.pet()
        }
    }

    func attach(_ model: PetModel) {
        self.model = model
        cat.setMood(model.mood)
    }

    func syncMood(_ mood: MurzikMood) {
        cat.setMood(mood)
    }

    private var hapticsOn: Bool { ExperienceSettings.isOn(ExperienceSettings.hapticsKey) }
    private var soundOn: Bool { ExperienceSettings.isOn(ExperienceSettings.soundKey) }

    // MARK: Actions

    func perform(_ action: PetAction) {
        model?.perform(action)
        cat.perform(action)
        burst(for: action)
        pulse += 1
        if action == .play, !toyMode {
            enterToyMode(performPlay: false)
        }
    }

    func pet() {
        guard !toyMode else { return }
        perform(.pet)
    }

    // MARK: Touch → purr

    /// Finger down / moving on the cat. `point` is normalized in the stage.
    func touchChanged(at point: CGPoint, translation: CGSize) {
        guard !toyMode else { return }
        if touchStart == nil {
            // Only touches on (or near) Murzik start a cuddle.
            guard abs(point.x - Self.catCenter.x) < 0.42, point.y > 0.12 else { return }
            touchStart = .now
            purrDelay?.cancel()
            purrDelay = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                self?.startPurr()
            }
        }
        // A stroke across the fur starts purring right away.
        if hypot(translation.width, translation.height) > 22 {
            startPurr()
        }
        if isPurring {
            cat.lookAt(normalizedPoint: point)
        }
    }

    func touchEnded() {
        touchStart = nil
        purrDelay?.cancel()
        purrDelay = nil
        stopPurr()
    }

    private func startPurr() {
        guard !isPurring, touchStart != nil, !toyMode else { return }
        isPurring = true
        purrStart = .now
        model?.perform(.pet)
        cat.perform(.pet)
        if hapticsOn { haptics.start() }
        if soundOn { sound.start() }
        purrLoop?.cancel()
        purrLoop = Task { [weak self] in
            var beat = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let self, !Task.isCancelled, self.isPurring else { return }
                beat += 1
                self.burst(symbol: "heart.fill", color: MurzikPalette.heart, count: 2, spread: 70)
                // Long cuddles keep making him happier (every ~8 s).
                if beat % 9 == 0 {
                    self.model?.perform(.pet)
                }
            }
        }
    }

    private func stopPurr() {
        guard isPurring else { return }
        isPurring = false
        purrLoop?.cancel()
        purrLoop = nil
        haptics.stop()
        sound.stop()
        cat.lookAt(normalizedPoint: nil)
        if let purrStart {
            model?.recordPurr(seconds: Date.now.timeIntervalSince(purrStart))
        }
        purrStart = nil
    }

    // MARK: Toy mode

    func enterToyMode(performPlay: Bool = true) {
        stopPurr()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            toyMode = true
            toyPoint = CGPoint(x: 0.72, y: 0.3)
        }
        cat.lookAt(normalizedPoint: toyPoint)
        lastToyPlay = .now
        if performPlay {
            model?.perform(.play)
            cat.perform(.play)
        }
    }

    func exitToyMode() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            toyMode = false
        }
        cat.lookAt(normalizedPoint: nil)
    }

    /// She drags the toy. `point` is normalized in the stage.
    func moveToy(to point: CGPoint) {
        guard toyMode else { return }
        let clamped = CGPoint(x: min(max(point.x, 0.04), 0.96), y: min(max(point.y, 0.04), 0.96))
        toyPoint = clamped
        cat.lookAt(normalizedPoint: clamped)

        let distance = hypot(clamped.x - Self.catCenter.x, (clamped.y - Self.catCenter.y) * 0.8)
        let now = Date.now
        if distance < 0.2, now.timeIntervalSince(lastCatch) > 2.2 {
            lastCatch = now
            caughtAt = now
            cat.perform(.play)
            burst(symbol: "sparkle", color: MurzikPalette.amber, count: 5, spread: 80)
            if hapticsOn { haptics.tap(intensity: 0.7, sharpness: 0.5) }
            // Playing changes his needs; don't let a long session drain him instantly.
            if now.timeIntervalSince(lastToyPlay) > 12 {
                lastToyPlay = now
                model?.perform(.play)
            }
        }
    }

    func toyReleased() {
        cat.lookAt(normalizedPoint: toyPoint)
    }

    // MARK: Particles

    func burst(for action: PetAction) {
        switch action {
        case .pet: burst(symbol: "heart.fill", color: MurzikPalette.heart)
        case .feed: burst(symbol: "fish.fill", color: MurzikPalette.amber)
        case .play: burst(symbol: "sparkle", color: MurzikPalette.mint)
        case .sleep: burst(symbol: "moon.zzz.fill", color: MurzikPalette.sky, count: 4)
        case .wake: burst(symbol: "sun.max.fill", color: MurzikPalette.amber, count: 4)
        }
    }

    func burst(symbol: String, color: Color, count: Int = 6, spread: CGFloat = 100) {
        let newParticles = (0..<count).map { index in
            Particle(
                symbol: symbol,
                color: color,
                x: CGFloat.random(in: -spread...spread),
                delay: Double(index) * 0.07,
                size: CGFloat.random(in: 16...26)
            )
        }
        bursts.append(contentsOf: newParticles)
        let ids = Set(newParticles.map(\.id))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            self?.bursts.removeAll { ids.contains($0.id) }
        }
    }
}
