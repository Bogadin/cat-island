import AVFoundation
import CoreHaptics
import Foundation

/// User preferences for the experience (stored in standard defaults, read with `@AppStorage` in views).
enum ExperienceSettings {
    /// In-app island walker (built by the walker team). Default: on.
    static let walkerKey = "murzik.walker.enabled"
    static let soundKey = "murzik.sound.enabled"
    static let hapticsKey = "murzik.haptics.enabled"
    static let showNameKey = "murzik.name.visible"

    static func isOn(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}

/// A continuous, gently modulated purr you can feel: soft "inhale" and stronger "exhale" phrases,
/// each made of a low rumble plus a ~25 Hz flutter, looping until stopped.
final class PurrHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func start() {
        guard supported else { return }
        do {
            let engine = try makeEngineIfNeeded()
            try engine.start()
            if player == nil {
                let player = try engine.makeAdvancedPlayer(with: Self.purrPattern())
                player.loopEnabled = true
                player.loopEnd = Self.cycle
                self.player = player
            }
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            player = nil
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
    }

    /// A single soft tap (toy caught, gift…).
    func tap(intensity: Float = 0.6, sharpness: Float = 0.4) {
        guard supported else { return }
        do {
            let engine = try makeEngineIfNeeded()
            try engine.start()
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    private func makeEngineIfNeeded() throws -> CHHapticEngine {
        if let engine { return engine }
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak self] in
            self?.player = nil
            try? self?.engine?.start()
        }
        engine.stoppedHandler = { [weak self] _ in
            self?.player = nil
        }
        self.engine = engine
        return engine
    }

    /// One breath, in seconds.
    static let cycle: TimeInterval = 2.5

    static func purrPattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        func phrase(start: TimeInterval, duration: TimeInterval, strength: Float) {
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45 * strength),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.05),
            ], relativeTime: start, duration: duration))
            var t = start
            while t < start + duration {
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.32 * strength),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.0),
                ], relativeTime: t))
                t += 0.04
            }
        }
        phrase(start: 0, duration: 1.0, strength: 0.75)    // inhale
        phrase(start: 1.15, duration: 1.2, strength: 1.0)  // exhale
        // Swell and fade within each phrase.
        let swell = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0.0, value: 0.35),
            .init(relativeTime: 0.45, value: 1.0),
            .init(relativeTime: 1.0, value: 0.4),
            .init(relativeTime: 1.15, value: 0.35),
            .init(relativeTime: 1.7, value: 1.0),
            .init(relativeTime: 2.35, value: 0.3),
        ], relativeTime: 0)
        return try CHHapticPattern(events: events, parameterCurves: [swell])
    }
}

/// A synthesized purr: low-passed noise pulsed at ~26 Hz with a breathing envelope.
/// Uses the `.ambient` audio session, so it mixes with other audio and respects the silent switch.
final class PurrSound {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let synth = PurrSynth()
    private var stopWork: DispatchWorkItem?
    private var sessionActive = false
    /// Set after an engine configuration change (route / sample rate): rebuild the graph on next start.
    private var needsRebuild = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// True while a purr is wanted (between `start` and `stop`).
    private var isPurring: Bool { synth.targetGain > 0 }

    func start() {
        stopWork?.cancel()
        stopWork = nil
        synth.targetGain = 0.55
        guard !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            sessionActive = true
            if needsRebuild, let node = source {
                engine.detach(node)
                source = nil
            }
            needsRebuild = false
            if source == nil {
                let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
                let rate = hardwareRate > 0 ? hardwareRate : 44_100
                synth.sampleRate = rate
                guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
                let node = Self.makeSourceNode(synth)
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
                source = node
            }
            engine.prepare()
            try engine.start()
        } catch {
            engine.stop()
            deactivateSession()
        }
    }

    /// Fades out, then stops the engine and releases the audio session.
    func stop() {
        synth.targetGain = 0
        stopWork?.cancel()
        guard engine.isRunning else {
            stopWork = nil
            deactivateSession()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engine.stop()
            self.deactivateSession()
            self.stopWork = nil
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The engine stopped itself (route or format changed): rebuild, and resume if still purring.
    private func handleConfigurationChange() {
        needsRebuild = true
        engine.stop()
        if isPurring {
            start()
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // The system stopped the engine; start() brings it back next time.
            engine.stop()
            sessionActive = false
        case .ended:
            if isPurring { start() }
        @unknown default:
            break
        }
    }

    private static func makeSourceNode(_ synth: PurrSynth) -> AVAudioSourceNode {
        AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            synth.render(frames: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(audioBufferList))
            return noErr
        }
    }
}

/// The purr generator. `render` runs on the real-time audio thread; only `targetGain` is touched from outside.
final class PurrSynth: @unchecked Sendable {
    var sampleRate: Double = 44_100
    var targetGain: Float = 0

    private var gain: Float = 0
    private var time: Double = 0
    private var low1: Float = 0
    private var low2: Float = 0
    private var seed: UInt32 = 0x1234_5678

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let dt = 1.0 / sampleRate
        let target = targetGain
        let smoothing = Float(1 - exp(-dt / 0.12))
        let lowPass = Float(1 - exp(-2 * Double.pi * 190 * dt))
        let cycle = PurrHaptics.cycle
        for frame in 0..<frames {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            low1 += lowPass * (noise - low1)
            low2 += lowPass * (low1 - low2)

            // Breathing: softer inhale, short pause, stronger exhale (matches the haptic pattern).
            let t = time.truncatingRemainder(dividingBy: cycle)
            let breath: Double
            if t < 1.0 {
                breath = 0.6 * sin(Double.pi * t / 1.0)
            } else if t >= 1.15, t < 2.35 {
                breath = sin(Double.pi * (t - 1.15) / 1.2)
            } else {
                breath = 0
            }
            let pulse = pow(max(0, sin(2 * Double.pi * 26 * time)), 1.5)
            let body = Float(sin(2 * Double.pi * 52 * time)) * 0.22

            gain += smoothing * (target - gain)
            let sample = (low2 * 7 + body) * Float(pulse * breath) * gain
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
            time += dt
            // Wrap on a common multiple of every period (2.5 s, 1/26 s, 1/52 s) to keep precision.
            if time >= 250 { time -= 250 }
        }
    }
}
