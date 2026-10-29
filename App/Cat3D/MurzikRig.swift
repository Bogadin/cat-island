import SceneKit
import UIKit
import simd

/// Procedural 3D Murzik: builds the node hierarchy (all geometry generated in code) and applies `CatPose`s.
/// Frame: the cat faces +X, +Y is up, +Z is the cat's right side. Ground at y = 0.
final class MurzikRig {
    struct Style {
        /// Eye size multiplier (sprites use bigger eyes so they read at tiny sizes).
        var eyeScale: Float = 1
        /// Fresnel rim strength added to the fur.
        var rimStrength: Float = 0.5
        var rimColor = SIMD3<Float>(0.56, 0.60, 0.74)
        var whiskers = true
        var whiskerOpacity: CGFloat = 0.75

        static let app = Style()
        static let sprite = Style(eyeScale: 1.2, rimStrength: 0.95, rimColor: SIMD3(0.62, 0.66, 0.80),
                                  whiskers: true, whiskerOpacity: 0.55)
    }

    final class Leg {
        let root: SCNNode
        let knee: SCNNode
        let paw: SCNNode
        let parent: SCNNode
        let l1: Float
        let l2: Float
        let kneeForward: Bool
        init(root: SCNNode, knee: SCNNode, paw: SCNNode, parent: SCNNode, l1: Float, l2: Float, kneeForward: Bool) {
            self.root = root; self.knee = knee; self.paw = paw; self.parent = parent
            self.l1 = l1; self.l2 = l2; self.kneeForward = kneeForward
        }
    }

    final class Eye {
        let socket = SCNNode()
        let rot = SCNNode()
        let pupil = SCNNode()
        let upperLid = SCNNode()
        let lowerLid = SCNNode()
        let closedArc = SCNNode()   // "◡" sleeping
        let happyArc = SCNNode()    // "◠" happy / loving
        let highlights = SCNNode()
        let open = SCNNode()        // eyeball + iris + pupil container (hidden when closed)
    }

    static let catName = "murzik"

    let style: Style
    let root = SCNNode()
    let bodyNode = SCNNode()
    let chestNode = SCNNode()
    let hipsNode = SCNNode()
    let neckNode = SCNNode()
    let headNode = SCNNode()
    let jawNode = SCNNode()
    private(set) var earPivots: [SCNNode] = []
    private(set) var legs: [Leg] = []
    private(set) var tailNodes: [SCNNode] = []
    private var tailMeshes: [SCNNode] = []
    private(set) var eyes: [Eye] = []
    private let chestMesh = SCNNode()
    private let bellyMesh = SCNNode()
    private let mouthInside = SCNNode()
    private let tongue = SCNNode()
    private let mouthLine = SCNNode()
    private var blush: [SCNNode] = []
    private var colliders: [(SCNNode, Float)] = []

    // Materials
    let fur: SCNMaterial
    let furLight: SCNMaterial
    private let pink: SCNMaterial
    private let innerEar: SCNMaterial

    // Dimensions
    static let frontL1: Float = 0.115
    static let frontL2: Float = 0.11
    static let hindL1: Float = 0.12
    static let hindL2: Float = 0.12
    static let tailSeg: Float = 0.05

    init(style: Style = .app) {
        self.style = style
        fur = MurzikRig.furMaterial(base: UIColor(red: 0.035, green: 0.034, blue: 0.042, alpha: 1), style: style)
        furLight = MurzikRig.furMaterial(base: UIColor(red: 0.075, green: 0.072, blue: 0.085, alpha: 1), style: style)
        pink = MurzikRig.pbr(UIColor(red: 0.98, green: 0.55, blue: 0.64, alpha: 1), roughness: 0.42, emission: 0.18)
        innerEar = MurzikRig.pbr(UIColor(red: 0.92, green: 0.52, blue: 0.62, alpha: 1), roughness: 0.7, emission: 0.22)
        root.name = MurzikRig.catName
        build()
    }

    // MARK: - Materials

    static func furMaterial(base: UIColor, style: Style) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = base
        m.roughness.contents = NSNumber(value: 0.58)
        m.metalness.contents = NSNumber(value: 0.0)
        let r = String(format: "%.3f", style.rimColor.x * style.rimStrength)
        let g = String(format: "%.3f", style.rimColor.y * style.rimStrength)
        let b = String(format: "%.3f", style.rimColor.z * style.rimStrength)
        let shader = """
        float3 murzikN = normalize(_surface.normal);
        float3 murzikV = normalize(_surface.view);
        float murzikF = pow(1.0 - saturate(dot(murzikN, murzikV)), 2.4);
        float murzikTop = 0.55 + 0.45 * saturate(murzikN.y * 0.5 + 0.5);
        _output.color.rgb += float3(\(r), \(g), \(b)) * (murzikF * murzikTop);
        """
        m.shaderModifiers = [.fragment: shader]
        return m
    }

    static func pbr(_ color: UIColor, roughness: Double, emission: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = NSNumber(value: roughness)
        m.metalness.contents = NSNumber(value: 0.0)
        if emission > 0 {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            m.emission.contents = UIColor(red: r * emission, green: g * emission, blue: b * emission, alpha: 1)
        }
        return m
    }

    static func flat(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        return m
    }

    // MARK: - Geometry helpers

    static func sphere(_ r: Float, _ m: SCNMaterial, segments: Int = 48) -> SCNNode {
        let g = SCNSphere(radius: CGFloat(r))
        g.segmentCount = segments
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    /// Capsule along local Y, centered.
    static func capsule(radius: Float, length: Float, _ m: SCNMaterial) -> SCNNode {
        let g = SCNCapsule(capRadius: CGFloat(radius), height: CGFloat(length + 2 * radius))
        g.radialSegmentCount = 36
        g.capSegmentCount = 24
        g.heightSegmentCount = 1
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    /// Extruded 2D shape (path built in centimeters, scaled to meters).
    static func shape(_ path: UIBezierPath, depth: CGFloat, _ m: SCNMaterial, chamfer: CGFloat = 0) -> SCNNode {
        let g = SCNShape(path: path, extrusionDepth: depth * 100)
        if chamfer > 0 {
            g.chamferRadius = chamfer * 100
        }
        g.materials = [m]
        let holder = SCNNode()
        let n = SCNNode(geometry: g)
        n.scale = SCNVector3(0.01, 0.01, 0.01)
        holder.addChildNode(n)
        return holder
    }

    private func addCollider(_ n: SCNNode, _ r: Float) { colliders.append((n, r)) }

    // MARK: - Build

    private func build() {
        root.addChildNode(bodyNode)
        bodyNode.simdPosition = SIMD3(0, CatPose.standHeight, 0)

        // Torso
        let belly = MurzikRig.sphere(1, fur)
        belly.simdScale = SIMD3(0.205, 0.15, 0.155)
        bellyMesh.addChildNode(belly)
        bellyMesh.simdPosition = SIMD3(-0.005, -0.012, 0)
        bodyNode.addChildNode(bellyMesh)
        addCollider(bellyMesh, 0.14)

        chestNode.simdPosition = SIMD3(0.13, 0.02, 0)
        bodyNode.addChildNode(chestNode)
        let chestBall = MurzikRig.sphere(0.165, fur)
        chestBall.simdScale = SIMD3(1.0, 1.02, 0.94)
        chestMesh.addChildNode(chestBall)
        let bib = MurzikRig.sphere(0.12, furLight)
        bib.simdPosition = SIMD3(0.075, -0.035, 0)
        bib.simdScale = SIMD3(0.9, 1.05, 1.0)
        chestMesh.addChildNode(bib)
        chestNode.addChildNode(chestMesh)
        addCollider(chestNode, 0.16)

        hipsNode.simdPosition = SIMD3(-0.14, 0.0, 0)
        bodyNode.addChildNode(hipsNode)
        let hipBall = MurzikRig.sphere(0.168, fur)
        hipBall.simdScale = SIMD3(1.0, 0.97, 1.0)
        hipsNode.addChildNode(hipBall)
        addCollider(hipsNode, 0.155)
        for s: Float in [-1, 1] {
            let haunch = MurzikRig.sphere(0.095, fur)
            haunch.simdPosition = SIMD3(-0.01, -0.045, s * 0.085)
            hipsNode.addChildNode(haunch)
        }

        buildHead()
        buildLegs()
        buildTail()

        // Hit test helper: every geometry node under root counts as the cat.
        root.enumerateHierarchy { node, _ in
            if node.geometry != nil { node.name = node.name ?? "murzik.part" }
        }
    }

    private func buildHead() {
        neckNode.simdPosition = SIMD3(0.09, 0.09, 0)
        chestNode.addChildNode(neckNode)
        let neckMesh = MurzikRig.capsule(radius: 0.085, length: 0.08, fur)
        neckMesh.simdPosition = SIMD3(0.02, 0.05, 0)
        neckMesh.simdEulerAngles = SIMD3(0, 0, -0.35)
        neckNode.addChildNode(neckMesh)

        headNode.simdPosition = SIMD3(0.06, 0.13, 0)
        neckNode.addChildNode(headNode)
        addCollider(headNode, 0.17)

        let skull = MurzikRig.sphere(0.19, fur, segments: 64)
        skull.simdScale = SIMD3(0.93, 0.88, 1.05)
        headNode.addChildNode(skull)
        for s: Float in [-1, 1] {
            let cheek = MurzikRig.sphere(0.098, fur)
            cheek.simdPosition = SIMD3(0.045, -0.07, s * 0.098)
            cheek.simdScale = SIMD3(1.0, 0.92, 1.0)
            headNode.addChildNode(cheek)
            let pad = MurzikRig.sphere(0.046, furLight)
            pad.simdPosition = SIMD3(0.152, -0.066, s * 0.036)
            headNode.addChildNode(pad)
            // Blush
            let b = MurzikRig.sphere(0.034, MurzikRig.flat(UIColor(red: 1.0, green: 0.42, blue: 0.56, alpha: 1)), segments: 24)
            b.simdPosition = SIMD3(0.12, -0.045, s * 0.118)
            b.simdScale = SIMD3(0.35, 0.62, 1.0)
            b.simdOrientation = simd_quatf(angle: s * -0.75, axis: SIMD3(0, 1, 0))
            b.opacity = 0
            headNode.addChildNode(b)
            blush.append(b)
        }
        let chin = MurzikRig.sphere(0.036, fur)
        chin.simdPosition = SIMD3(0.132, -0.103, 0)
        headNode.addChildNode(chin)

        // Nose: rounded inverted triangle, facing +X.
        let nosePath = UIBezierPath()
        nosePath.move(to: CGPoint(x: -2.3, y: 1.1))
        nosePath.addQuadCurve(to: CGPoint(x: 2.3, y: 1.1), controlPoint: CGPoint(x: 0, y: 1.9))
        nosePath.addQuadCurve(to: CGPoint(x: 0, y: -1.5), controlPoint: CGPoint(x: 1.9, y: -0.6))
        nosePath.addQuadCurve(to: CGPoint(x: -2.3, y: 1.1), controlPoint: CGPoint(x: -1.9, y: -0.6))
        nosePath.close()
        let nose = MurzikRig.shape(nosePath, depth: 0.014, pink, chamfer: 0.004)
        nose.simdPosition = SIMD3(0.188, -0.03, 0)
        nose.simdOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: 0.25, axis: SIMD3(1, 0, 0))
        headNode.addChildNode(nose)

        // Mouth "ω" line under the nose.
        let w = UIBezierPath()
        w.move(to: CGPoint(x: -2.6, y: 0.3))
        w.addQuadCurve(to: CGPoint(x: 0, y: 0.2), controlPoint: CGPoint(x: -1.3, y: -1.6))
        w.addQuadCurve(to: CGPoint(x: 2.6, y: 0.3), controlPoint: CGPoint(x: 1.3, y: -1.6))
        let stroked = UIBezierPath(cgPath: w.cgPath.copy(strokingWithWidth: 0.42, lineCap: .round, lineJoin: .round, miterLimit: 2))
        let mouthMat = MurzikRig.flat(UIColor(red: 0.42, green: 0.42, blue: 0.48, alpha: 1))
        let mouthShape = MurzikRig.shape(stroked, depth: 0.004, mouthMat)
        mouthLine.addChildNode(mouthShape)
        mouthLine.simdPosition = SIMD3(0.196, -0.068, 0)
        mouthLine.simdOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        headNode.addChildNode(mouthLine)
        // Philtrum
        let phil = MurzikRig.capsule(radius: 0.0021, length: 0.018, mouthMat)
        phil.simdPosition = SIMD3(0.197, -0.053, 0)
        headNode.addChildNode(phil)

        // Mouth interior (scaled by jaw opening) + jaw.
        let inside = MurzikRig.sphere(0.05, MurzikRig.pbr(UIColor(red: 0.55, green: 0.12, blue: 0.2, alpha: 1), roughness: 0.5, emission: 0.25))
        inside.simdScale = SIMD3(0.8, 0.75, 1.0)
        mouthInside.addChildNode(inside)
        mouthInside.simdPosition = SIMD3(0.15, -0.088, 0)
        mouthInside.simdScale = SIMD3(repeating: 0.01)
        headNode.addChildNode(mouthInside)

        jawNode.simdPosition = SIMD3(0.1, -0.075, 0)
        headNode.addChildNode(jawNode)
        let jawMesh = MurzikRig.sphere(0.042, fur)
        jawMesh.simdPosition = SIMD3(0.055, -0.03, 0)
        jawMesh.simdScale = SIMD3(1.15, 0.6, 1.1)
        jawNode.addChildNode(jawMesh)
        let tongueMesh = MurzikRig.sphere(0.024, pink)
        tongueMesh.simdScale = SIMD3(1.3, 0.45, 1.0)
        tongue.addChildNode(tongueMesh)
        tongue.simdPosition = SIMD3(0.08, -0.018, 0)
        tongue.simdScale = SIMD3(repeating: 0.01)
        jawNode.addChildNode(tongue)

        // Whiskers
        if style.whiskers {
            let wm = MurzikRig.flat(UIColor(white: 0.9, alpha: style.whiskerOpacity))
            for s: Float in [-1, 1] {
                for i in 0..<3 {
                    let g = SCNCylinder(radius: 0.0016, height: 0.17)
                    g.radialSegmentCount = 6
                    g.materials = [wm]
                    let wn = SCNNode(geometry: g)
                    wn.position = SCNVector3(0, 0.085, 0)
                    let holder = SCNNode()
                    holder.addChildNode(wn)
                    holder.simdPosition = SIMD3(0.165, -0.062 + Float(i) * 0.011, s * 0.07)
                    // Point sideways (+/-Z), slightly forward, fanned up/down.
                    let fan = Float(i - 1) * 0.16
                    let toSide = simd_quatf(angle: s * (.pi / 2), axis: SIMD3(1, 0, 0))   // Y → ±Z
                    let forward = simd_quatf(angle: s * 0.2, axis: SIMD3(0, 1, 0))
                    let tilt = simd_quatf(angle: fan, axis: SIMD3(1, 0, 0) * -s)
                    holder.simdOrientation = forward * tilt * toSide
                    headNode.addChildNode(holder)
                }
            }
        }

        // Ears
        for s: Float in [-1, 1] {
            let base = SCNNode()
            base.simdPosition = SIMD3(-0.005, 0.125, s * 0.105)
            base.simdOrientation = simd_quatf(angle: s * 0.38, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: -0.08, axis: SIMD3(0, 0, 1))
            headNode.addChildNode(base)
            let pivot = SCNNode()
            base.addChildNode(pivot)
            let outer = SCNCone(topRadius: 0.006, bottomRadius: 0.078, height: 0.135)
            outer.radialSegmentCount = 36
            outer.materials = [fur]
            let outerN = SCNNode(geometry: outer)
            outerN.simdPosition = SIMD3(0, 0.0675, 0)
            outerN.simdScale = SIMD3(0.42, 1, 1)
            pivot.addChildNode(outerN)
            let inner = SCNCone(topRadius: 0.004, bottomRadius: 0.056, height: 0.1)
            inner.radialSegmentCount = 30
            inner.materials = [innerEar]
            let innerN = SCNNode(geometry: inner)
            innerN.simdPosition = SIMD3(0.019, 0.055, 0)
            innerN.simdScale = SIMD3(0.3, 1, 1)
            pivot.addChildNode(innerN)
            earPivots.append(pivot)
        }

        // Eyes
        let edge = MurzikRig.pbr(UIColor(red: 0.62, green: 0.84, blue: 0.20, alpha: 1), roughness: 0.18, emission: 0.55)
        let center = MurzikRig.pbr(UIColor(red: 1.0, green: 0.76, blue: 0.22, alpha: 1), roughness: 0.18, emission: 0.6)
        let pupilMat = MurzikRig.pbr(UIColor(red: 0.01, green: 0.01, blue: 0.015, alpha: 1), roughness: 0.1)
        let shine = MurzikRig.flat(.white)
        let arcMat = MurzikRig.flat(UIColor(red: 0.98, green: 0.80, blue: 0.36, alpha: 1))
        for s: Float in [-1, 1] {
            let e = Eye()
            let n = simd_normalize(SIMD3<Float>(0.80, 0.10, s * 0.58))
            e.socket.simdPosition = SIMD3(0.125, 0.018, s * 0.083)
            e.socket.simdOrientation = simd_quatf(from: SIMD3(0, 0, 1), to: n)
            e.socket.simdScale = SIMD3(repeating: style.eyeScale)
            headNode.addChildNode(e.socket)

            e.socket.addChildNode(e.open)
            e.open.addChildNode(e.rot)
            let ball = MurzikRig.sphere(0.06, edge)
            ball.simdScale = SIMD3(1, 1.08, 0.55)
            e.rot.addChildNode(ball)
            let iris = MurzikRig.sphere(0.046, center)
            iris.simdScale = SIMD3(1, 1.08, 0.45)
            iris.simdPosition = SIMD3(0, 0, 0.0145)
            e.rot.addChildNode(iris)
            let pupilBall = MurzikRig.sphere(0.03, pupilMat)
            e.pupil.addChildNode(pupilBall)
            e.pupil.simdPosition = SIMD3(0, 0, 0.0275)
            e.pupil.simdScale = SIMD3(0.6, 1.2, 0.3)
            e.rot.addChildNode(e.pupil)

            e.socket.addChildNode(e.highlights)
            let h1 = MurzikRig.sphere(0.0125, shine, segments: 16)
            h1.simdPosition = SIMD3(0.017, 0.024, 0.0335)
            h1.simdScale = SIMD3(1, 1, 0.4)
            e.highlights.addChildNode(h1)
            let h2 = MurzikRig.sphere(0.0065, shine, segments: 12)
            h2.simdPosition = SIMD3(-0.017, -0.019, 0.032)
            h2.simdScale = SIMD3(1, 1, 0.4)
            e.highlights.addChildNode(h2)

            for lid in [e.upperLid, e.lowerLid] {
                let l = MurzikRig.sphere(0.067, fur)
                l.simdScale = SIMD3(1.04, 1.0, 0.64)
                lid.addChildNode(l)
                lid.isHidden = true
                e.socket.addChildNode(lid)
            }

            // Closed-eye arcs (stroked paths, cm units).
            let down = UIBezierPath()
            down.move(to: CGPoint(x: -4.4, y: 0.6))
            down.addQuadCurve(to: CGPoint(x: 4.4, y: 0.6), controlPoint: CGPoint(x: 0, y: -3.0))
            let downS = UIBezierPath(cgPath: down.cgPath.copy(strokingWithWidth: 1.15, lineCap: .round, lineJoin: .round, miterLimit: 2))
            let up = UIBezierPath()
            up.move(to: CGPoint(x: -4.2, y: -1.0))
            up.addQuadCurve(to: CGPoint(x: 4.2, y: -1.0), controlPoint: CGPoint(x: 0, y: 3.4))
            let upS = UIBezierPath(cgPath: up.cgPath.copy(strokingWithWidth: 1.2, lineCap: .round, lineJoin: .round, miterLimit: 2))
            let downN = MurzikRig.shape(downS, depth: 0.006, arcMat)
            let upN = MurzikRig.shape(upS, depth: 0.006, arcMat)
            e.closedArc.addChildNode(downN)
            e.happyArc.addChildNode(upN)
            for arc in [e.closedArc, e.happyArc] {
                arc.simdPosition = SIMD3(0, -0.004, 0.036)
                // Path +x should point toward the cat's left (socket +X) — already the case; keep upright.
                arc.isHidden = true
                e.socket.addChildNode(arc)
            }
            eyes.append(e)
        }
    }

    private func buildLegs() {
        func makeLeg(parent: SCNNode, anchor: SIMD3<Float>, l1: Float, l2: Float, r1: Float, r2: Float, front: Bool) -> Leg {
            let rootN = SCNNode()
            rootN.simdPosition = anchor
            parent.addChildNode(rootN)
            let upper = MurzikRig.capsule(radius: r1, length: l1, fur)
            upper.simdPosition = SIMD3(0, -l1 / 2, 0)
            rootN.addChildNode(upper)
            if !front {
                let thigh = MurzikRig.sphere(r1 * 1.25, fur)
                thigh.simdPosition = SIMD3(0.0, -l1 * 0.25, 0)
                thigh.simdScale = SIMD3(1.0, 1.25, 0.85)
                rootN.addChildNode(thigh)
            }
            let knee = SCNNode()
            knee.simdPosition = SIMD3(0, -l1, 0)
            rootN.addChildNode(knee)
            let lower = MurzikRig.capsule(radius: r2, length: l2, fur)
            lower.simdPosition = SIMD3(0, -l2 / 2, 0)
            knee.addChildNode(lower)
            let paw = SCNNode()
            paw.simdPosition = SIMD3(0, -l2, 0)
            knee.addChildNode(paw)
            let pawMesh = MurzikRig.sphere(0.043, fur)
            pawMesh.simdPosition = SIMD3(0.014, 0, 0)
            pawMesh.simdScale = SIMD3(1.32, 0.74, 1.08)
            paw.addChildNode(pawMesh)
            // Toe beans under the paw.
            let bean = MurzikRig.sphere(0.017, pink, segments: 16)
            bean.simdPosition = SIMD3(0.01, -0.027, 0)
            bean.simdScale = SIMD3(1.1, 0.4, 1.2)
            paw.addChildNode(bean)
            for j in 0..<3 {
                let toe = MurzikRig.sphere(0.0085, pink, segments: 12)
                toe.simdPosition = SIMD3(0.04, -0.024, Float(j - 1) * 0.017)
                toe.simdScale = SIMD3(1, 0.5, 1)
                paw.addChildNode(toe)
            }
            return Leg(root: rootN, knee: knee, paw: paw, parent: parent, l1: l1, l2: l2, kneeForward: !front)
        }
        // Order: FL, FR, HL, HR
        legs = [
            makeLeg(parent: chestNode, anchor: SIMD3(0.05, -0.08, -0.075), l1: MurzikRig.frontL1, l2: MurzikRig.frontL2, r1: 0.044, r2: 0.036, front: true),
            makeLeg(parent: chestNode, anchor: SIMD3(0.05, -0.08, 0.075), l1: MurzikRig.frontL1, l2: MurzikRig.frontL2, r1: 0.044, r2: 0.036, front: true),
            makeLeg(parent: hipsNode, anchor: SIMD3(0.0, -0.06, -0.085), l1: MurzikRig.hindL1, l2: MurzikRig.hindL2, r1: 0.052, r2: 0.034, front: false),
            makeLeg(parent: hipsNode, anchor: SIMD3(0.0, -0.06, 0.085), l1: MurzikRig.hindL1, l2: MurzikRig.hindL2, r1: 0.052, r2: 0.034, front: false),
        ]
    }

    private func buildTail() {
        var parent = hipsNode
        var offset = SIMD3<Float>(-0.145, 0.055, 0)
        let n = CatPose.tailCount
        for i in 0..<n {
            let seg = SCNNode()
            seg.simdPosition = offset
            parent.addChildNode(seg)
            let k = Float(i) / Float(n - 1)
            let r = CM.mix(0.03, 0.021, k)
            let mesh = MurzikRig.capsule(radius: r, length: MurzikRig.tailSeg, fur)
            mesh.simdPosition = SIMD3(-MurzikRig.tailSeg / 2, 0, 0)
            mesh.simdOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            let holder = SCNNode()
            holder.addChildNode(mesh)
            seg.addChildNode(holder)
            tailMeshes.append(holder)
            tailNodes.append(seg)
            parent = seg
            offset = SIMD3(-MurzikRig.tailSeg, 0, 0)
        }
    }

    // MARK: - Apply pose

    /// Applies a complete pose. `time` drives breathing.
    func apply(_ p: CatPose, time: Double) {
        let breath = sin(Float(time) * CM.tau * p.breathRate) * p.breathAmp
        bodyNode.simdPosition = p.bodyPos
        bodyNode.simdOrientation = CM.quat(p.body)
        chestNode.simdOrientation = CM.quat(p.chest)
        hipsNode.simdOrientation = CM.quat(p.hips)
        neckNode.simdOrientation = CM.quat(p.neck)
        headNode.simdOrientation = CM.quat(p.head)

        let puff = 1 + 0.12 * p.puff
        chestMesh.simdScale = SIMD3(1 + 0.012 * breath, 1 + 0.022 * breath, 1 + 0.02 * breath) * puff
        bellyMesh.simdScale = SIMD3(1, 1 + 0.03 * breath, 1 + 0.035 * breath) * puff

        // Keep the body above the floor.
        if p.groundClamp > 0.01 {
            var lowest: Float = 1
            for (node, r) in colliders {
                let c = root.simdConvertPosition(SIMD3(0, 0, 0), from: node)
                lowest = min(lowest, c.y - r)
            }
            if lowest < 0 {
                bodyNode.simdPosition.y += -lowest * p.groundClamp
            }
        }

        earPivots[0].simdOrientation = CM.quat(SIMD3(-p.earL.x, p.earL.y, p.earL.z))
        earPivots[1].simdOrientation = CM.quat(SIMD3(p.earR.x, -p.earR.y, p.earR.z))

        // Tail
        for i in 0..<tailNodes.count {
            let a = p.tail[i]
            tailNodes[i].simdOrientation = simd_quatf(angle: a.y, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -a.x, axis: SIMD3(0, 0, 1))
            let k = 1 + 0.55 * p.puff
            tailMeshes[i].simdScale = SIMD3(1, k, k)
        }

        // Legs (IK)
        for i in 0..<4 {
            solve(legs[i], target: p.feet[i], ground: p.feetGround, tilt: p.pawTilt[i])
        }

        applyFace(p.face)
    }

    private func solve(_ leg: Leg, target: SIMD3<Float>, ground: Float, tilt: Float) {
        let anchor = leg.root.simdPosition
        let localTarget = anchor + target
        var t = localTarget
        if ground > 0.001 {
            let g = leg.parent.simdConvertPosition(target, from: root)
            t = CM.mix(localTarget, g, ground)
        }
        let dx = t.x - anchor.x
        let dy = t.y - anchor.y
        let a = leg.l1, b = leg.l2
        var dist = sqrt(dx * dx + dy * dy)
        dist = CM.clamp(dist, (a + b) * 0.22, (a + b) * 0.999)
        let phi = atan2(dx, -dy)
        let cosA = CM.clamp((a * a + dist * dist - b * b) / (2 * a * dist), -1, 1)
        let cosK = CM.clamp((a * a + b * b - dist * dist) / (2 * a * b), -1, 1)
        let angA = acos(cosA)
        let angK = acos(cosK)
        let s: Float = leg.kneeForward ? 1 : -1
        let upper = phi + s * angA
        let lower = -s * (CM.pi - angK)
        leg.root.simdOrientation = simd_quatf(angle: upper, axis: SIMD3(0, 0, 1))
        leg.knee.simdOrientation = simd_quatf(angle: lower, axis: SIMD3(0, 0, 1))
        // Keep paws level with the ground (plus tilt).
        let v = root.simdConvertVector(SIMD3(1, 0, 0), from: leg.parent)
        let parentPitch = atan2(v.y, max(abs(v.x), 0.0001) * (v.x < 0 ? -1 : 1))
        let level = -(upper + lower + parentPitch)
        leg.paw.simdOrientation = simd_quatf(angle: level * ground + tilt, axis: SIMD3(0, 0, 1))
    }

    private func applyFace(_ f: CatFaceState) {
        let closedAmt = CM.ramp(f.lidUpper, 0.82, 0.97)
        let happy = f.lidLower > 0.25
        for e in eyes {
            // Pupils: slit ↔ round.
            let w = CM.mix(0.22, 1.05, f.pupil)
            let h = CM.mix(1.25, 1.1, f.pupil)
            e.pupil.simdScale = SIMD3(w, h, 0.3)
            e.rot.simdOrientation = simd_quatf(angle: f.gaze.x * 0.42, axis: SIMD3(0, 1, 0)) *
                simd_quatf(angle: -f.gaze.y * 0.35, axis: SIMD3(1, 0, 0))
            let up = CM.sat(f.lidUpper)
            e.upperLid.isHidden = up < 0.02 || closedAmt > 0.99
            e.upperLid.simdPosition = SIMD3(0, CM.mix(0.125, 0.0, up), 0.003)
            let low = CM.sat(f.lidLower)
            e.lowerLid.isHidden = low < 0.02 || closedAmt > 0.99
            e.lowerLid.simdPosition = SIMD3(0, CM.mix(-0.125, -0.06, low), 0.003)
            e.open.isHidden = closedAmt > 0.99
            e.highlights.isHidden = up > 0.7
            e.closedArc.isHidden = happy || closedAmt < 0.01
            e.happyArc.isHidden = !happy || closedAmt < 0.01
            e.closedArc.opacity = CGFloat(closedAmt)
            e.happyArc.opacity = CGFloat(closedAmt)
        }
        let jaw = CM.sat(f.jaw)
        jawNode.simdOrientation = simd_quatf(angle: -0.55 * jaw, axis: SIMD3(0, 0, 1))
        let inside = max(0.01, CM.ramp(jaw, 0.0, 0.35))
        mouthInside.simdScale = SIMD3(repeating: inside)
        mouthLine.isHidden = jaw > 0.18
        let tg = max(0.01, CM.sat(f.tongue))
        tongue.simdScale = SIMD3(repeating: tg)
        tongue.simdPosition = SIMD3(0.06 + 0.035 * f.tongue, -0.012, 0)
        for b in blush { b.opacity = CGFloat(CM.sat(f.blush) * 0.75) }
    }

    // MARK: - Queries

    /// Head center in the root frame.
    var headPositionInRoot: SIMD3<Float> {
        root.simdConvertPosition(SIMD3(0, 0, 0), from: headNode)
    }

    /// World position of the mouth.
    var mouthWorld: SIMD3<Float> {
        headNode.simdConvertPosition(SIMD3(0.19, -0.08, 0), to: nil)
    }

    var headWorld: SIMD3<Float> {
        headNode.simdConvertPosition(SIMD3(0, 0.05, 0), to: nil)
    }

    func pawWorld(_ i: Int) -> SIMD3<Float> {
        legs[i].paw.simdConvertPosition(SIMD3(0.02, -0.02, 0), to: nil)
    }

    /// True if `node` belongs to this cat.
    func contains(_ node: SCNNode) -> Bool {
        var n: SCNNode? = node
        while let cur = n {
            if cur === root { return true }
            n = cur.parent
        }
        return false
    }
}
