import Foundation
import simd

/// Small math helpers for the procedural cat (namespaced to avoid clashes with other modules).
enum CM {
    static let pi: Float = .pi
    static let tau: Float = 2 * .pi

    @inline(__always) static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    @inline(__always) static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
    @inline(__always) static func mix(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> { a + (b - a) * t }
    @inline(__always) static func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float { min(max(x, lo), hi) }
    @inline(__always) static func sat(_ x: Float) -> Float { min(max(x, 0), 1) }

    /// Smoothstep on 0...1.
    static func ease(_ x: Float) -> Float {
        let t = sat(x)
        return t * t * (3 - 2 * t)
    }

    /// 0 → 1 over [a, b] with smoothstep.
    static func ramp(_ x: Float, _ a: Float, _ b: Float) -> Float {
        ease((x - a) / (b - a))
    }

    /// Rises over [a, b], holds, falls over [c, d].
    static func window(_ x: Float, _ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
        ramp(x, a, b) * (1 - ramp(x, c, d))
    }

    /// Fractional part, always positive.
    static func fract(_ x: Float) -> Float { x - floor(x) }

    static func wrapAngle(_ a: Float) -> Float {
        var x = a
        while x > pi { x -= tau }
        while x < -pi { x += tau }
        return x
    }

    /// Deterministic hash → 0...1.
    static func hash(_ n: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: n &* 374_761_393 &+ 668_265_263)
        x = (x ^ (x >> 13)) &* 1_274_126_177
        x = x ^ (x >> 16)
        return Float(x & 0xFFFFFF) / Float(0xFFFFFF)
    }

    /// Smooth deterministic 1D noise in -1...1 (sum of incommensurate sines).
    static func wobble(_ t: Float, seed: Float = 0) -> Float {
        let a = sin(t * 1.0 + seed * 1.7)
        let b = sin(t * 2.31 + seed * 3.1) * 0.5
        let c = sin(t * 0.57 + seed * 5.3) * 0.7
        return (a + b + c) / 2.2
    }

    static func quat(_ e: SIMD3<Float>) -> simd_quatf {
        // e.x = roll about X, e.y = yaw about Y, e.z = pitch about Z (cat faces +X, so +z = nose up).
        let qy = simd_quatf(angle: e.y, axis: SIMD3<Float>(0, 1, 0))
        let qz = simd_quatf(angle: e.z, axis: SIMD3<Float>(0, 0, 1))
        let qx = simd_quatf(angle: e.x, axis: SIMD3<Float>(1, 0, 0))
        return qy * qz * qx
    }
}

/// Facial expression channels.
struct CatFaceState {
    /// 0 = open, 1 = closed.
    var lidUpper: Float = 0.08
    /// 0 = none, 1 = lower lid pushed up (happy squint).
    var lidLower: Float = 0
    /// 0 = slit, 1 = big round.
    var pupil: Float = 0.55
    /// Eye direction (x = yaw toward cat's left, y = up), -1...1.
    var gaze = SIMD2<Float>(0, 0)
    /// 0 = closed, 1 = wide open (meow / yawn).
    var jaw: Float = 0
    /// 0 = hidden, 1 = out.
    var tongue: Float = 0
    /// Pink cheeks.
    var blush: Float = 0

    static func mix(_ a: CatFaceState, _ b: CatFaceState, _ t: Float) -> CatFaceState {
        var r = CatFaceState()
        r.lidUpper = CM.mix(a.lidUpper, b.lidUpper, t)
        r.lidLower = CM.mix(a.lidLower, b.lidLower, t)
        r.pupil = CM.mix(a.pupil, b.pupil, t)
        r.gaze = CM.mix(a.gaze, b.gaze, t)
        r.jaw = CM.mix(a.jaw, b.jaw, t)
        r.tongue = CM.mix(a.tongue, b.tongue, t)
        r.blush = CM.mix(a.blush, b.blush, t)
        return r
    }
}

/// A full-body pose. Angles are radians; positions are in the cat's root frame
/// (x = forward, y = up, z = cat's right side), ground at y = 0.
struct CatPose {
    static let tailCount = 10
    static let groundY: Float = 0.032  // paw center height when standing on the ground

    /// Rest feet positions (root frame): front-left, front-right, hind-left, hind-right.
    static let restFeet: [SIMD3<Float>] = [
        SIMD3(0.19, groundY, -0.075), SIMD3(0.19, groundY, 0.075),
        SIMD3(-0.15, groundY, -0.085), SIMD3(-0.15, groundY, 0.085),
    ]
    static let standHeight: Float = 0.31

    var bodyPos = SIMD3<Float>(0, CatPose.standHeight, 0)
    var body = SIMD3<Float>(repeating: 0)
    var chest = SIMD3<Float>(repeating: 0)
    var hips = SIMD3<Float>(repeating: 0)
    var neck = SIMD3<Float>(repeating: 0)
    var head = SIMD3<Float>(repeating: 0)
    var earL = SIMD3<Float>(repeating: 0)
    var earR = SIMD3<Float>(repeating: 0)
    /// Per tail segment: x = lift (up), y = sway (toward the cat's left).
    var tail: [SIMD2<Float>] = CatPose.neutralTail()
    /// Paw targets. With `feetGround` = 1 they are in the root frame; with 0 they are offsets from the
    /// shoulder/hip joint in the chest/hips frame.
    var feet: [SIMD3<Float>] = CatPose.restFeet
    var feetGround: Float = 1
    /// Extra paw tilt per leg (positive = toes up).
    var pawTilt: [Float] = [0, 0, 0, 0]
    /// Breathing amount (0...1.5) and speed (cycles / s).
    var breathAmp: Float = 1
    var breathRate: Float = 0.33
    /// Fur puff (surprised): scales body + tail thickness.
    var puff: Float = 0
    /// Prevent the body from sinking below the floor.
    var groundClamp: Float = 1
    var face = CatFaceState()
    /// 0 = face from mood, 1 = face from this pose (behaviour overrides the mood).
    var faceWeight: Float = 0
    /// How much the user's look target may turn the head (0...1).
    var lookWeight: Float = 1

    static func neutralTail() -> [SIMD2<Float>] {
        var t = [SIMD2<Float>](repeating: SIMD2(0.13, 0), count: tailCount)
        t[0] = SIMD2(0.95, 0)
        return t
    }

    static func mix(_ a: CatPose, _ b: CatPose, _ t: Float) -> CatPose {
        if t <= 0 { return a }
        if t >= 1 { return b }
        var r = a
        r.bodyPos = CM.mix(a.bodyPos, b.bodyPos, t)
        r.body = CM.mix(a.body, b.body, t)
        r.chest = CM.mix(a.chest, b.chest, t)
        r.hips = CM.mix(a.hips, b.hips, t)
        r.neck = CM.mix(a.neck, b.neck, t)
        r.head = CM.mix(a.head, b.head, t)
        r.earL = CM.mix(a.earL, b.earL, t)
        r.earR = CM.mix(a.earR, b.earR, t)
        for i in 0..<tailCount { r.tail[i] = CM.mix(a.tail[i], b.tail[i], t) }
        for i in 0..<4 {
            r.feet[i] = CM.mix(a.feet[i], b.feet[i], t)
            r.pawTilt[i] = CM.mix(a.pawTilt[i], b.pawTilt[i], t)
        }
        r.feetGround = CM.mix(a.feetGround, b.feetGround, t)
        r.breathAmp = CM.mix(a.breathAmp, b.breathAmp, t)
        r.breathRate = CM.mix(a.breathRate, b.breathRate, t)
        r.puff = CM.mix(a.puff, b.puff, t)
        r.groundClamp = CM.mix(a.groundClamp, b.groundClamp, t)
        r.face = CatFaceState.mix(a.face, b.face, t)
        r.faceWeight = CM.mix(a.faceWeight, b.faceWeight, t)
        r.lookWeight = CM.mix(a.lookWeight, b.lookWeight, t)
        return r
    }
}
