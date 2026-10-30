import SwiftUI
import SceneKit

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

    // Stage camera framing (horizontal FOV in degrees, distance and target height in metres, pitch in radians).
    static let cameraFieldOfView: CGFloat = 42
    static let cameraDistance: Float = 3.46
    static let cameraTargetHeight: Float = 1.04
    static let cameraPitch: Float = 0.082

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
    /// The current touch started off the cat (no cuddle until the finger lifts).
    private var touchRejected = false
    private var purrStart: Date?
    private var purrDelay: Task<Void, Never>?
    private var purrLoop: Task<Void, Never>?
    private var lastCatch: Date = .distantPast
    private var lastToyPlay: Date = .distantPast

    init() {
        // Use the 3D rug (real shadows, Murzik wanders on it), framed by width so the whole rug
        // fits the tall stage. The camera looks almost level at a point above him, so the rug sits
        // low in the stage (on the room's floor) and the space above stays free for the bubble.
        if let camera = cat.engine.cameraNode.camera {
            camera.projectionDirection = .horizontal
            camera.fieldOfView = Self.cameraFieldOfView
        }
        let stage = cat.engine.stage
        stage.orbitDistance = Self.cameraDistance
        stage.orbitTarget = SIMD3(0, Self.cameraTargetHeight, 0)
        stage.orbitPitchOffset = Self.cameraPitch - 0.3   // the controller's default orbit pitch is 0.3
        stage.applyOrbit(yaw: 0, pitch: 0.3)
        cat.engine.prefersFacingViewer = true
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

    /// A tap on the cat (3D view or the island walker). Ignored in toy mode, and while purring:
    /// a purr already counted as one pet, strokes during it don't add more.
    func pet() {
        guard !toyMode, !isPurring else { return }
        perform(.pet)
    }

    /// Pauses the 3D view (settings sheet up, app not active).
    func setRenderingPaused(_ paused: Bool) {
        cat.setRenderingPaused(paused)
        if paused { touchEnded() }
    }

    // MARK: Touch → purr

    /// Finger down / moving on the stage. `point` and `start` are normalized in the stage.
    /// Only a touch that starts on Murzik himself (3D hit test) starts a cuddle; elsewhere the
    /// 3D view orbits the camera instead.
    func touchChanged(at point: CGPoint, start: CGPoint, translation: CGSize) {
        guard !toyMode else { return }
        if touchStart == nil {
            guard !touchRejected else { return }
            guard touchStartsOnCat(start) else {
                touchRejected = true
                return
            }
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

    private func touchStartsOnCat(_ start: CGPoint) -> Bool {
        if let view = cat.sceneView, view.bounds.width > 0, view.bounds.height > 0 {
            let p = CGPoint(x: start.x * view.bounds.width, y: start.y * view.bounds.height)
            return cat.hitsCat(p, in: view)
        }
        // No view yet: a rough box around where he sits.
        return abs(start.x - Self.catCenter.x) < 0.2 && abs(start.y - Self.catCenter.y) < 0.25
    }

    func touchEnded() {
        touchStart = nil
        touchRejected = false
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
