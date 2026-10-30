import Combine
import SceneKit
import SwiftUI
import UIKit

/// CONTRACT between the 3D character (owned by the 3D team) and the app screen (owned by the app team).
/// The app screen only uses this public API; everything behind it may change freely.
///
/// Usage:
/// ```swift
/// @StateObject var cat = Murzik3DController()
/// Murzik3DView(controller: cat)            // transparent, fills its frame
///     .frame(height: 380)
/// cat.setMood(model.mood)                  // whenever the mood changes
/// cat.perform(.feed)                       // after a user action
/// cat.onPetted = { model.pet() }           // tap / stroke on the cat
/// ```
@MainActor
final class Murzik3DController: ObservableObject {
    /// Current mood (drives idle behaviour, expressions and posture).
    @Published private(set) var mood: MurzikMood = .idle
    /// Called when the user pets Murzik directly in the 3D view (tap or stroke on the cat).
    var onPetted: (() -> Void)?

    /// The SceneKit simulation (scene, rig, brain). Exposed for tests and advanced use.
    let engine: MurzikEngine
    /// The view currently showing the scene (set by `Murzik3DView`).
    weak var sceneView: SCNView?
    /// True while rendering is paused (see `setRenderingPaused`).
    private(set) var isRenderingPaused = false

    /// Camera orbit (radians), limited.
    private(set) var orbitYaw: Float = 0
    private(set) var orbitPitch: Float = 0.3
    private var lastPetCallback = Date.distantPast

    init() {
        engine = MurzikEngine()
    }

    func setMood(_ mood: MurzikMood) {
        self.mood = mood
        engine.send(.mood(mood))
    }

    /// Plays the animation for an action (eat from a bowl, play with a toy, purr, curl up, wake up…).
    func perform(_ action: PetAction) {
        engine.send(.action(action))
    }

    /// Makes Murzik look toward a point in the view (0...1 in both axes), e.g. the user's finger. `nil` = stop.
    func lookAt(normalizedPoint: CGPoint?) {
        guard let p = normalizedPoint else {
            engine.setLookTarget(world: nil)
            return
        }
        if let view = sceneView, view.bounds.width > 0 {
            let pt = CGPoint(x: p.x * view.bounds.width, y: p.y * view.bounds.height)
            let head = engine.rig.headNode.presentation.simdWorldPosition
            let projected = view.projectPoint(SCNVector3(head.x, head.y, head.z))
            let w = view.unprojectPoint(SCNVector3(Float(pt.x), Float(pt.y), projected.z))
            engine.setLookTarget(world: SIMD3(w.x, w.y, w.z))
        } else {
            // No view yet: map to a plane in front of the stage.
            let x = (Float(p.x) - 0.5) * 2.4
            let y = (0.5 - Float(p.y)) * 1.6 + 0.4
            engine.setLookTarget(world: SIMD3(x, y, 1.2))
        }
    }

    // MARK: Additional API

    /// Stops (or resumes) rendering and the simulation, e.g. while the screen is covered by a sheet
    /// or the app is in the background.
    func setRenderingPaused(_ paused: Bool) {
        isRenderingPaused = paused
        (sceneView as? MurzikSCNView)?.renderingPaused = paused
    }

    /// Shows or hides the round rug under Murzik.
    func setRugVisible(_ visible: Bool) {
        engine.stage.rug.isHidden = !visible
    }

    /// Rotates the camera around Murzik (limited angles).
    func orbit(byYaw dYaw: Float, pitch dPitch: Float) {
        orbitYaw = CM.clamp(orbitYaw + dYaw, -0.7, 0.7)
        orbitPitch = CM.clamp(orbitPitch + dPitch, 0.1, 0.62)
        engine.send(.orbit(yaw: orbitYaw, pitch: orbitPitch))
    }

    /// True if a point in the scene view hits the cat.
    func hitsCat(_ point: CGPoint, in view: SCNView) -> Bool {
        let hits = view.hitTest(point, options: [
            SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
            SCNHitTestOption.ignoreHiddenNodes: true,
        ])
        return hits.contains { engine.rig.contains($0.node) }
    }

    /// User petted the cat in the view: purr + callback (throttled for strokes).
    func userPetted() {
        engine.send(.petted)
        let now = Date()
        if now.timeIntervalSince(lastPetCallback) > 1.2 {
            lastPetCallback = now
            onPetted?()
        }
    }
}

/// The 3D stage. Transparent background, fills its frame.
struct Murzik3DView: View {
    @ObservedObject var controller: Murzik3DController

    var body: some View {
        MurzikSceneView(controller: controller)
            .accessibilityElement()
            .accessibilityLabel(Text("\(Strings.name), \(Strings.moodTitle(controller.mood))"))
            .accessibilityAddTraits(.isButton)
    }
}

/// SCNView that pauses rendering when it is not in a window or when paused by the app.
final class MurzikSCNView: SCNView {
    var renderingPaused = false {
        didSet { updatePlaying() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlaying()
    }

    private func updatePlaying() {
        let play = window != nil && !renderingPaused
        isPlaying = play
        rendersContinuously = play
    }
}

struct MurzikSceneView: UIViewRepresentable {
    let controller: Murzik3DController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> MurzikSCNView {
        let v = MurzikSCNView(frame: .zero, options: nil)
        v.scene = controller.engine.scene
        v.pointOfView = controller.engine.cameraNode
        v.delegate = controller.engine
        v.backgroundColor = .clear
        v.isOpaque = false
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.isPlaying = true
        v.renderingPaused = controller.isRenderingPaused
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(pan)
        controller.sceneView = v
        return v
    }

    func updateUIView(_ uiView: MurzikSCNView, context: Context) {
        context.coordinator.controller = controller
        if controller.sceneView !== uiView { controller.sceneView = uiView }
        if uiView.renderingPaused != controller.isRenderingPaused {
            uiView.renderingPaused = controller.isRenderingPaused
        }
    }

    static func dismantleUIView(_ uiView: MurzikSCNView, coordinator: Coordinator) {
        uiView.isPlaying = false
        uiView.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        var controller: Murzik3DController
        private var stroking = false
        private var strokeDistance: CGFloat = 0
        private var last: CGPoint = .zero

        init(controller: Murzik3DController) { self.controller = controller }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? SCNView else { return }
            let p = g.location(in: v)
            if controller.hitsCat(p, in: v) {
                controller.userPetted()
            } else if v.bounds.width > 0 {
                // Tapping elsewhere: Murzik glances there for a moment.
                controller.lookAt(normalizedPoint: CGPoint(x: p.x / v.bounds.width, y: p.y / v.bounds.height))
                let c = controller
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    c.lookAt(normalizedPoint: nil)
                }
            }
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view as? SCNView else { return }
            let p = g.location(in: v)
            switch g.state {
            case .began:
                stroking = controller.hitsCat(p, in: v)
                strokeDistance = 0
                last = p
            case .changed:
                let d = CGPoint(x: p.x - last.x, y: p.y - last.y)
                last = p
                if stroking {
                    strokeDistance += hypot(d.x, d.y)
                    if strokeDistance > 60 {
                        strokeDistance = 0
                        controller.userPetted()
                    }
                } else {
                    controller.orbit(byYaw: Float(-d.x) * 0.006, pitch: Float(d.y) * 0.004)
                }
            default:
                stroking = false
            }
        }
    }
}
