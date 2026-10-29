import Metal
import SceneKit
import UIKit
import simd

/// Renders every `MurzikSprite` pose of 3D Murzik offscreen into square transparent images that follow
/// the contract in `Shared/Character/MurzikSprite.swift` (192×192 px, side views face right, feet on the
/// bottom edge, centered). Deterministic: the same sprite always renders the same image.
final class MurzikSpriteRenderer {
    struct Spec {
        var behavior: CatBehavior
        var t: Float
        var gait: Float = 0
        var mood: MurzikMood = .idle
        /// Camera azimuth from the cat's front toward its right side (π/2 = side view facing right).
        var azimuth: Float
        var elevation: Float
        var lookAtCamera = false
        var modify: ((inout CatPose) -> Void)?
        /// FX nodes placed relative to the head (kind, offset, scale).
        var fx: [(MurzikStage.FXKind, SIMD3<Float>, Float)] = []
        var sizeBoost: Float = 1
    }

    static let pixels = Int(MurzikSprite.exportPoints * MurzikSprite.exportScale)   // 192
    static let rawPixels = 576
    static let rawHalfHeight: Float = 0.9
    /// Final pixels per scene unit (same for all sprites so Murzik keeps his size across poses).
    static let finalPixelsPerUnit: Float = 172
    static let bottomMargin: CGFloat = 0.04

    let engine: MurzikEngine
    private let renderer: SCNRenderer
    private let target = SIMD3<Float>(0, 0.35, 0)

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        engine = MurzikEngine(stageConfig: .sprite, style: .sprite, autonomous: false)
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = engine.scene
        renderer.pointOfView = engine.cameraNode
        renderer.autoenablesDefaultLighting = false
    }

    // MARK: Specs

    static func spec(for sprite: MurzikSprite) -> Spec {
        let side: Float = 1.22  // side view facing right, turned slightly toward the viewer
        let q: Float = 0.66
        switch sprite {
        case .walk0, .walk1, .walk2, .walk3, .walk4, .walk5, .walk6, .walk7:
            let i = Float(MurzikSprite.walkCycle.firstIndex(of: sprite) ?? 0)
            return Spec(behavior: .walk, t: i / 8 / 1.25, gait: i / 8, mood: .idle, azimuth: side, elevation: 0.05,
                        modify: { p in p.face.gaze = SIMD2(0, 0.05) })
        case .sitFront:
            return Spec(behavior: .sit, t: 0, mood: .idle, azimuth: q, elevation: 0.14, lookAtCamera: true)
        case .sitSide:
            return Spec(behavior: .sit, t: 0, mood: .idle, azimuth: side, elevation: 0.05,
                        modify: { p in p.neck.y = 0; p.head.y = 0; p.head.x = 0 })
        case .happy:
            return Spec(behavior: .sit, t: 0, mood: .happy, azimuth: q, elevation: 0.14, lookAtCamera: true,
                        modify: { p in Poses.tail(&p, base: 1.45, curl: 0.05, tip: 0.38, sway: 0, freq: 0, t: 0) })
        case .loving:
            return Spec(behavior: .purr, t: 0.55, mood: .loving, azimuth: q, elevation: 0.14,
                        fx: [(.heart, SIMD3(0.02, 0.27, 0.1), 1.25)])
        case .hungry:
            return Spec(behavior: .meow, t: 0.7, mood: .hungry, azimuth: q, elevation: 0.12, lookAtCamera: true)
        case .sleepy:
            return Spec(behavior: .loaf, t: 0, mood: .sleepy, azimuth: q, elevation: 0.2, lookAtCamera: true)
        case .sleeping:
            return Spec(behavior: .sleep, t: 0, mood: .sleeping, azimuth: q, elevation: 0.45,
                        fx: [(.zzz, SIMD3(0.06, 0.2, 0.05), 1.3)])
        case .playful:
            return Spec(behavior: .crouch, t: 0.9, mood: .playful, azimuth: side, elevation: 0.05)
        case .surprised:
            return Spec(behavior: .surprised, t: 0.7, mood: .surprised, azimuth: 1.05, elevation: 0.1)
        case .excited:
            return Spec(behavior: .jump, t: 0.53, mood: .excited, azimuth: q, elevation: 0.12, lookAtCamera: true)
        case .groom:
            return Spec(behavior: .groom, t: 1.1, mood: .idle, azimuth: 0.75, elevation: 0.12)
        case .stretch:
            return Spec(behavior: .stretch, t: 1.35, mood: .idle, azimuth: side, elevation: 0.05)
        case .peek:
            return Spec(behavior: .peek, t: 0, mood: .idle, azimuth: 0.12, elevation: 0.08, lookAtCamera: true, sizeBoost: 1.25)
        }
    }

    // MARK: Rendering

    private struct Raw {
        let image: CGImage
        let bounds: CGRect
        let cutRow: CGFloat?
    }

    private var rawPixelsPerUnit: Float { Float(MurzikSpriteRenderer.rawPixels) / (2 * MurzikSpriteRenderer.rawHalfHeight) }

    /// Pixel row (from the top) of a world point in the raw orthographic render.
    private func row(of p: SIMD3<Float>) -> CGFloat {
        let up = engine.cameraNode.simdWorldUp
        let d = simd_dot(p - target, up)
        return CGFloat(Float(MurzikSpriteRenderer.rawPixels) / 2 - d * rawPixelsPerUnit)
    }

    private func renderRaw(_ spec: Spec, sprite: MurzikSprite) -> Raw? {
        engine.clearStaticFX()
        engine.stage.aim(azimuth: spec.azimuth, elevation: spec.elevation, distance: 4, target: target)
        engine.cameraNode.camera?.usesOrthographicProjection = true
        engine.cameraNode.camera?.orthographicScale = Double(MurzikSpriteRenderer.rawHalfHeight)
        let cam = engine.cameraNode.simdWorldPosition
        engine.setStaticPose(spec.behavior, t: spec.t, gait: spec.gait, mood: spec.mood,
                             lookAt: spec.lookAtCamera ? cam : nil, modify: spec.modify)
        let head = engine.rig.headWorld
        for (kind, offset, scale) in spec.fx {
            engine.addStaticFX(kind, at: head + offset, scale: scale)
        }
        let n = MurzikSpriteRenderer.rawPixels
        let img = renderer.snapshot(atTime: 0, with: CGSize(width: n, height: n), antialiasingMode: .multisampling4X)
        guard let cg = img.cgImage, let bounds = MurzikSpriteRenderer.alphaBounds(cg) else { return nil }
        // Rescale bounds if the snapshot is not exactly n px.
        let sx = CGFloat(cg.width) / CGFloat(n)
        var cut: CGFloat?
        if sprite == .peek {
            let paw = max(engine.rig.pawWorld(0).y, engine.rig.pawWorld(1).y)
            cut = (row(of: SIMD3(0, paw - 0.035, 0) + SIMD3(engine.rig.pawWorld(0).x, 0, engine.rig.pawWorld(0).z))) * sx
        }
        return Raw(image: cg, bounds: bounds, cutRow: cut)
    }

    /// Renders one sprite (192×192, transparent).
    func render(_ sprite: MurzikSprite) -> UIImage? {
        if MurzikSprite.walkCycle.contains(sprite) {
            return renderWalkCycle()[sprite]
        }
        let spec = MurzikSpriteRenderer.spec(for: sprite)
        guard let raw = renderRaw(spec, sprite: sprite) else { return nil }
        var rect = raw.bounds
        var bottomMargin = MurzikSpriteRenderer.bottomMargin
        if let cut = raw.cutRow, cut > rect.minY + 10, cut < rect.maxY {
            rect.size.height = cut - rect.minY
            bottomMargin = 0
        }
        return compose(raw.image, crop: rect, boost: spec.sizeBoost, bottomMargin: bottomMargin)
    }

    /// Renders the 8 walk frames with one shared crop so the loop doesn't jitter.
    func renderWalkCycle() -> [MurzikSprite: UIImage] {
        var raws: [(MurzikSprite, Raw)] = []
        for s in MurzikSprite.walkCycle {
            if let r = renderRaw(MurzikSpriteRenderer.spec(for: s), sprite: s) { raws.append((s, r)) }
        }
        guard let first = raws.first else { return [:] }
        let union = raws.dropFirst().reduce(first.1.bounds) { $0.union($1.1.bounds) }
        var out: [MurzikSprite: UIImage] = [:]
        for (s, r) in raws {
            out[s] = compose(r.image, crop: union, boost: 1, bottomMargin: MurzikSpriteRenderer.bottomMargin)
        }
        return out
    }

    func renderAll() -> [MurzikSprite: UIImage] {
        var out = renderWalkCycle()
        for s in MurzikSprite.allCases where !MurzikSprite.walkCycle.contains(s) {
            if let img = render(s) { out[s] = img }
        }
        return out
    }

    private func compose(_ image: CGImage, crop: CGRect, boost: Float, bottomMargin: CGFloat) -> UIImage? {
        let size = CGFloat(MurzikSpriteRenderer.pixels)
        let rawScaleFix = CGFloat(image.width) / CGFloat(MurzikSpriteRenderer.rawPixels)
        var k = CGFloat(MurzikSpriteRenderer.finalPixelsPerUnit / rawPixelsPerUnit * boost) / rawScaleFix
        let maxW = size * 0.96
        let maxH = size * (1 - bottomMargin - 0.02)
        k = min(k, maxW / crop.width, maxH / crop.height)
        guard let cropped = image.cropping(to: crop.integral) else { return nil }
        let w = CGFloat(cropped.width) * k
        let h = CGFloat(cropped.height) * k
        let dest = CGRect(x: (size - w) / 2, y: size * (1 - bottomMargin) - h, width: w, height: h)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIImage(cgImage: cropped).draw(in: dest)
        }
    }

    /// Bounding box (top-left origin, pixels) of pixels with alpha above a threshold.
    static func alphaBounds(_ cg: CGImage, threshold: UInt8 = 6) -> CGRect? {
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let rowBase = y * w * 4
            for x in 0..<w where data[rowBase + x * 4 + 3] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
