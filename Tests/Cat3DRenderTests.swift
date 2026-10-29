import Metal
import SceneKit
import UIKit
import XCTest
@testable import Murzik

/// Hero renders of 3D Murzik (behaviours, moods, angles) into `$RENDER_DIR/3d/`, on light and dark
/// backgrounds, plus walk-cycle frames and sanity checks of the live engine and controller API.
@MainActor
final class Cat3DRenderTests: XCTestCase {
    private struct Shot {
        var name: String
        var behavior: CatBehavior
        var t: Float
        var gait: Float = 0
        var mood: MurzikMood = .idle
        var azimuth: Float
        var elevation: Float = 0.22
        var distance: Float = 2.7
        var look = false
        var bowl = false
        var toy = false
        var fx: [(MurzikStage.FXKind, SIMD3<Float>)] = []
    }

    private func makeRenderer(_ engine: MurzikEngine) throws -> SCNRenderer {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Metal unavailable")
        let r = SCNRenderer(device: device, options: nil)
        r.scene = engine.scene
        r.pointOfView = engine.cameraNode
        r.autoenablesDefaultLighting = false
        return r
    }

    private func snapshot(_ r: SCNRenderer, size: Int) throws -> UIImage {
        let img = r.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)
        let cg = try XCTUnwrap(img.cgImage)
        XCTAssertNotNil(MurzikSpriteRenderer.alphaBounds(cg), "render is empty")
        XCTAssertEqual(SpriteExportTests.alpha(cg, x: 2, y: 2), 0, "background should be transparent")
        return img
    }

    /// Composites a transparent render on a cream and on a near-black background, side by side.
    private func lightDark(_ img: UIImage, size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size * 2, height: size), format: format).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let light = [UIColor(red: 0.99, green: 0.96, blue: 0.92, alpha: 1).cgColor, UIColor(red: 0.94, green: 0.88, blue: 0.81, alpha: 1).cgColor]
            let dark = [UIColor(red: 0.13, green: 0.12, blue: 0.15, alpha: 1).cgColor, UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1).cgColor]
            for (i, colors) in [light, dark].enumerated() {
                let x = CGFloat(i) * size
                c.saveGState()
                c.clip(to: CGRect(x: x, y: 0, width: size, height: size))
                if let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) {
                    c.drawLinearGradient(g, start: CGPoint(x: x, y: 0), end: CGPoint(x: x, y: size), options: [])
                }
                c.restoreGState()
                img.draw(in: CGRect(x: x, y: 0, width: size, height: size))
            }
        }
    }

    private func save(_ img: UIImage, _ name: String) throws {
        let data = try XCTUnwrap(img.pngData())
        try data.write(to: SpriteExportTests.dir("3d").appendingPathComponent("\(name).png"))
    }

    func testHeroRenders() throws {
        let engine = MurzikEngine(autonomous: false)
        let r = try makeRenderer(engine)
        let q: Float = 0.62
        let shots: [Shot] = [
            Shot(name: "hero-sit-happy", behavior: .sit, t: 0, mood: .happy, azimuth: q, look: true),
            Shot(name: "hero-idle-stand", behavior: .idle, t: 2.0, azimuth: 0.95, look: true),
            Shot(name: "hero-walk-side", behavior: .walk, t: 0.3, gait: 0.3, azimuth: .pi / 2, elevation: 0.12),
            Shot(name: "hero-trot", behavior: .trot, t: 0.2, gait: 0.2, mood: .playful, azimuth: 1.25, elevation: 0.15),
            Shot(name: "hero-sleep-curled", behavior: .sleep, t: 0, mood: .sleeping, azimuth: 0.7, elevation: 0.6, distance: 2.4,
                 fx: [(.zzz, SIMD3(0.06, 0.2, 0.05)), (.zzz, SIMD3(0.14, 0.34, 0.02))]),
            Shot(name: "hero-loaf-sleepy", behavior: .loaf, t: 0, mood: .sleepy, azimuth: q, look: true),
            Shot(name: "hero-groom", behavior: .groom, t: 1.1, azimuth: 0.8),
            Shot(name: "hero-wipe-face", behavior: .groom, t: 2.6, azimuth: 0.5),
            Shot(name: "hero-stretch-yawn", behavior: .stretch, t: 1.35, azimuth: 1.1, elevation: 0.15),
            Shot(name: "hero-eat", behavior: .eat, t: 0.3, mood: .happy, azimuth: 1.0, elevation: 0.3, bowl: true),
            Shot(name: "hero-purr-hearts", behavior: .purr, t: 0.55, mood: .loving, azimuth: q,
                 fx: [(.heart, SIMD3(0.03, 0.27, 0.1)), (.heart, SIMD3(-0.08, 0.4, -0.05))]),
            Shot(name: "hero-crouch-toy", behavior: .crouch, t: 0.9, mood: .playful, azimuth: 1.2, elevation: 0.18, toy: true),
            Shot(name: "hero-pounce", behavior: .pounce, t: 0.5, mood: .playful, azimuth: .pi / 2, elevation: 0.1),
            Shot(name: "hero-surprised", behavior: .surprised, t: 0.7, mood: .surprised, azimuth: 1.1, elevation: 0.12),
            Shot(name: "hero-jump-excited", behavior: .jump, t: 0.53, mood: .excited, azimuth: q, look: true),
            Shot(name: "hero-meow-hungry", behavior: .meow, t: 0.7, mood: .hungry, azimuth: q, look: true),
            Shot(name: "hero-lie", behavior: .lie, t: 0, azimuth: q, look: true),
            Shot(name: "hero-front", behavior: .sit, t: 0, azimuth: 0.0, elevation: 0.12, look: true),
            Shot(name: "diag-top-sit", behavior: .sit, t: 0, azimuth: 0.6, elevation: 1.4),
            Shot(name: "diag-top-sleep", behavior: .sleep, t: 0, mood: .sleeping, azimuth: 0.6, elevation: 1.4),
            Shot(name: "diag-top-loaf", behavior: .loaf, t: 0, azimuth: 0.6, elevation: 1.4),
        ]
        let size = 1000
        for shot in shots {
            engine.clearStaticFX()
            engine.stage.aim(azimuth: shot.azimuth, elevation: shot.elevation, distance: shot.distance, target: SIMD3(0.02, 0.3, 0))
            let cam = engine.cameraNode.simdWorldPosition
            engine.setStaticPose(shot.behavior, t: shot.t, gait: shot.gait, mood: shot.mood, lookAt: shot.look ? cam : nil)
            engine.showBowl(at: shot.bowl ? SIMD2(0.36, 0) : nil, fill: 0.8)
            engine.showToy(at: shot.toy ? SIMD2(0.62, 0.05) : nil)
            let head = engine.rig.headWorld
            for (kind, offset) in shot.fx { engine.addStaticFX(kind, at: head + offset, scale: 1.1) }
            let img = try snapshot(r, size: size)
            try save(lightDark(img, size: CGFloat(size)), shot.name)
        }
        engine.showBowl(at: nil)
        engine.showToy(at: nil)
    }

    func testWalkCycleStrip() throws {
        let engine = MurzikEngine(autonomous: false)
        let r = try makeRenderer(engine)
        let n = 8
        let cell = 420
        var frames: [UIImage] = []
        for i in 0..<n {
            engine.stage.aim(azimuth: .pi / 2, elevation: 0.1, distance: 2.6, target: SIMD3(0, 0.3, 0))
            let g = Float(i) / Float(n)
            engine.setStaticPose(.walk, t: g / 1.25, gait: g)
            frames.append(try snapshot(r, size: cell))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let strip = UIGraphicsImageRenderer(size: CGSize(width: cell * n, height: cell * 2), format: format).image { ctx in
            UIColor(red: 0.97, green: 0.93, blue: 0.88, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: cell * n, height: cell))
            UIColor(white: 0.05, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: cell, width: cell * n, height: cell))
            for (i, f) in frames.enumerated() {
                f.draw(in: CGRect(x: i * cell, y: 0, width: cell, height: cell))
                f.draw(in: CGRect(x: i * cell, y: cell, width: cell, height: cell))
            }
        }
        try save(strip, "walk-cycle")
    }

    func testTrotAndStretchStrips() throws {
        let engine = MurzikEngine(autonomous: false)
        let r = try makeRenderer(engine)
        let cell = 360
        func strip(_ name: String, _ frames: [(CatBehavior, Float, Float, MurzikMood)], azimuth: Float) throws {
            var imgs: [UIImage] = []
            for (b, t, g, m) in frames {
                engine.stage.aim(azimuth: azimuth, elevation: 0.12, distance: 2.7, target: SIMD3(0, 0.32, 0))
                engine.setStaticPose(b, t: t, gait: g, mood: m)
                imgs.append(try snapshot(r, size: cell))
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let out = UIGraphicsImageRenderer(size: CGSize(width: cell * imgs.count, height: cell), format: format).image { ctx in
                UIColor(red: 0.2, green: 0.2, blue: 0.24, alpha: 1).setFill()
                ctx.cgContext.fill(CGRect(x: 0, y: 0, width: cell * imgs.count, height: cell))
                for (i, f) in imgs.enumerated() { f.draw(in: CGRect(x: i * cell, y: 0, width: cell, height: cell)) }
            }
            try save(out, name)
        }
        try strip("trot-cycle", (0..<6).map { i in (CatBehavior.trot, Float(i) / 6 / 2.4, Float(i) / 6, MurzikMood.playful) }, azimuth: .pi / 2)
        try strip("stretch-sequence", [0.2, 0.8, 1.3, 2.2, 2.6, 3.4].map { (CatBehavior.stretch, Float($0), Float(0), MurzikMood.idle) }, azimuth: 1.2)
        try strip("pounce-sequence", [0.1, 0.3, 0.45, 0.6, 0.8, 1.1].map { (CatBehavior.pounce, Float($0), Float(0), MurzikMood.playful) }, azimuth: .pi / 2)
        try strip("moods-faces", MurzikMood.allCases.map { (CatBehavior.sit, Float(0), Float(0), $0) }, azimuth: 0.35)
    }

    /// Runs the autonomous engine for simulated minutes with mood changes and actions; checks stability.
    func testAutonomousLifeSimulation() throws {
        let engine = MurzikEngine()
        var t = 1000.0
        let moods: [MurzikMood] = [.idle, .playful, .hungry, .sleepy, .sleeping, .happy, .loving, .excited, .surprised, .idle]
        var seen = Set<String>()
        for (i, m) in moods.enumerated() {
            engine.send(.mood(m))
            if i == 2 { engine.send(.action(.feed)) }
            if i == 5 { engine.send(.action(.play)) }
            if i == 6 { engine.send(.action(.pet)) }
            if i == 7 { engine.send(.action(.wake)) }
            for _ in 0..<(30 * 20) {
                t += 1.0 / 30
                engine.tick(systemTime: t)
                seen.insert(engine.currentBehavior.rawValue)
            }
            let p = engine.rig.root.simdPosition
            XCTAssertFalse(p.x.isNaN || p.z.isNaN, "NaN position")
            XCTAssertLessThan(simd_length(SIMD2(p.x, p.z)), 1.0, "left the rug")
            let h = engine.rig.headWorld
            XCTAssertFalse(h.x.isNaN || h.y.isNaN, "NaN pose")
        }
        print("Behaviours seen: \(seen.sorted())")
        XCTAssertGreaterThanOrEqual(seen.count, 8, "too few behaviours: \(seen)")
        // Render the final live frame.
        let r = try makeRenderer(engine)
        let img = try snapshot(r, size: 700)
        try save(lightDark(img, size: 700), "live-final-frame")
    }

    func testControllerAPI() throws {
        let c = Murzik3DController()
        var petted = 0
        c.onPetted = { petted += 1 }
        for m in MurzikMood.allCases { c.setMood(m) }
        XCTAssertEqual(c.mood, MurzikMood.allCases.last)
        for a in PetAction.allCases { c.perform(a) }
        c.lookAt(normalizedPoint: CGPoint(x: 0.2, y: 0.3))
        c.lookAt(normalizedPoint: nil)
        c.orbit(byYaw: 5, pitch: 5)
        XCTAssertLessThanOrEqual(c.orbitYaw, 0.7)
        c.userPetted()
        XCTAssertEqual(petted, 1)
        c.setRugVisible(false)
        XCTAssertTrue(c.engine.stage.rug.isHidden)
        for i in 0..<60 { c.engine.tick(systemTime: Double(i) / 30) }
    }
}
