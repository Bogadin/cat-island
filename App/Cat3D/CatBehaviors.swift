import Foundation
import simd

/// Inputs for evaluating a behaviour pose.
struct BehaviorContext {
    /// Gait phase in cycles (advances with distance travelled).
    var gait: Float = 0
    /// Free parameter (e.g. pounce distance).
    var param: Float = 0
}

/// Everything Murzik can do. Each case is a deterministic function of local time → pose.
enum CatBehavior: String, CaseIterable {
    case idle, walk, trot, sit, loaf, lie, sleep, groom, stretch, crouch, pounce, bat, eat, purr,
         surprised, jump, spin, meow, peek

    /// Natural length of one-shot behaviours (nil = loops until replaced).
    var duration: Float? {
        switch self {
        case .stretch: return 3.6
        case .pounce: return 1.15
        case .bat: return 0.9
        case .surprised: return 1.7
        case .jump: return 1.25
        case .spin: return 1.5
        case .meow: return 1.6
        default: return nil
        }
    }

    /// Cross-fade time into this behaviour.
    var fadeIn: Float {
        switch self {
        case .walk, .trot: return 0.3
        case .sit, .loaf, .lie: return 0.75
        case .sleep: return 1.3
        case .pounce, .bat, .surprised: return 0.18
        case .jump, .spin: return 0.25
        case .peek: return 0.5
        default: return 0.45
        }
    }

    /// Gait stride (m per cycle) for locomotion behaviours.
    var stride: Float {
        switch self {
        case .trot, .spin: return 0.3
        default: return 0.2
        }
    }

    var isLocomotion: Bool { self == .walk || self == .trot }

    /// Root displacement along the heading at local time t (meters, cumulative).
    func advance(_ t: Float, _ ctx: BehaviorContext) -> Float {
        switch self {
        case .pounce: return (ctx.param > 0 ? ctx.param : 0.42) * CM.ramp(t, 0.3, 0.72)
        case .surprised: return -0.1 * CM.ramp(t, 0.08, 0.42)
        case .jump: return 0.04 * CM.ramp(t, 0.3, 0.8)
        default: return 0
        }
    }

    /// Root yaw change at local time t (radians, cumulative).
    func yaw(_ t: Float, _ ctx: BehaviorContext) -> Float {
        switch self {
        case .spin: return CM.tau * CM.ramp(t, 0.1, 1.35)
        case .jump: return 0
        default: return 0
        }
    }

    func pose(_ t: Float, _ ctx: BehaviorContext) -> CatPose {
        switch self {
        case .idle: return Poses.idle(t)
        case .walk: return Poses.walk(ctx.gait, t)
        case .trot: return Poses.trot(ctx.gait, t)
        case .sit: return Poses.sit(t)
        case .loaf: return Poses.loaf(t)
        case .lie: return Poses.lie(t)
        case .sleep: return Poses.sleep(t)
        case .groom: return Poses.groom(t)
        case .stretch: return Poses.stretch(t)
        case .crouch: return Poses.crouch(t)
        case .pounce: return Poses.pounce(t)
        case .bat: return Poses.bat(t)
        case .eat: return Poses.eat(t)
        case .purr: return Poses.purr(t)
        case .surprised: return Poses.surprised(t)
        case .jump: return Poses.jump(t)
        case .spin: return Poses.spin(t)
        case .meow: return Poses.meow(t)
        case .peek: return Poses.peek(t)
        }
    }
}

/// Pose library.
enum Poses {
    static let g = CatPose.groundY

    // MARK: Tail helpers

    /// Builds a tail: base lift, per-segment curl, extra tip curl, travelling sway wave.
    static func tail(_ p: inout CatPose, base: Float, curl: Float, tip: Float = 0.12,
                     sway: Float = 0.08, freq: Float = 0.35, t: Float, side: Float = 0, lag: Float = 0.55) {
        let n = CatPose.tailCount
        for i in 0..<n {
            let k = Float(i) / Float(n - 1)
            var lift = i == 0 ? base : curl
            if k > 0.65 { lift += tip }
            let wave = sin(CM.tau * freq * t - Float(i) * lag)
            let amp = i == 0 ? sway * 2.2 : sway * (0.6 + 0.8 * k)
            p.tail[i] = SIMD2(lift, side + wave * amp)
        }
    }

    static func lookAround(_ p: inout CatPose, _ t: Float, amount: Float = 1) {
        let yaw = CM.wobble(t * 0.42, seed: 1) * 0.42 * amount
        let pitch = CM.wobble(t * 0.33, seed: 2) * 0.12 * amount
        let roll = CM.wobble(t * 0.27, seed: 3) * 0.1 * amount
        p.neck.y += yaw * 0.5
        p.head.y += yaw * 0.5
        p.head.z += pitch
        p.head.x += roll
        p.face.gaze.x = yaw * 0.6
        p.face.gaze.y = pitch
    }

    // MARK: Standing & locomotion

    static func stand() -> CatPose {
        var p = CatPose()
        p.neck.z = -0.05
        p.head.z = 0.02
        return p
    }

    static func idle(_ t: Float) -> CatPose {
        var p = stand()
        p.bodyPos.x += 0.006 * sin(t * 0.7)
        p.body.x = 0.015 * sin(t * 0.7)
        lookAround(&p, t)
        tail(&p, base: 0.55 + 0.12 * sin(t * 0.5), curl: 0.16, tip: 0.18, sway: 0.09, freq: 0.32, t: t)
        return p
    }

    /// Foot target for one leg in a gait cycle.
    private static func gaitFoot(rest: SIMD3<Float>, phase: Float, duty: Float, stride: Float, lift: Float) -> (SIMD3<Float>, Float) {
        var f = rest
        let p = CM.fract(phase)
        if p < duty {
            let s = p / duty
            f.x += stride * (0.5 - s)
            return (f, 0)
        } else {
            let s = (p - duty) / (1 - duty)
            f.x += stride * (-0.5 + CM.ease(s))
            f.y += lift * sin(CM.pi * s)
            return (f, sin(CM.pi * s))
        }
    }

    static func walk(_ phase: Float, _ t: Float) -> CatPose {
        var p = stand()
        // Lateral-sequence walk: HL → FL → HR → FR.
        let offsets: [Float] = [0.25, 0.75, 0.0, 0.5]
        for i in 0..<4 {
            let front = i < 2
            let (f, sw) = gaitFoot(rest: CatPose.restFeet[i], phase: phase + offsets[i], duty: 0.62,
                                   stride: 0.2, lift: front ? 0.055 : 0.045)
            p.feet[i] = f
            p.pawTilt[i] = front ? -0.7 * sw : -0.35 * sw
        }
        let w = CM.tau * phase
        p.bodyPos.y += 0.007 * cos(2 * w)
        p.bodyPos.x += 0.004 * sin(2 * w)
        p.body.x = 0.035 * sin(w)
        p.body.z = -0.02 + 0.012 * sin(2 * w)
        p.chest.y = 0.05 * sin(w)
        p.hips.y = -0.05 * sin(w)
        p.hips.x = -0.03 * sin(w)
        p.neck.z = -0.1 - 0.02 * cos(2 * w)
        p.head.z = 0.06 + 0.025 * cos(2 * w)
        p.head.y = -0.04 * sin(w)
        p.head.x = -0.02 * sin(w)
        tail(&p, base: 1.05, curl: 0.05, tip: 0.32, sway: 0.06, freq: 0, t: 0, side: 0)
        for i in 0..<CatPose.tailCount {
            let k = Float(i) / Float(CatPose.tailCount - 1)
            p.tail[i].y += 0.07 * (0.4 + k) * sin(w - Float(i) * 0.45)
        }
        p.earL.z = 0.05
        p.earR.z = 0.05
        p.lookWeight = 0.7
        return p
    }

    static func trot(_ phase: Float, _ t: Float) -> CatPose {
        var p = stand()
        // Diagonal pairs: FL+HR, FR+HL.
        let offsets: [Float] = [0.0, 0.5, 0.5, 0.0]
        for i in 0..<4 {
            let front = i < 2
            var rest = CatPose.restFeet[i]
            rest.x += front ? 0.02 : -0.01
            let (f, sw) = gaitFoot(rest: rest, phase: phase + offsets[i], duty: 0.42,
                                   stride: 0.3, lift: front ? 0.085 : 0.07)
            p.feet[i] = f
            p.pawTilt[i] = front ? -1.0 * sw : -0.5 * sw
        }
        let w = CM.tau * phase
        p.bodyPos.y += 0.012 + 0.014 * cos(2 * w)
        p.body.z = -0.06 + 0.02 * sin(2 * w)
        p.body.x = 0.02 * sin(w)
        p.chest.z = 0.02 * cos(2 * w)
        p.neck.z = -0.02 + 0.03 * cos(2 * w)
        p.head.z = -0.02 - 0.03 * cos(2 * w)
        p.earL.z = 0.25
        p.earR.z = 0.25
        tail(&p, base: 0.55, curl: 0.05, tip: 0.2, sway: 0, freq: 0, t: 0)
        for i in 0..<CatPose.tailCount {
            p.tail[i].y += 0.06 * sin(w * 2 - Float(i) * 0.5)
            p.tail[i].x += 0.04 * cos(w * 2 - Float(i) * 0.5)
        }
        p.face.pupil = 0.95
        p.face.lidUpper = 0
        p.face.jaw = 0.08
        p.faceWeight = 0.5
        p.lookWeight = 0.4
        return p
    }

    // MARK: Postures

    static func sitBase() -> CatPose {
        var p = CatPose()
        p.bodyPos = SIMD3(-0.03, 0.2, 0)
        p.body.z = 0.52
        p.chest.z = 0.12
        p.hips.z = -0.32
        p.neck.z = -0.42
        p.head.z = -0.2
        p.feet = [
            SIMD3(0.165, g, -0.06), SIMD3(0.165, g, 0.06),
            SIMD3(0.02, g, -0.11), SIMD3(0.02, g, 0.11),
        ]
        p.pawTilt = [0, 0, 0, 0]
        // Tail wrapped around the front, on the floor (toward the cat's right / camera side).
        p.tail = Poses.floorTail(side: -1, wrap: 0.34, parentPitch: 0.2, dropSegments: 3)
        return p
    }

    /// Tail that drops to the floor and then wraps around the body in the floor plane.
    /// side -1 = toward the cat's right, +1 = left. `parentPitch` = nose-up pitch of the hips frame.
    static func floorTail(side: Float, wrap: Float = 0.3, parentPitch: Float = 0, dropSegments: Int = 3) -> [SIMD2<Float>] {
        let steep: Float = 1.2
        var t = [SIMD2<Float>](repeating: SIMD2(0, 0), count: CatPose.tailCount)
        t[0] = SIMD2(-(steep - parentPitch), side * 0.45)
        let level = min(max(dropSegments, 1), CatPose.tailCount - 2)
        t[level] = SIMD2(steep, side * wrap)
        for i in (level + 1)..<CatPose.tailCount {
            t[i] = SIMD2(0, side * wrap)
        }
        t[CatPose.tailCount - 1].x = 0.25
        return t
    }

    static func sit(_ t: Float) -> CatPose {
        var p = sitBase()
        lookAround(&p, t, amount: 0.9)
        // Tip flick
        for i in 7..<CatPose.tailCount {
            p.tail[i].x += 0.18 * max(0, sin(t * 1.3)) * Float(i - 6) / 3
            p.tail[i].y += 0.05 * sin(t * 1.9 + Float(i))
        }
        return p
    }

    static func loaf(_ t: Float) -> CatPose {
        var p = CatPose()
        p.bodyPos = SIMD3(0, 0.165, 0)
        p.body.z = 0.02
        p.neck.z = -0.28
        p.head.z = 0.12
        p.feetGround = 0
        p.feet = [SIMD3(0.06, -0.06, 0.005), SIMD3(0.06, -0.06, -0.005), SIMD3(0.08, -0.07, 0), SIMD3(0.08, -0.07, 0)]
        p.pawTilt = [-1.4, -1.4, -1.3, -1.3]
        lookAround(&p, t * 0.6, amount: 0.5)
        let n = CatPose.tailCount
        p.tail = Poses.floorTail(side: -1, wrap: 0.3, dropSegments: 4)
        p.tail[n - 1].x += 0.2 * max(0, sin(t * 0.9))
        p.breathAmp = 1.1
        p.earL.x = 0.1
        p.earR.x = 0.1
        return p
    }

    /// Sphinx: lying down with front paws forward.
    static func lie(_ t: Float) -> CatPose {
        var p = CatPose()
        p.bodyPos = SIMD3(-0.02, 0.15, 0)
        p.body.z = 0.03
        p.neck.z = -0.12
        p.head.z = 0.0
        p.feet = [
            SIMD3(0.33, g, -0.07), SIMD3(0.35, g, 0.07),
            SIMD3(-0.03, g, -0.13), SIMD3(-0.03, g, 0.13),
        ]
        p.pawTilt = [0, 0, -0.3, -0.3]
        lookAround(&p, t * 0.7, amount: 0.7)
        let n = CatPose.tailCount
        p.tail = Poses.floorTail(side: -1, wrap: 0.22, dropSegments: 4)
        p.tail[n - 1].x += 0.25 * max(0, sin(t * 1.1))
        p.tail[n - 2].x += 0.1 * max(0, sin(t * 1.1))
        return p
    }

    /// Curled up asleep, nose tucked toward the tail.
    static func sleep(_ t: Float) -> CatPose {
        var p = CatPose()
        p.bodyPos = SIMD3(0.0, 0.15, 0)
        p.body.x = 0.04
        p.chest.y = -0.5
        p.hips.y = 0.45
        p.neck.y = -0.6
        p.neck.z = -0.62
        p.head.y = -0.35
        p.head.z = -0.05
        p.head.x = 0.22
        p.feetGround = 0
        p.feet = [SIMD3(0.09, -0.06, 0.0), SIMD3(0.1, -0.055, 0.0), SIMD3(0.1, -0.06, 0), SIMD3(0.11, -0.055, 0)]
        p.pawTilt = [-1.2, -1.2, -1.2, -1.2]
        let n = CatPose.tailCount
        p.tail = Poses.floorTail(side: -1, wrap: 0.42, dropSegments: 4)
        p.tail[n - 1].y += -0.12 * sin(t * 0.7)
        p.breathAmp = 1.6
        p.breathRate = 0.22
        p.earL.z = 0.15
        p.earR.z = 0.15
        p.earL.x = 0.25
        p.earR.x = 0.25
        p.face.lidUpper = 1
        p.face.lidLower = 0
        p.face.pupil = 0.5
        p.faceWeight = 1
        p.lookWeight = 0
        return p
    }

    // MARK: Grooming / stretching

    static func groom(_ t: Float) -> CatPose {
        var p = sitBase()
        let cycle: Float = 4.2
        let c = CM.fract(t / cycle) * cycle
        // 0–1.9 s: lick the raised paw. 1.9–3.9: wipe face. Then lower briefly.
        let raise = CM.window(c, 0.0, 0.45, 3.7, 4.15)
        let wipe = CM.window(c, 1.9, 2.2, 3.5, 3.8)
        let lick = CM.window(c, 0.35, 0.55, 1.75, 1.95)
        var paw = SIMD3<Float>(0.255, 0.39, 0.035)
        let wa = sin((c - 1.9) * CM.tau * 1.1)
        let wipeTarget = SIMD3<Float>(0.24 + 0.025 * wa, 0.47 + 0.05 * wa, 0.075)
        paw = CM.mix(paw, wipeTarget, wipe)
        let rest = p.feet[1]
        p.feet[1] = CM.mix(rest, paw, raise)
        p.pawTilt[1] = 1.3 * raise
        // Lean toward the paw.
        let lickBob = sin(c * CM.tau * 2.4)
        p.neck.z += -0.1 * raise
        p.head.z += (-0.35 + 0.08 * lickBob) * lick + 0.1 * wipe * wa
        p.head.x += -0.18 * lick + 0.28 * wipe
        p.neck.y += -0.12 * raise
        p.body.x = 0.06 * raise
        p.face.lidUpper = CM.mix(0.2, 0.95, max(lick, wipe))
        p.face.tongue = lick * (0.55 + 0.35 * max(0, lickBob))
        p.face.jaw = lick * (0.18 + 0.1 * max(0, lickBob))
        p.faceWeight = max(lick, wipe)
        p.earL.z = 0.12 * wipe
        p.earR.z = 0.35 * wipe
        p.lookWeight = 1 - raise
        return p
    }

    static func stretch(_ t: Float) -> CatPose {
        let base = stand()
        // Play-bow stretch.
        var bow = stand()
        bow.bodyPos = SIMD3(0.0, 0.25, 0)
        bow.body.z = -0.5
        bow.hips.z = 0.12
        bow.neck.z = 0.5
        bow.head.z = 0.12
        bow.feet[0] = SIMD3(0.4, g, -0.07)
        bow.feet[1] = SIMD3(0.4, g, 0.07)
        bow.feet[2] = SIMD3(-0.12, g, -0.085)
        bow.feet[3] = SIMD3(-0.12, g, 0.085)
        bow.pawTilt = [0.15, 0.15, 0, 0]
        tail(&bow, base: 1.35, curl: 0.04, tip: 0.18, sway: 0.02, freq: 0.5, t: t)
        // Forward stretch with a hind leg extended.
        var fwd = stand()
        fwd.bodyPos = SIMD3(0.06, 0.29, 0)
        fwd.body.z = 0.06
        fwd.neck.z = 0.12
        fwd.head.z = 0.08
        fwd.feet[0] = SIMD3(0.22, g, -0.075)
        fwd.feet[1] = SIMD3(0.22, g, 0.075)
        fwd.feet[2] = SIMD3(-0.12, g, -0.085)
        fwd.feet[3] = SIMD3(-0.36, 0.07, 0.085)
        fwd.pawTilt[3] = -0.9
        tail(&fwd, base: 0.5, curl: 0.04, tip: 0.1, sway: 0.03, freq: 0.5, t: t)

        let a = CM.ramp(t, 0.0, 0.7)
        let b = CM.ramp(t, 1.9, 2.5)
        let c = CM.ramp(t, 3.0, 3.6)
        var p = CatPose.mix(CatPose.mix(CatPose.mix(base, bow, a), fwd, b), base, c)
        // Yawn during the bow.
        let yawn = CM.window(t, 0.7, 1.1, 1.6, 2.0)
        p.face.jaw = yawn
        p.face.lidUpper = CM.mix(0.15, 1.0, CM.window(t, 0.6, 0.9, 1.75, 2.1))
        p.face.tongue = 0.3 * yawn
        p.faceWeight = CM.window(t, 0.4, 0.7, 2.6, 3.2)
        p.earL.z = 0.45 * yawn
        p.earR.z = 0.45 * yawn
        p.earL.x = 0.25 * yawn
        p.earR.x = 0.25 * yawn
        p.head.z += 0.22 * yawn
        p.lookWeight = 0.2
        return p
    }

    // MARK: Play

    static func crouchBase() -> CatPose {
        var p = stand()
        p.bodyPos = SIMD3(-0.02, 0.2, 0)
        p.body.z = -0.1
        p.hips.z = 0.08
        p.neck.z = 0.1
        p.head.z = -0.02
        p.feet[0] = SIMD3(0.25, g, -0.07)
        p.feet[1] = SIMD3(0.25, g, 0.07)
        p.feet[2] = SIMD3(-0.12, g, -0.095)
        p.feet[3] = SIMD3(-0.12, g, 0.095)
        p.earL.z = -0.08
        p.earR.z = -0.08
        p.face.pupil = 1
        p.face.lidUpper = 0
        p.faceWeight = 0.85
        return p
    }

    static func crouch(_ t: Float) -> CatPose {
        var p = crouchBase()
        let wig = sin(t * CM.tau * 3.2)
        let intensity = CM.ramp(t, 0.3, 0.8)
        p.hips.y = 0.16 * wig * intensity
        p.hips.x = 0.06 * wig * intensity
        p.bodyPos.y += 0.012 * abs(wig) * intensity
        p.body.z += -0.03 * intensity
        tail(&p, base: 0.12, curl: 0.02, tip: 0.25, sway: 0.0, freq: 0, t: 0)
        for i in 5..<CatPose.tailCount {
            p.tail[i].y += 0.22 * sin(t * CM.tau * 2.1 - Float(i) * 0.6)
        }
        p.lookWeight = 0.3
        return p
    }

    static func pounce(_ t: Float) -> CatPose {
        let crouch0 = crouch(0.9)
        var air = stand()
        let s = CM.sat((t - 0.3) / 0.42)
        air.bodyPos.y = 0.31 + 0.2 * sin(CM.pi * s)
        air.body.z = CM.mix(0.28, -0.3, s)
        air.neck.z = CM.mix(-0.2, 0.25, s)
        air.feet[0] = SIMD3(0.36, g + 0.15, -0.07)
        air.feet[1] = SIMD3(0.38, g + 0.17, 0.07)
        air.feet[2] = SIMD3(-0.32, g + 0.12, -0.09)
        air.feet[3] = SIMD3(-0.3, g + 0.1, 0.09)
        air.pawTilt = [0.5, 0.5, -1.2, -1.2]
        air.groundClamp = 0
        tail(&air, base: 0.3, curl: -0.02, tip: 0.1, sway: 0, freq: 0, t: 0)
        air.face.pupil = 1
        air.face.lidUpper = 0
        air.face.jaw = 0.25
        air.faceWeight = 1
        air.earL.z = -0.1
        air.earR.z = -0.1
        var land = crouchBase()
        land.bodyPos = SIMD3(0.0, 0.18, 0)
        land.body.z = -0.18
        land.feet[0] = SIMD3(0.27, g, -0.04)
        land.feet[1] = SIMD3(0.28, g, 0.04)
        land.pawTilt = [0.2, 0.2, 0, 0]
        land.neck.z = 0.0
        land.head.z = -0.25
        tail(&land, base: 0.25, curl: 0.06, tip: 0.2, sway: 0.1, freq: 2, t: t)
        let toAir = CM.ramp(t, 0.22, 0.36)
        let toLand = CM.ramp(t, 0.68, 0.82)
        var p = CatPose.mix(CatPose.mix(crouch0, air, toAir), land, toLand)
        // Anticipation: deeper crouch before take-off.
        let antic = CM.window(t, 0.0, 0.15, 0.22, 0.32)
        p.bodyPos.y -= 0.03 * antic
        p.hips.z += 0.1 * antic
        return p
    }

    static func bat(_ t: Float) -> CatPose {
        var p = crouchBase()
        p.bodyPos = SIMD3(-0.03, 0.215, 0)
        p.body.z = 0.12
        p.neck.z = -0.05
        p.head.z = -0.25
        let up = CM.ramp(t, 0.0, 0.25)
        let swipe = CM.ramp(t, 0.3, 0.45)
        let back = CM.ramp(t, 0.62, 0.9)
        let raised = SIMD3<Float>(0.27, 0.24, 0.1)
        let hit = SIMD3<Float>(0.4, g + 0.01, 0.0)
        var paw = CM.mix(p.feet[1], raised, up)
        paw = CM.mix(paw, hit, swipe)
        paw = CM.mix(paw, p.feet[1], back)
        p.feet[1] = paw
        p.pawTilt[1] = 0.8 * up * (1 - swipe)
        tail(&p, base: 0.3, curl: 0.05, tip: 0.25, sway: 0.15, freq: 2.5, t: t)
        return p
    }

    // MARK: Care

    static func eat(_ t: Float) -> CatPose {
        var p = stand()
        p.bodyPos = SIMD3(-0.04, 0.235, 0)
        p.body.z = -0.3
        p.chest.z = -0.1
        p.hips.z = 0.12
        p.neck.z = -0.7
        p.head.z = -0.45
        p.feet[0] = SIMD3(0.13, g, -0.075)
        p.feet[1] = SIMD3(0.13, g, 0.075)
        p.feet[2] = SIMD3(-0.16, g, -0.09)
        p.feet[3] = SIMD3(-0.16, g, 0.09)
        let chew = sin(t * CM.tau * 2.6)
        p.head.z += 0.05 * chew
        p.neck.z += 0.025 * sin(t * CM.tau * 0.4)
        p.head.x = 0.06 * sin(t * 0.8)
        p.face.jaw = 0.18 + 0.16 * max(0, chew)
        p.face.lidUpper = 0.55
        p.face.pupil = 0.7
        p.faceWeight = 1
        tail(&p, base: 0.75, curl: 0.12, tip: 0.25, sway: 0.08, freq: 0.6, t: t)
        p.lookWeight = 0
        return p
    }

    static func purr(_ t: Float) -> CatPose {
        var p = sitBase()
        let rub = sin(t * CM.tau * 0.45)
        p.head.x = 0.28 * rub
        p.neck.y = 0.22 * rub
        p.head.z += 0.12 + 0.04 * sin(t * CM.tau * 0.9)
        p.body.x = 0.04 * rub
        // Purr vibration.
        p.bodyPos.y += 0.0018 * sin(t * CM.tau * 24)
        p.face.lidUpper = 0.95
        p.face.lidLower = 0.6
        p.face.blush = 1
        p.face.jaw = 0.0
        p.faceWeight = 1
        p.earL.x = 0.2
        p.earR.x = 0.2
        tail(&p, base: 1.45, curl: 0.03, tip: 0.35, sway: 0.03, freq: 0.6, t: t)
        for i in 0..<CatPose.tailCount {
            p.tail[i].y += 0.012 * sin(t * CM.tau * 9 + Float(i))
        }
        p.lookWeight = 0.3
        return p
    }

    // MARK: Emotions

    static func surprised(_ t: Float) -> CatPose {
        let base = stand()
        var arch = stand()
        arch.bodyPos = SIMD3(0, 0.37, 0)
        arch.chest.z = -0.55
        arch.hips.z = 0.55
        arch.neck.z = 0.6
        arch.head.z = 0.05
        arch.feet[0] = SIMD3(0.17, g, -0.075)
        arch.feet[1] = SIMD3(0.17, g, 0.075)
        arch.feet[2] = SIMD3(-0.13, g, -0.09)
        arch.feet[3] = SIMD3(-0.13, g, 0.09)
        arch.puff = 1
        tail(&arch, base: 1.55, curl: -0.03, tip: 0.05, sway: 0, freq: 0, t: 0)
        arch.earL.z = 0.55
        arch.earR.z = 0.55
        arch.earL.x = 0.35
        arch.earR.x = 0.35
        arch.face.pupil = 1
        arch.face.lidUpper = 0
        arch.face.jaw = 0.35
        arch.faceWeight = 1
        arch.lookWeight = 0
        let into = CM.ramp(t, 0.0, 0.18)
        let out = CM.ramp(t, 1.2, 1.7)
        var p = CatPose.mix(CatPose.mix(base, arch, into), base, out)
        // Startle hop.
        let hop = CM.sat((t - 0.06) / 0.34)
        p.bodyPos.y += 0.12 * sin(CM.pi * hop) * (hop < 1 ? 1 : 0)
        if hop > 0, hop < 1 {
            let lift = 0.12 * sin(CM.pi * hop)
            for i in 0..<4 { p.feet[i].y += lift }
            p.groundClamp = 0
        }
        return p
    }

    static func jump(_ t: Float) -> CatPose {
        let base = stand()
        var squat = stand()
        squat.bodyPos.y = 0.24
        squat.body.z = 0.05
        squat.neck.z = -0.1
        var air = stand()
        let s = CM.sat((t - 0.28) / 0.5)
        let h = 0.3 * sin(CM.pi * s)
        air.bodyPos.y = 0.33 + h
        air.body.z = 0.25 * cos(CM.pi * s)
        air.feet[0] = SIMD3(0.24, 0.13 + h, -0.07)
        air.feet[1] = SIMD3(0.22, 0.16 + h, 0.07)
        air.feet[2] = SIMD3(-0.2, 0.06 + h, -0.09)
        air.feet[3] = SIMD3(-0.2, 0.07 + h, 0.09)
        air.pawTilt = [-0.8, -0.8, -0.8, -0.8]
        air.groundClamp = 0
        air.neck.z = 0.15
        tail(&air, base: 1.5, curl: 0.06, tip: 0.3, sway: 0.1, freq: 2, t: t)
        air.face.lidUpper = 0.0
        air.face.lidLower = 0.35
        air.face.pupil = 1
        air.face.jaw = 0.45
        air.faceWeight = 1
        air.earL.z = -0.1
        air.earR.z = -0.1
        let a = CM.ramp(t, 0.0, 0.22)
        let b = CM.ramp(t, 0.22, 0.34)
        let c = CM.ramp(t, 0.72, 0.85)
        let d = CM.ramp(t, 0.85, 1.25)
        var p = CatPose.mix(base, squat, a)
        p = CatPose.mix(p, air, b)
        p = CatPose.mix(p, squat, c)
        p = CatPose.mix(p, base, d)
        p.face.lidLower = max(p.face.lidLower, 0.3)
        p.faceWeight = max(p.faceWeight, 0.8)
        return p
    }

    static func spin(_ t: Float) -> CatPose {
        var p = trot(t * 2.6, t)
        p.body.x += -0.12 * CM.window(t, 0.1, 0.3, 1.2, 1.4)
        p.face.lidLower = 0.3
        p.face.jaw = 0.3
        p.faceWeight = 1
        return p
    }

    static func meow(_ t: Float) -> CatPose {
        var p = sitBase()
        let open = CM.window(t, 0.25, 0.5, 0.9, 1.25)
        p.neck.z += 0.2
        p.head.z += 0.3 + 0.08 * open
        p.head.x = 0.12 * sin(t * 1.4)
        p.face.jaw = 0.85 * open
        p.face.tongue = 0.0
        p.face.pupil = 0.9
        p.face.lidUpper = CM.mix(0.05, 0.35, open)
        p.face.gaze.y = 0.4
        p.faceWeight = 1
        p.earL.z = -0.05 + 0.15 * open
        p.earR.z = -0.05 + 0.15 * open
        p.earL.x = 0.12 * open
        p.earR.x = 0.12 * open
        tail(&p, base: 1.4, curl: 0.04, tip: 0.3, sway: 0.03, freq: 1.2, t: t)
        p.lookWeight = 0.4
        return p
    }

    /// Peeking over an edge: upright, paws resting forward.
    static func peek(_ t: Float) -> CatPose {
        var p = CatPose()
        p.bodyPos = SIMD3(0, 0.3, 0)
        p.body.z = 1.15
        p.neck.z = -0.75
        p.head.z = -0.38
        p.feetGround = 0
        p.feet = [SIMD3(0.13, -0.04, 0.02), SIMD3(0.13, -0.04, -0.02), SIMD3(0.06, -0.2, 0), SIMD3(0.06, -0.2, 0)]
        p.pawTilt = [1.0, 1.0, 0, 0]
        p.groundClamp = 0
        tail(&p, base: -0.5, curl: 0.1, tip: 0.2, sway: 0.05, freq: 0.5, t: t)
        p.face.pupil = 0.9
        p.face.lidUpper = 0.05
        p.faceWeight = 0.6
        return p
    }
}
