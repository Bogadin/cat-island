import SceneKit
import UIKit
import simd

/// Drives 3D Murzik: behaviour blending, facial expressions, look-at, autonomous life on the rug,
/// props and FX. Runs on SceneKit's render thread (as the SCNView delegate); commands from the main
/// thread are queued behind a lock.
final class MurzikEngine: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    enum Command {
        case mood(MurzikMood)
        case action(PetAction)
        case petted
        case orbit(yaw: Float, pitch: Float)
    }

    let scene: SCNScene
    let rig: MurzikRig
    let stage: MurzikStage
    var cameraNode: SCNNode { stage.cameraNode }

    // MARK: Thread-shared inputs (guarded by `lock`)
    private let lock = NSLock()
    private var commands: [Command] = []
    private var sharedLook: SIMD3<Float>?

    // MARK: Render-thread state
    private(set) var mood: MurzikMood = .idle
    private var position = SIMD2<Float>(0.05, 0.1)
    private var heading: Float = -0.5
    private var gait: Float = 0
    private var orbitYaw: Float = 0
    private var orbitPitch: Float = 0.3
    private var startTime: Double?
    private var lastTime: Double = 0
    private var rng = SplitMix(seed: 0x6D75_727A)

    private struct Track {
        var behavior: CatBehavior
        var start: Double
        var param: Float
        var gait: Float
    }
    private enum Previous {
        case track(Track)
        case frozen(CatPose)
    }
    private var current = Track(behavior: .sit, start: 0, param: 0, gait: 0)
    private var previous: Previous?
    private var fadeStart: Double = 0
    private var fadeDuration: Float = 0.4
    private var lastBlended = Poses.sitBase()

    // Brain
    enum Target {
        case point(SIMD2<Float>)
        case bowl
        case toy
        case camera
    }
    enum Event {
        case showBowl(SIMD2<Float>)
        case hideBowl
        case showToy(SIMD2<Float>)
        case rollToy
        case hideToy
    }
    struct Step {
        enum Kind {
            case walk(Target, run: Bool, stopShort: Float)
            case turn(Target)
            case act(CatBehavior)
            case event(Event)
        }
        var kind: Kind
        var seconds: Double?
        var param: Float = 0
        var lookCamera = false

        static func act(_ b: CatBehavior, _ seconds: Double? = nil, param: Float = 0, look: Bool = false) -> Step {
            Step(kind: .act(b), seconds: seconds, param: param, lookCamera: look)
        }
        static func walk(_ t: Target, run: Bool = false, stopShort: Float = 0) -> Step {
            Step(kind: .walk(t, run: run, stopShort: stopShort), seconds: nil)
        }
        static func turn(_ t: Target) -> Step { Step(kind: .turn(t), seconds: nil) }
        static func event(_ e: Event) -> Step { Step(kind: .event(e), seconds: nil) }
    }
    private var plan: [Step] = []
    private var step: Step?
    private var stepStart: Double = 0
    private var stepAdvance: Float = 0
    private var stepYaw: Float = 0
    private var bowlPos: SIMD2<Float>?
    private var toyPos: SIMD2<Float>?
    private var bowlShownAt: Double = 0
    private var lastFXSpawn: Double = 0

    // Look-at smoothing (yaw, pitch, weight)
    private var look = SIMD3<Float>(0, 0, 0)

    /// When false (sprite / hero renders), the brain and clock are not used.
    let autonomous: Bool

    init(stageConfig: MurzikStage.Config = .app, style: MurzikRig.Style = .app, autonomous: Bool = true) {
        let sc = SCNScene()
        scene = sc
        rig = MurzikRig(style: style)
        stage = MurzikStage(scene: sc, config: stageConfig)
        self.autonomous = autonomous
        super.init()
        scene.rootNode.addChildNode(rig.root)
        place()
        rig.apply(lastBlended, time: 0)
    }

    // MARK: - Commands (any thread)

    func send(_ c: Command) {
        lock.lock()
        commands.append(c)
        lock.unlock()
    }

    func setLookTarget(world: SIMD3<Float>?) {
        lock.lock()
        sharedLook = world
        lock.unlock()
    }

    private func takeInputs() -> ([Command], SIMD3<Float>?) {
        lock.lock()
        defer { lock.unlock() }
        let c = commands
        commands.removeAll()
        return (c, sharedLook)
    }

    // MARK: - SCNSceneRendererDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        tick(systemTime: time)
    }

    /// Advances the simulation to `systemTime` (seconds, any epoch).
    func tick(systemTime: Double) {
        if startTime == nil {
            startTime = systemTime
            lastTime = 0
        }
        let t = systemTime - (startTime ?? systemTime)
        let dt = Float(min(max(t - lastTime, 0), 0.1))
        lastTime = t
        let (cmds, lookTarget) = takeInputs()
        for c in cmds { handle(c, time: t) }
        if autonomous { think(time: t, dt: dt) }
        renderFrame(time: t, dt: dt, userLook: lookTarget)
    }

    // MARK: - Command handling

    private func handle(_ c: Command, time: Double) {
        switch c {
        case .mood(let m):
            guard m != mood else { return }
            let old = mood
            mood = m
            moodChanged(from: old, to: m, time: time)
        case .action(let a):
            perform(a, time: time)
        case .petted:
            perform(.pet, time: time)
        case .orbit(let yaw, let pitch):
            orbitYaw = yaw
            orbitPitch = pitch
            stage.setOrbit(yaw: yaw, pitch: pitch, distance: 3.6)
        }
    }

    private var isAsleep: Bool { current.behavior == .sleep }

    private func moodChanged(from old: MurzikMood, to m: MurzikMood, time: Double) {
        switch m {
        case .sleeping:
            if !isAsleep { setPlan(sleepPlan()) }
        case .surprised:
            setPlan([.act(.surprised), .act(.sit, 2.0, look: true)])
        case .excited:
            setPlan([.act(.jump), .act(.spin), .act(.jump), .act(.sit, 1.5, look: true)])
        default:
            if isAsleep { setPlan(wakePlan()) }
        }
    }

    private func perform(_ a: PetAction, time: Double) {
        switch a {
        case .pet:
            if current.behavior == .purr, var s = step, case .act(.purr) = s.kind {
                // Extend the current purr.
                s.seconds = (s.seconds ?? 4) + 2.5
                step = s
            } else {
                var p: [Step] = isAsleep ? [.act(.stretch)] : []
                p.append(.act(.purr, 4.5))
                p.append(.act(.sit, 2.0, look: true))
                setPlan(p)
            }
        case .feed:
            let fwd = forward
            var bp = position + fwd * 0.42
            bp = clampToRug(bp, radius: 0.82)
            let p: [Step] = isAsleep ? [.act(.stretch)] : []
            let seq: [Step] = [
                .event(.showBowl(bp)), .walk(.bowl, stopShort: 0.36), .turn(.bowl), .act(.eat, 7.0),
                .event(.hideBowl), .act(.sit, 1.0), .act(.groom, 4.2), .act(.sit, 2.0, look: true),
            ]
            setPlan(p + seq)
        case .play:
            var tp = position + rotate(forward, 0.35) * 0.75
            tp = clampToRug(tp, radius: 0.8)
            let p: [Step] = isAsleep ? [.act(.stretch)] : []
            let round1: [Step] = [.event(.showToy(tp)), .turn(.toy), .act(.crouch, 1.5), .act(.pounce, param: -1), .act(.bat)]
            let round2: [Step] = [.event(.rollToy), .turn(.toy), .act(.crouch, 1.2), .act(.pounce, param: -1), .act(.bat), .act(.bat)]
            let round3: [Step] = [.event(.rollToy), .walk(.toy, run: true, stopShort: 0.5), .act(.crouch, 0.9), .act(.pounce, param: -1)]
            let finale: [Step] = [.act(.jump), .event(.hideToy), .act(.sit, 2.0, look: true)]
            setPlan(p + round1 + round2 + round3 + finale)
        case .sleep:
            setPlan(sleepPlan())
        case .wake:
            setPlan(wakePlan())
        }
    }

    private func sleepPlan() -> [Step] {
        let c = clampToRug(position * 0.4, radius: 0.5)
        let r: Float = 0.13
        return [.walk(.point(c)),
                .walk(.point(c + SIMD2(r, 0))), .walk(.point(c + SIMD2(0, r))), .walk(.point(c + SIMD2(-r, 0))),
                .walk(.point(c + SIMD2(0, -r))), .walk(.point(c + SIMD2(r, 0))),
                .act(.loaf, 1.4), .act(.sleep)]
    }

    private func wakePlan() -> [Step] {
        [.act(.stretch), .act(.sit, 2.5, look: true)]
    }

    private func setPlan(_ p: [Step]) {
        plan = p
        step = nil
    }

    // MARK: - Brain

    private var forward: SIMD2<Float> { SIMD2(cos(heading), -sin(heading)) }

    private func rotate(_ v: SIMD2<Float>, _ a: Float) -> SIMD2<Float> {
        // Positive = toward the cat's left (same sense as heading).
        let c = cos(a), s = sin(a)
        return SIMD2(v.x * c + v.y * s, -v.x * s + v.y * c)
    }

    private func clampToRug(_ p: SIMD2<Float>, radius: Float) -> SIMD2<Float> {
        let l = simd_length(p)
        return l > radius ? p / l * radius : p
    }

    private func headingTo(_ p: SIMD2<Float>) -> Float {
        let d = p - position
        return atan2(-d.y, d.x)
    }

    private func cameraGround() -> SIMD2<Float> {
        let c = stage.cameraNode.simdWorldPosition
        return SIMD2(c.x, c.z)
    }

    private func resolve(_ t: Target) -> SIMD2<Float> {
        switch t {
        case .point(let p): return p
        case .bowl: return bowlPos ?? position
        case .toy: return toyPos ?? position
        case .camera: return cameraGround()
        }
    }

    private func randomRugPoint(minDistance: Float = 0.35, radius: Float = 0.68) -> SIMD2<Float> {
        for _ in 0..<12 {
            let a = rng.float() * CM.tau
            let r = sqrt(rng.float()) * radius
            let p = SIMD2<Float>(cos(a) * r, sin(a) * r)
            if simd_distance(p, position) > minDistance { return p }
        }
        return SIMD2(0, 0)
    }

    private func pick(_ weights: [(Float, () -> [Step])]) -> [Step] {
        let total = weights.reduce(0) { $0 + $1.0 }
        var x = rng.float() * total
        for (w, f) in weights {
            if x < w { return f() }
            x -= w
        }
        return weights.last?.1() ?? []
    }

    private func dur(_ a: Double, _ b: Double) -> Double { a + Double(rng.float()) * (b - a) }

    /// Picks the next autonomous activity, biased by mood.
    private func autonomousPlan() -> [Step] {
        let front = SIMD2<Float>(0, 0.45)
        switch mood {
        case .sleeping:
            return isAsleep ? [.act(.sleep, 30)] : sleepPlan()
        case .sleepy:
            return pick([
                (0.35, { [.act(.loaf, self.dur(7, 12))] }),
                (0.2, { [.act(.lie, self.dur(6, 10), look: true)] }),
                (0.12, { [.act(.stretch), .act(.sit, 2)] }),
                (0.2, { [.walk(.point(self.randomRugPoint(radius: 0.5))), .act(.loaf, self.dur(6, 10))] }),
                (0.13, { [.act(.sit, self.dur(3, 5), look: true), .act(.loaf, 6)] }),
            ])
        case .playful, .excited:
            return pick([
                (0.32, { [.walk(.point(self.randomRugPoint(minDistance: 0.6)), run: true),
                          .walk(.point(self.randomRugPoint(minDistance: 0.6)), run: true),
                          .walk(.point(self.randomRugPoint(minDistance: 0.6)), run: true), .act(.sit, 1.2, look: true)] }),
                (0.25, { [.act(.crouch, self.dur(1.2, 2.2)), .act(.pounce, param: 0.4), .act(.bat), .act(.sit, 1.5)] }),
                (0.15, { [.act(.jump), .act(.idle, 1.5, look: true)] }),
                (0.12, { [.act(.spin), .act(.sit, 1.5, look: true)] }),
                (0.16, { [.walk(.point(self.randomRugPoint())), .act(.idle, 2)] }),
            ])
        case .hungry:
            return pick([
                (0.35, { [.walk(.point(self.randomRugPoint(minDistance: 0.5))), .walk(.point(self.randomRugPoint(minDistance: 0.5))),
                          .act(.idle, 1)] }),
                (0.5, { [.walk(.point(front)), .turn(.camera), .act(.sit, 0.8, look: true), .act(.meow, look: true),
                         .act(.sit, 1.0, look: true), .act(.meow, look: true), .act(.sit, 2.0, look: true)] }),
                (0.15, { [.turn(.camera), .act(.sit, self.dur(3, 5), look: true)] }),
            ])
        case .loving:
            return pick([
                (0.5, { [.walk(.point(front)), .turn(.camera), .act(.sit, self.dur(4, 7), look: true)] }),
                (0.3, { [.walk(.point(self.randomRugPoint())), .act(.sit, 3, look: true)] }),
                (0.2, { [.act(.loaf, self.dur(5, 8))] }),
            ])
        case .surprised:
            return [.act(.idle, 2, look: true)]
        case .idle, .happy, .blinking:
            return pick([
                (0.3, { [.walk(.point(self.randomRugPoint())), .act(.sit, self.dur(3, 6))] }),
                (0.18, { [.walk(.point(self.randomRugPoint())), .act(.idle, self.dur(2, 4))] }),
                (0.14, { [.act(.sit, 1.0), .act(.groom, 4.2 * Double(1 + Int(self.rng.float() * 2))), .act(.sit, 1.5)] }),
                (0.16, { [.turn(.camera), .act(.sit, self.dur(3, 6), look: true)] }),
                (0.06, { [.act(.stretch), .act(.idle, 1.5)] }),
                (0.1, { [.act(.loaf, self.dur(5, 9))] }),
                (0.06, { [.act(.lie, self.dur(5, 8), look: true)] }),
            ])
        }
    }

    private func think(time: Double, dt: Float) {
        if step == nil {
            if plan.isEmpty { plan = autonomousPlan() }
            if plan.isEmpty { return }
            step = plan.removeFirst()
            stepStart = time
            stepAdvance = 0
            stepYaw = 0
            beginStep(time: time)
        }
        guard let s = step else { return }
        let elapsed = time - stepStart
        var done = false
        switch s.kind {
        case .event:
            done = true
        case .walk(let target, let run, let stopShort):
            let b: CatBehavior = run ? .trot : .walk
            play(b, time: time)
            let goal = resolve(target)
            let dist = simd_distance(goal, position) - stopShort
            if dist < 0.04 {
                done = true
            } else {
                let desired = headingTo(goal)
                let diff = CM.wrapAngle(desired - heading)
                let turnRate: Float = run ? 4.5 : 2.6
                let turn = CM.clamp(diff, -turnRate * dt, turnRate * dt)
                heading += turn
                let cadence: Float = run ? 2.4 : 1.25
                var speed = b.stride * cadence
                speed *= CM.clamp(cos(diff), 0.15, 1)
                speed = min(speed, dist * 3 + 0.05)
                let move = speed * dt
                position += forward * move
                gait += move / b.stride + abs(turn) * 0.12
            }
            if elapsed > 12 { done = true }
        case .turn(let target):
            play(.walk, time: time)
            let diff = CM.wrapAngle(headingTo(resolve(target)) - heading)
            let turn = CM.clamp(diff, -2.4 * dt, 2.4 * dt)
            heading += turn
            gait += abs(turn) * 0.32
            if abs(diff) < 0.06 || elapsed > 4 { done = true }
        case .act(let b):
            let t = Float(time - current.start)
            let ctx = BehaviorContext(gait: gait, param: current.param)
            let adv = b.advance(t, ctx)
            let yaw = b.yaw(t, ctx)
            position += forward * (adv - stepAdvance)
            heading += yaw - stepYaw
            stepAdvance = adv
            stepYaw = yaw
            if b == .spin { gait = t * 2.6 }
            let length = s.seconds ?? b.duration.map { Double($0) }
            if let length, elapsed >= length { done = true }
        }
        position = clampToRug(position, radius: 0.85)
        if done { finishStep(time: time) }
    }

    private func beginStep(time: Double) {
        guard let s = step else { return }
        switch s.kind {
        case .event(let e):
            switch e {
            case .showBowl(let p):
                bowlPos = p
                stage.bowl.simdPosition = SIMD3(p.x, 0, p.y)
                stage.food.simdScale = SIMD3(repeating: 1)
                stage.bowl.isHidden = false
                stage.bowl.simdScale = SIMD3(repeating: 0.01)
                stage.bowl.runAction(.scale(to: 1, duration: 0.35))
                bowlShownAt = time
            case .hideBowl:
                stage.bowl.runAction(.sequence([.scale(to: 0.01, duration: 0.3), .hide()]))
                bowlPos = nil
            case .showToy(let p):
                toyPos = p
                stage.toy.removeAllActions()
                stage.toy.simdPosition = SIMD3(p.x, 0.065, p.y)
                stage.toy.isHidden = false
                stage.toy.simdScale = SIMD3(repeating: 0.01)
                stage.toy.runAction(.scale(to: 1, duration: 0.35))
            case .rollToy:
                let from = toyPos ?? position
                var to = from + rotate(forward, rng.float() * 2 - 1) * (0.45 + rng.float() * 0.25)
                to = clampToRug(to, radius: 0.78)
                toyPos = to
                let d = simd_distance(from, to)
                let move = SCNAction.move(to: SCNVector3(to.x, 0.065, to.y), duration: Double(0.4 + d))
                move.timingMode = .easeOut
                let axis = simd_normalize(SIMD3<Float>(to.y - from.y, 0, -(to.x - from.x)) + SIMD3(0, 0.0001, 0))
                let spin = SCNAction.rotate(by: CGFloat(-d / 0.065), around: SCNVector3(axis.x, axis.y, axis.z), duration: Double(0.4 + d))
                spin.timingMode = .easeOut
                stage.toy.runAction(.group([move, spin]))
            case .hideToy:
                stage.toy.runAction(.sequence([.scale(to: 0.01, duration: 0.3), .hide()]))
                toyPos = nil
            }
        case .act(let b):
            var param = s.param
            if b == .pounce, param < 0 {
                let tp = toyPos ?? (position + forward * 0.5)
                param = CM.clamp(simd_distance(tp, position) - 0.3, 0.05, 0.7)
                heading = headingTo(tp)
            }
            play(b, time: time, param: param, restart: b.duration != nil || b == .purr)
        default:
            break
        }
    }

    private func finishStep(time: Double) {
        step = nil
    }

    // MARK: - Behaviour player

    private func play(_ b: CatBehavior, time: Double, param: Float = 0, restart: Bool = false) {
        if current.behavior == b && !restart { return }
        let fadeK = fadeDuration > 0 ? Float(time - fadeStart) / fadeDuration : 1
        if previous != nil && fadeK < 1 {
            previous = .frozen(lastBlended)
        } else {
            previous = .track(current)
        }
        current = Track(behavior: b, start: time, param: param, gait: gait)
        fadeStart = time
        fadeDuration = b.fadeIn
    }

    private func pose(of track: Track, time: Double) -> CatPose {
        let t = Float(time - track.start)
        let ctx = BehaviorContext(gait: gait, param: track.param)
        return track.behavior.pose(t, ctx)
    }

    private func blendedPose(time: Double) -> CatPose {
        var p = pose(of: current, time: time)
        if let prev = previous {
            let k = fadeDuration > 0 ? Float(time - fadeStart) / fadeDuration : 1
            if k >= 1 {
                previous = nil
            } else {
                let a: CatPose
                switch prev {
                case .track(let tr): a = pose(of: tr, time: time)
                case .frozen(let fp): a = fp
                }
                p = CatPose.mix(a, p, CM.ease(k))
            }
        }
        lastBlended = p
        return p
    }

    // MARK: - Faces & layers

    static func moodFace(_ m: MurzikMood) -> CatFaceState {
        var f = CatFaceState()
        switch m {
        case .idle: break
        case .happy:
            f.lidLower = 0.42; f.lidUpper = 0.08; f.pupil = 0.7; f.jaw = 0.12
        case .sleepy:
            f.lidUpper = 0.58; f.pupil = 0.6
        case .sleeping, .blinking:
            f.lidUpper = 1
        case .playful:
            f.pupil = 0.95; f.lidUpper = 0
        case .hungry:
            f.pupil = 0.85; f.lidUpper = 0.04; f.gaze.y = 0.25
        case .loving:
            f.lidUpper = 0.95; f.lidLower = 0.55; f.blush = 1
        case .surprised:
            f.lidUpper = 0; f.pupil = 1; f.jaw = 0.3
        case .excited:
            f.lidUpper = 0; f.lidLower = 0.3; f.pupil = 1; f.jaw = 0.35
        }
        return f
    }

    static func moodEars(_ m: MurzikMood) -> SIMD3<Float> {
        switch m {
        case .surprised: return SIMD3(0.3, 0, 0.45)
        case .sleepy: return SIMD3(0.18, 0, 0.12)
        case .playful, .excited: return SIMD3(0, 0, -0.1)
        case .hungry: return SIMD3(0, 0, -0.05)
        case .loving, .happy: return SIMD3(0.1, 0, 0)
        default: return SIMD3(0, 0, 0)
        }
    }

    /// Deterministic random blink: returns lid closure 0...1.
    static func blink(_ t: Double) -> Float {
        let period = 3.6
        let k = Int(floor(t / period))
        let offset = Double(CM.hash(k)) * (period - 0.4)
        let local = Float(t - Double(k) * period - offset)
        let double = CM.hash(k + 7_777) > 0.75
        var b = CM.window(local, 0, 0.07, 0.1, 0.2)
        if double { b = max(b, CM.window(local, 0.28, 0.35, 0.38, 0.48)) }
        return b
    }

    /// Deterministic ear twitch (additive ear rotation for one ear).
    static func earTwitch(_ t: Double, seed: Int) -> Float {
        let period = 5.3 + Double(seed) * 1.7
        let k = Int(floor(t / period))
        let offset = Double(CM.hash(k * 31 + seed)) * (period - 0.5)
        let local = Float(t - Double(k) * period - offset)
        return CM.window(local, 0, 0.06, 0.12, 0.3)
    }

    /// Applies mood face, blink, ear twitches and look-at to a behaviour pose.
    func finalize(_ base: CatPose, time: Double, mood: MurzikMood, lookYaw: Float, lookPitch: Float, lookWeight: Float, blinks: Bool = true) -> CatPose {
        var p = base
        let mf = MurzikEngine.moodFace(mood)
        p.face = CatFaceState.mix(mf, base.face, CM.sat(base.faceWeight))
        if base.faceWeight < 0.999 {
            // Keep mood blush/smile even when a behaviour sets eyes.
            p.face.blush = max(p.face.blush, mf.blush * (1 - base.faceWeight))
        }
        if blinks && p.face.lidUpper < 0.8 {
            let b = MurzikEngine.blink(time)
            p.face.lidUpper = CM.mix(p.face.lidUpper, 1, b)
        }
        let ears = MurzikEngine.moodEars(mood)
        p.earL += ears
        p.earR += ears
        if p.face.lidUpper < 0.9 {
            p.earL.z += 0.35 * MurzikEngine.earTwitch(time, seed: 1)
            p.earL.y += 0.2 * MurzikEngine.earTwitch(time, seed: 1)
            p.earR.z += 0.35 * MurzikEngine.earTwitch(time, seed: 2)
            p.earR.y += 0.2 * MurzikEngine.earTwitch(time, seed: 2)
        }
        let w = lookWeight * p.lookWeight
        if w > 0.001 {
            p.neck.y += lookYaw * 0.45 * w
            p.head.y += lookYaw * 0.4 * w
            p.neck.z += lookPitch * 0.3 * w
            p.head.z += lookPitch * 0.45 * w
            p.head.x += -lookYaw * 0.08 * w
            let gx = CM.clamp(lookYaw * 0.6, -1, 1)
            let gy = CM.clamp(lookPitch * 0.8, -1, 1)
            p.face.gaze = CM.mix(p.face.gaze, SIMD2(gx, gy), min(1, w))
        }
        return p
    }

    /// Yaw/pitch (root frame) from the head to a world point.
    func lookAngles(toWorld target: SIMD3<Float>) -> (Float, Float, Float) {
        let tr = rig.root.simdConvertPosition(target, from: nil)
        let h = rig.headPositionInRoot
        let d = tr - h
        var yaw = atan2(-d.z, d.x)
        let flat = sqrt(d.x * d.x + d.z * d.z)
        let pitch = CM.clamp(atan2(d.y, flat), -0.5, 0.65)
        // Behind the cat: fade out rather than snapping the head around.
        let behind = CM.ramp(abs(yaw), 1.6, 2.4)
        yaw = CM.clamp(yaw, -1.15, 1.15)
        return (yaw, pitch, 1 - behind)
    }

    // MARK: - Frame

    private func place() {
        rig.root.simdPosition = SIMD3(position.x, 0, position.y)
        rig.root.simdOrientation = simd_quatf(angle: heading, axis: SIMD3(0, 1, 0))
    }

    private func renderFrame(time: Double, dt: Float, userLook: SIMD3<Float>?) {
        place()
        let base = blendedPose(time: time)
        // Look target: user's finger > camera (when the step asks) > none.
        var targetYaw: Float = 0, targetPitch: Float = 0, targetW: Float = 0
        if let u = userLook {
            let (y, p, w) = lookAngles(toWorld: u)
            targetYaw = y; targetPitch = p; targetW = w
        } else if let s = step, s.lookCamera {
            let (y, p, w) = lookAngles(toWorld: stage.cameraNode.simdWorldPosition)
            targetYaw = y; targetPitch = p; targetW = w * 0.9
        }
        let k = 1 - exp(-dt * 5)
        if targetW > 0.01 {
            look.x += (targetYaw - look.x) * k
            look.y += (targetPitch - look.y) * k
        }
        look.z += (targetW - look.z) * k
        let p = finalize(base, time: time, mood: mood, lookYaw: look.x, lookPitch: look.y, lookWeight: look.z)
        rig.apply(p, time: time)
        updateProps(time: time)
        updateFX(time: time)
    }

    private func updateProps(time: Double) {
        if current.behavior == .eat, bowlPos != nil {
            let eaten = CM.sat(Float(time - current.start) / 7)
            let s = max(0.05, 1 - eaten * 0.85)
            stage.food.simdScale = SIMD3(s, s, s)
        }
    }

    private func updateFX(time: Double) {
        switch current.behavior {
        case .purr:
            if time - lastFXSpawn > 0.55, time - current.start > 0.4 {
                lastFXSpawn = time
                var h = rig.headWorld
                let r = rng.float()
                h += SIMD3(r * 0.16 - 0.08, 0.2, rng.float() * 0.1 - 0.05)
                stage.spawn(.heart, at: h, time: time, seed: r)
            }
        case .sleep:
            if time - lastFXSpawn > 1.25, time - current.start > 1.5 {
                lastFXSpawn = time
                let h = rig.headWorld + SIMD3(0.05, 0.16, 0)
                stage.spawn(.zzz, at: h, time: time, seed: rng.float())
            }
        default:
            break
        }
        stage.updateFX(time: time)
    }

    // MARK: - Static posing (tests, sprites, hero renders)

    /// Poses the cat deterministically at the origin facing +X (or at `heading`).
    func setStaticPose(_ behavior: CatBehavior, t: Float, gait: Float = 0, param: Float = 0, mood: MurzikMood = .idle,
                       lookAt target: SIMD3<Float>? = nil, heading: Float = 0, at pos: SIMD2<Float> = .zero,
                       modify: ((inout CatPose) -> Void)? = nil) {
        position = pos
        self.heading = heading
        place()
        var base = behavior.pose(t, BehaviorContext(gait: gait, param: param))
        modify?(&base)
        // First pass so the head position is valid for look-at.
        var p = finalize(base, time: 0.05, mood: mood, lookYaw: 0, lookPitch: 0, lookWeight: 0, blinks: false)
        rig.apply(p, time: 0)
        if let target {
            let (y, pi, w) = lookAngles(toWorld: target)
            p = finalize(base, time: 0.05, mood: mood, lookYaw: y, lookPitch: pi, lookWeight: w, blinks: false)
            rig.apply(p, time: 0)
        }
    }

    func showBowl(at p: SIMD2<Float>?, fill: Float = 1) {
        if let p {
            stage.bowl.isHidden = false
            stage.bowl.simdScale = SIMD3(repeating: 1)
            stage.bowl.simdPosition = SIMD3(p.x, 0, p.y)
            stage.food.simdScale = SIMD3(repeating: fill)
        } else {
            stage.bowl.isHidden = true
        }
    }

    func showToy(at p: SIMD2<Float>?) {
        if let p {
            stage.toy.isHidden = false
            stage.toy.simdScale = SIMD3(repeating: 1)
            stage.toy.simdPosition = SIMD3(p.x, 0.065, p.y)
        } else {
            stage.toy.isHidden = true
        }
    }

    /// Adds a static FX node (heart / z) at a world position (for stills).
    @discardableResult
    func addStaticFX(_ kind: MurzikStage.FXKind, at p: SIMD3<Float>, scale: Float = 1) -> SCNNode {
        let n = stage.makeFXNode(kind)
        n.simdPosition = p
        n.simdScale = SIMD3(repeating: scale)
        stage.fxRoot.addChildNode(n)
        return n
    }

    func clearStaticFX() {
        stage.fxRoot.childNodes.forEach { $0.removeFromParentNode() }
    }

    /// Debug/test: current behaviour name.
    var currentBehavior: CatBehavior { current.behavior }
}

/// Tiny deterministic RNG.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func float() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}
