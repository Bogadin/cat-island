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
                }
            }
            if IslandChoreographer.backgroundTask == id { IslandChoreographer.endBackgroundTask() }
        }
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
        for beat in beats.prefix(IslandChoreography.maxBeats) {
            let wait = beat.at - Date.now.timeIntervalSince(start)
            if wait > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                } catch {
                    // Cancelled (e.g. background time ran out): don't leave him mid-step.
                    if current == generation {
                        await send(IslandSceneStore.shared.current.resting(), storage: storage)
                    }
                    return false
                }
            }
            guard current == generation else { return false }
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
        }
    }

    // MARK: Helpers

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
