import SceneKit
import UIKit
import simd

/// Lights, camera, rug, shadow floor, props (bowl, yarn ball) and floating FX (hearts, Zs).
final class MurzikStage {
    struct Config {
        var showsStage = true
        var isSprite = false
        static let app = Config()
        static let sprite = Config(showsStage: false, isSprite: true)
    }

    let config: Config
    let cameraRig = SCNNode()
    let cameraNode = SCNNode()
    let lights = SCNNode()
    let rug = SCNNode()
    let floor = SCNNode()
    let bowl = SCNNode()
    let food = SCNNode()
    let toy = SCNNode()
    let fxRoot = SCNNode()
    private var keyLight = SCNLight()

    static let rugRadius: Float = 1.05

    init(scene: SCNScene, config: Config) {
        self.config = config
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = MurzikStage.environmentImage()
        scene.lightingEnvironment.intensity = config.isSprite ? 0.9 : 1.0

        let cam = SCNCamera()
        cam.fieldOfView = 28
        cam.zNear = 0.05
        cam.zFar = 60
        cam.wantsHDR = false
        if config.isSprite {
            cam.usesOrthographicProjection = true
            cam.orthographicScale = 0.8
        }
        cameraNode.camera = cam
        cameraNode.name = "murzik.camera"
        cameraRig.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraRig)
        cameraNode.addChildNode(lights)
        buildLights()

        if config.showsStage {
            buildFloor()
            buildRug()
            scene.rootNode.addChildNode(floor)
            scene.rootNode.addChildNode(rug)
            buildBowl()
            buildToy()
            scene.rootNode.addChildNode(bowl)
            scene.rootNode.addChildNode(toy)
        }
        scene.rootNode.addChildNode(fxRoot)
        setOrbit(yaw: 0, pitch: 0.3, distance: 3.6)
    }

    // MARK: Camera

    func setOrbit(yaw: Float, pitch: Float, distance: Float, target: SIMD3<Float> = SIMD3(0, 0.3, 0)) {
        cameraRig.simdPosition = target
        cameraRig.simdOrientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -pitch, axis: SIMD3(1, 0, 0))
        cameraNode.simdPosition = SIMD3(0, 0, distance)
        cameraNode.simdOrientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    }

    /// Places the camera looking at `target` from a direction given by azimuth (from the cat's front,
    /// toward its right side) and elevation, for a cat at the origin facing +X.
    func aim(azimuth: Float, elevation: Float, distance: Float, target: SIMD3<Float>) {
        let dir = SIMD3<Float>(cos(azimuth) * cos(elevation), sin(elevation), sin(azimuth) * cos(elevation))
        cameraRig.simdPosition = .zero
        cameraRig.simdOrientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        cameraNode.simdPosition = target + dir * distance
        cameraNode.simdLook(at: target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
    }

    // MARK: Lights

    private func directional(_ intensity: CGFloat, _ color: UIColor, yaw: Float, pitch: Float) -> SCNNode {
        let l = SCNLight()
        l.type = .directional
        l.intensity = intensity
        l.color = color
        let n = SCNNode()
        n.light = l
        n.simdOrientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
        lights.addChildNode(n)
        return n
    }

    private func buildLights() {
        let s = config.isSprite
        // Key: from upper left of the camera.
        // Key: from the upper left/front. Lives in the orbit rig (not the camera) so its shadow frustum
        // is centred on Murzik.
        let key = directional(s ? 1100 : 1000, UIColor(red: 1.0, green: 0.96, blue: 0.9, alpha: 1), yaw: 0, pitch: 0)
        key.removeFromParentNode()
        cameraRig.addChildNode(key)
        key.simdPosition = SIMD3(-0.9, 3.8, 1.3)
        key.simdLook(at: SIMD3(0, 0, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        keyLight = key.light!
        if config.showsStage {
            keyLight.castsShadow = true
            keyLight.shadowMode = .forward
            keyLight.shadowColor = UIColor(white: 0, alpha: 0.32)
            keyLight.automaticallyAdjustsShadowProjection = false
            keyLight.shadowRadius = 14
            keyLight.shadowSampleCount = 16
            keyLight.shadowMapSize = CGSize(width: 2048, height: 2048)
            keyLight.orthographicScale = 1.4
            keyLight.zNear = 0.1
            keyLight.zFar = 12
        }
        // Fill from the right, cool.
        _ = directional(s ? 380 : 300, UIColor(red: 0.8, green: 0.86, blue: 1.0, alpha: 1), yaw: 0.9, pitch: -0.2)
        // Rim / back lights (shine toward the camera).
        _ = directional(s ? 2600 : 1700, UIColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1), yaw: .pi + 0.55, pitch: -0.45)
        _ = directional(s ? 2000 : 1300, UIColor(red: 1.0, green: 0.92, blue: 0.85, alpha: 1), yaw: .pi - 0.6, pitch: -0.3)
        // Top light for a soft sheen on the head and back.
        _ = directional(s ? 600 : 450, .white, yaw: 0, pitch: -1.45)
        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = s ? 160 : 120
        amb.color = UIColor(red: 0.85, green: 0.86, blue: 0.95, alpha: 1)
        let an = SCNNode()
        an.light = amb
        lights.addChildNode(an)
    }

    /// Vertical gradient used as an image-based light (soft sky above, dark floor below).
    static func environmentImage() -> UIImage {
        let size = CGSize(width: 64, height: 32)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [
                UIColor(red: 0.85, green: 0.88, blue: 0.98, alpha: 1).cgColor,
                UIColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1).cgColor,
                UIColor(red: 0.12, green: 0.11, blue: 0.11, alpha: 1).cgColor,
            ]
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.5, 1]) {
                ctx.cgContext.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    /// Soft radial blob used as a contact shadow under the cat.
    static func contactShadow() -> SCNNode {
        let size = CGSize(width: 128, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0.0).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                let c = CGPoint(x: 64, y: 64)
                ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 64, options: [])
            }
        }
        let plane = SCNPlane(width: 1, height: 1)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.simdOrientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        n.castsShadow = false
        n.renderingOrder = 5   // after the opaque rug, depth-tested
        n.name = "murzik.contactShadow"
        return n
    }

    // MARK: Floor & rug

    private func buildFloor() {
        let f = SCNFloor()
        f.reflectivity = 0
        let m = SCNMaterial()
        m.lightingModel = .shadowOnly
        f.materials = [m]
        floor.geometry = f
        floor.name = "murzik.floor"
        floor.simdPosition = SIMD3(0, -0.025, 0)
    }

    private func buildRug() {
        let r = CGFloat(MurzikStage.rugRadius)
        let base = SCNCylinder(radius: r, height: 0.02)
        base.radialSegmentCount = 96
        base.materials = [MurzikRig.pbr(UIColor(red: 0.70, green: 0.52, blue: 0.50, alpha: 1), roughness: 0.95)]
        let baseN = SCNNode(geometry: base)
        baseN.simdPosition = SIMD3(0, -0.012, 0)
        rug.addChildNode(baseN)
        let ring = SCNTorus(ringRadius: r - 0.06, pipeRadius: 0.014)
        ring.ringSegmentCount = 120
        ring.pipeSegmentCount = 12
        ring.materials = [MurzikRig.pbr(UIColor(red: 0.85, green: 0.5, blue: 0.55, alpha: 1), roughness: 0.9)]
        let ringN = SCNNode(geometry: ring)
        ringN.simdPosition = SIMD3(0, -0.006, 0)
        ringN.simdScale = SIMD3(1, 0.5, 1)
        rug.addChildNode(ringN)
        let inner = SCNCylinder(radius: r * 0.68, height: 0.004)
        inner.radialSegmentCount = 96
        inner.materials = [MurzikRig.pbr(UIColor(red: 0.76, green: 0.60, blue: 0.56, alpha: 1), roughness: 0.95)]
        let innerN = SCNNode(geometry: inner)
        innerN.simdPosition = SIMD3(0, -0.0035, 0)
        rug.addChildNode(innerN)
        // Little paw-print dots around the inner circle.
        let dotMat = MurzikRig.pbr(UIColor(red: 0.62, green: 0.44, blue: 0.43, alpha: 1), roughness: 0.95)
        for i in 0..<12 {
            let a = Float(i) / 12 * CM.tau
            let d = SCNCylinder(radius: 0.022, height: 0.004)
            d.radialSegmentCount = 24
            d.materials = [dotMat]
            let dn = SCNNode(geometry: d)
            let rr = Float(r) * 0.84
            dn.simdPosition = SIMD3(cos(a) * rr, -0.002, sin(a) * rr)
            rug.addChildNode(dn)
        }
        rug.name = "murzik.rug"
    }

    // MARK: Props

    private func buildBowl() {
        let ceramic = MurzikRig.pbr(UIColor(red: 0.42, green: 0.6, blue: 0.92, alpha: 1), roughness: 0.28)
        let insideM = MurzikRig.pbr(UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1), roughness: 0.3)
        let tube = SCNTube(innerRadius: 0.105, outerRadius: 0.125, height: 0.065)
        tube.radialSegmentCount = 64
        tube.materials = [ceramic, insideM, ceramic, ceramic]
        let tn = SCNNode(geometry: tube)
        tn.simdPosition = SIMD3(0, 0.0325, 0)
        bowl.addChildNode(tn)
        let rim = SCNTorus(ringRadius: 0.115, pipeRadius: 0.012)
        rim.ringSegmentCount = 64
        rim.materials = [ceramic]
        let rn = SCNNode(geometry: rim)
        rn.simdPosition = SIMD3(0, 0.065, 0)
        bowl.addChildNode(rn)
        let bottom = SCNCylinder(radius: 0.108, height: 0.012)
        bottom.radialSegmentCount = 48
        bottom.materials = [insideM]
        let bn = SCNNode(geometry: bottom)
        bn.simdPosition = SIMD3(0, 0.008, 0)
        bowl.addChildNode(bn)
        // Kibble
        let kib = [
            MurzikRig.pbr(UIColor(red: 0.62, green: 0.38, blue: 0.2, alpha: 1), roughness: 0.6),
            MurzikRig.pbr(UIColor(red: 0.75, green: 0.5, blue: 0.26, alpha: 1), roughness: 0.6),
        ]
        for i in 0..<26 {
            let a = CM.hash(i * 3) * CM.tau
            let rr = sqrt(CM.hash(i * 3 + 1)) * 0.085
            let k = MurzikRig.sphere(0.017, kib[i % 2], segments: 12)
            k.simdPosition = SIMD3(cos(a) * rr, 0.03 + CM.hash(i * 3 + 2) * 0.02 + (0.085 - rr) * 0.25, sin(a) * rr)
            k.simdScale = SIMD3(1, 0.7, 1)
            food.addChildNode(k)
        }
        bowl.addChildNode(food)
        bowl.isHidden = true
        bowl.name = "murzik.bowl"
    }

    private func buildToy() {
        let yarnM = MurzikRig.pbr(UIColor(red: 0.95, green: 0.38, blue: 0.48, alpha: 1), roughness: 0.85)
        let wrapM = MurzikRig.pbr(UIColor(red: 0.82, green: 0.26, blue: 0.38, alpha: 1), roughness: 0.85)
        let holder = SCNNode()
        let ball = MurzikRig.sphere(0.065, yarnM)
        holder.addChildNode(ball)
        let axes: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 0, 1), SIMD3(0.7, 0.7, 0), SIMD3(0, 0.7, 0.7), SIMD3(0.6, 0, 0.8)]
        for (i, ax) in axes.enumerated() {
            let t = SCNTorus(ringRadius: 0.064, pipeRadius: 0.0045)
            t.ringSegmentCount = 48
            t.pipeSegmentCount = 8
            t.materials = [i % 2 == 0 ? wrapM : yarnM]
            let tn = SCNNode(geometry: t)
            tn.simdOrientation = simd_quatf(angle: 0.9 + Float(i) * 0.4, axis: simd_normalize(ax))
            holder.addChildNode(tn)
        }
        // Loose strand
        var parent = holder
        for i in 0..<5 {
            let seg = MurzikRig.capsule(radius: 0.005, length: 0.03, wrapM)
            let j = SCNNode()
            j.simdPosition = i == 0 ? SIMD3(0.0, -0.055, 0.03) : SIMD3(0, -0.03, 0)
            j.simdOrientation = simd_quatf(angle: 0.35, axis: SIMD3(1, 0, 0))
            seg.simdPosition = SIMD3(0, -0.015, 0)
            j.addChildNode(seg)
            parent.addChildNode(j)
            parent = j
        }
        toy.addChildNode(holder)
        toy.isHidden = true
        toy.name = "murzik.toy"
    }

    // MARK: FX (deterministic floaters)

    enum FXKind { case heart, zzz }

    private struct Floater {
        let node: SCNNode
        let born: Double
        let kind: FXKind
        let origin: SIMD3<Float>
        let seed: Float
    }

    private var floaters: [Floater] = []

    static func heartPath() -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: -3))
        p.addCurve(to: CGPoint(x: -3.2, y: 1.2), controlPoint1: CGPoint(x: -1.2, y: -1.6), controlPoint2: CGPoint(x: -3.2, y: -0.6))
        p.addCurve(to: CGPoint(x: 0, y: 1.6), controlPoint1: CGPoint(x: -3.2, y: 3.4), controlPoint2: CGPoint(x: -0.6, y: 3.6))
        p.addCurve(to: CGPoint(x: 3.2, y: 1.2), controlPoint1: CGPoint(x: 0.6, y: 3.6), controlPoint2: CGPoint(x: 3.2, y: 3.4))
        p.addCurve(to: CGPoint(x: 0, y: -3), controlPoint1: CGPoint(x: 3.2, y: -0.6), controlPoint2: CGPoint(x: 1.2, y: -1.6))
        p.close()
        return p
    }

    private lazy var heartGeometry: SCNGeometry = {
        let g = SCNShape(path: MurzikStage.heartPath(), extrusionDepth: 1.2)
        g.chamferRadius = 0.4
        g.materials = [MurzikRig.pbr(UIColor(red: 1.0, green: 0.36, blue: 0.52, alpha: 1), roughness: 0.35, emission: 0.55)]
        return g
    }()

    private lazy var zGeometry: SCNGeometry = {
        let base = UIFont.systemFont(ofSize: 7, weight: .black)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 7) } ?? base
        let t = SCNText(string: "z", extrusionDepth: 1.0)
        t.font = font
        t.flatness = 0.1
        t.materials = [MurzikRig.flat(UIColor(red: 0.78, green: 0.86, blue: 1.0, alpha: 1))]
        return t
    }()

    func makeFXNode(_ kind: FXKind) -> SCNNode {
        let inner = SCNNode(geometry: kind == .heart ? heartGeometry : zGeometry)
        inner.scale = SCNVector3(0.01, 0.01, 0.01)
        if kind == .zzz {
            // Center the text glyph.
            let (mn, mx) = inner.boundingBox
            inner.pivot = SCNMatrix4MakeTranslation((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, 0)
        }
        let n = SCNNode()
        n.addChildNode(inner)
        let bb = SCNBillboardConstraint()
        bb.freeAxes = .all
        n.constraints = [bb]
        return n
    }

    func spawn(_ kind: FXKind, at p: SIMD3<Float>, time: Double, seed: Float) {
        let n = makeFXNode(kind)
        n.simdPosition = p
        n.opacity = 0
        fxRoot.addChildNode(n)
        floaters.append(Floater(node: n, born: time, kind: kind, origin: p, seed: seed))
    }

    func updateFX(time: Double) {
        var keep: [Floater] = []
        for f in floaters {
            let age = Float(time - f.born)
            let life: Float = f.kind == .heart ? 1.7 : 2.6
            if age > life || age < -1 {
                f.node.removeFromParentNode()
                continue
            }
            let k = age / life
            let sway = sin(age * 3 + f.seed * 6) * (f.kind == .heart ? 0.03 : 0.05)
            let rise: Float = f.kind == .heart ? 0.3 : 0.35
            let drift = f.kind == .zzz ? age * 0.08 : 0
            f.node.simdPosition = f.origin + SIMD3(sway + drift, rise * age, 0)
            let pop = CM.ramp(age, 0, 0.25)
            let s = (f.kind == .heart ? 0.9 : 1.0) * (0.4 + 0.6 * pop) * (1 + 0.5 * k)
            f.node.simdScale = SIMD3(repeating: s)
            f.node.opacity = CGFloat(pop * (1 - CM.ramp(k, 0.6, 1)))
            keep.append(f)
        }
        floaters = keep
    }

    func clearFX() {
        for f in floaters { f.node.removeFromParentNode() }
        floaters.removeAll()
    }
}
