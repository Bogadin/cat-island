import Foundation

#if !WIDGET_EXTENSION
import UIKit

/// Plays short walk sequences in the Dynamic Island by sending a series of content updates
/// (app process only). Each update goes through `IslandQueue`, so it never races `reconcile`.
/// A newer sequence supersedes an older one; every sequence ends with Murzik resting.
@MainActor
enum IslandChoreographer {
    private static var generation = 0
    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private static var walkTask: Task<Void, Never>?

    private static var isHostingUnitTests: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }

    // MARK: Triggers

    /// The app went to the background: Murzik walks across the island (through the camera area
    /// in the compact island) and sits down on the other side. Runs in a short background task.
    static func appDidEnterBackground(storage: PetStorage = PetStorage()) {
        guard !isHostingUnitTests, storage.islandEnabled, LiveActivityController.areActivitiesEnabled else { return }
        endBackgroundTask()
        walkTask?.cancel()
        let id = UIApplication.shared.beginBackgroundTask(withName: "murzik.island.walk") {
            // Called on the main thread when time runs out.
            MainActor.assumeIsolated { IslandChoreographer.expire() }
        }
        guard id != .invalid else { return }
        backgroundTask = id
        #if DEBUG
        debugLog("background: start walk")
        #endif
        walkTask = Task { @MainActor in
            // Let the app finish closing so the island is on screen when he starts walking.
            try? await Task.sleep(nanoseconds: 900_000_000)
            if !Task.isCancelled, LiveActivityController.isRunning {
                let now = Date.now
                let state = PersonalityEngine.advance(storage.load(now: now), to: now)
                if !state.isSleeping {
                    let beats = IslandChoreography.crossing(
                        from: IslandSceneStore.shared.current,
                        restNotBefore: IslandChoreographer.reactionRemaining(in: state, at: now)
                    )
                    await IslandChoreographer.play(beats, storage: storage)
                } else if !Task.isCancelled {
                    // Asleep: no walk, but one update so the island shows his latest state
                    // (in-app actions are not sent while the app is open).
                    await IslandChoreographer.send(IslandSceneStore.shared.current.resting(), storage: storage)
                }
            }
            #if DEBUG
            if !Task.isCancelled { await IslandChoreographer.runDebugIntentAfterWalk() }
            #endif
            if IslandChoreographer.backgroundTask == id { IslandChoreographer.endBackgroundTask() }
        }
    }

    /// The app came back to the front: stop a walk that is still running (without a closing
    /// update; the caller reconciles right after with the latest state).
    static func cancelWalk() {
        generation &+= 1
        walkTask?.cancel()
        walkTask = nil
        endBackgroundTask()
    }

    /// After an action (island button or in-app): walk to the tapped button, react, settle.
    static func react(to action: PetAction?, state: PetState, storage: PetStorage = PetStorage()) async {
        let now = Date.now
        var mood: MurzikMood?
        if let reaction = state.lastReaction, PersonalityEngine.isReactionActive(reaction, at: now) {
            mood = reaction.mood
        }
        // Nothing to show (e.g. "sleep"): reconcile has already updated the mood.
        guard mood != nil || action == .pet || action == .feed else { return }
        #if DEBUG
        debugLog("react action=\(action?.rawValue ?? "nil") mood=\(mood?.rawValue ?? "nil")")
        #endif
        // In-app reactions happen while the island is hidden (app in front): don't spend the
        // update budget on a show nobody sees, just settle when the reaction is over.
        if action == nil {
            var settle = IslandSceneStore.shared.current.resting()
            settle.facingLeft = IslandSceneStore.shared.current.facingLeft
            await play([IslandBeat(at: reactionRemaining(in: state, at: now), scene: settle)], storage: storage)
            return
        }
        let beats = IslandChoreography.reaction(
            to: action,
            reactionMood: mood,
            isSleeping: state.isSleeping,
            from: IslandSceneStore.shared.current,
            restNotBefore: reactionRemaining(in: state, at: now)
        )
        await play(beats, storage: storage)
    }

    // MARK: Playback

    /// Sends the beats on schedule. Returns false if superseded or cancelled.
    @discardableResult
    static func play(_ beats: [IslandBeat], storage: PetStorage = PetStorage()) async -> Bool {
        generation &+= 1
        let current = generation
        let start = Date.now
        let list = Array(beats.prefix(IslandChoreography.maxBeats))
        for (index, beat) in list.enumerated() {
            let wait = beat.at - Date.now.timeIntervalSince(start)
            if wait > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                } catch {
                    // Cancelled (e.g. background time ran out): don't leave him mid-step.
                    // A superseded settle (he is already resting) sends nothing.
                    let shown = IslandSceneStore.shared.current
                    if current == generation, shown.pose != .rest || shown.effect != .none {
                        await send(IslandSceneStore.shared.current.resting(), storage: storage)
                    }
                    return false
                }
            }
            guard current == generation else { return false }
            // Running late (slow updates)? Skip to the next beat instead of piling up a backlog.
            if index + 1 < list.count, Date.now.timeIntervalSince(start) >= list[index + 1].at {
                continue
            }
            await send(beat.scene, storage: storage)
        }
        return true
    }

    private static func send(_ scene: IslandScene, storage: PetStorage) async {
        await IslandQueue.runQuietly {
            guard storage.islandEnabled, LiveActivityController.isRunning else { return }
            let now = Date.now
            let state = PersonalityEngine.advance(storage.load(now: now), to: now)
            await LiveActivityController.update(state: state, now: now, scene: scene)
            #if DEBUG
            IslandChoreographer.debugLog("sent step=\(scene.step) pose=\(scene.pose.rawValue) frame=\(scene.frame) pos=\(String(format: "%.2f", scene.position)) effect=\(scene.effect.rawValue) mood=\(MurzikAttributes.ContentState(state: state, now: now).mood.rawValue)")
            #endif
        }
    }

    #if DEBUG
    /// UI tests pass MURZIK_ISLAND_LOG (a file path) to record every update the app sends.
    static func debugLog(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["MURZIK_ISLAND_LOG"] else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let text = "\(formatter.string(from: .now)) \(line)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: URL(fileURLWithPath: path))
        }
    }
    #endif

    // MARK: Helpers

    #if DEBUG
    /// UI tests: `-uitest-intent-after-walk pet|feed` runs that island button's intent after the
    /// leaving-the-app walk (the simulator cannot tap Live Activity buttons reliably).
    static func runDebugIntentAfterWalk() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uitest-intent-after-walk"), i + 1 < args.count else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        switch args[i + 1] {
        case "pet": _ = try? await PetMurzikIntent().perform()
        case "feed": _ = try? await FeedMurzikIntent().perform()
        default: break
        }
    }
    #endif

    private static func reactionRemaining(in state: PetState, at now: Date) -> TimeInterval {
        guard let reaction = state.lastReaction, PersonalityEngine.isReactionActive(reaction, at: now) else { return 0 }
        return PersonalityEngine.reactionDuration - now.timeIntervalSince(reaction.date) + 0.3
    }

    private static func expire() {
        walkTask?.cancel()
        endBackgroundTask()
    }

    private static func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
#endif
