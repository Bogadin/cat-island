import ActivityKit
import Foundation

#if !WIDGET_EXTENSION

/// Starts, updates and ends Murzik's Live Activity. App process only.
/// All mutations go through `reconcile`, serialized on the main actor by `IslandQueue`,
/// so quick toggles or overlapping app/intent calls can never start two activities.
@MainActor
enum LiveActivityController {
    enum StartError: Error {
        case disabledBySystem
    }

    /// iOS keeps a Live Activity in the Dynamic Island for at most 8 hours.
    static let maximumDuration: TimeInterval = 8 * 3600

    private static var endingOnPurpose = Set<String>()
    private static var observed = Set<String>()

    nonisolated static var runningActivities: [Activity<MurzikAttributes>] {
        Activity<MurzikAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    nonisolated static var isRunning: Bool { !runningActivities.isEmpty }

    nonisolated static var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// - Parameter scene: Murzik's place and pose on the island; nil keeps him where he last was,
    ///   sitting in his mood pose.
    nonisolated static func content(
        for state: PetState,
        now: Date,
        scene: IslandScene? = nil
    ) -> ActivityContent<MurzikAttributes.ContentState> {
        var contentState = MurzikAttributes.ContentState(state: state, now: now)
        let base = scene ?? IslandSceneStore.shared.current.resting()
        contentState.stage = IslandSceneStore.withTrail(base, hungryAt: contentState.hungryAt)
        // Stale date = the moment Murzik gets hungry; the widget then shows the hungry face.
        let staleDate: Date? = contentState.hungryAt > now ? contentState.hungryAt : nil
        return ActivityContent(state: contentState, staleDate: staleDate, relevanceScore: 100)
    }

    /// Brings the Live Activity in line with the stored state and the user's setting:
    /// ends it when disabled, updates it when running, (re)starts it when allowed.
    static func reconcile(storage: PetStorage = PetStorage(), allowStart: Bool) async throws {
        try await IslandQueue.run {
            try await LiveActivityController.reconcileNow(storage: storage, allowStart: allowStart)
        }
    }

    private static func reconcileNow(storage: PetStorage, allowStart: Bool) async throws {
        guard storage.islandEnabled, areActivitiesEnabled else {
            if !storage.islandEnabled { await endAllNow(storage: storage) }
            return
        }
        let now = Date.now
        let current = PersonalityEngine.advance(storage.load(now: now), to: now)
        if isRunning {
            for activity in runningActivities { observe(activity) }
            await update(state: current, now: now)
            return
        }
        guard allowStart else { return }
        // Clear an expired card lingering on the Lock Screen before starting a fresh one.
        await endAllNow(storage: storage)
        guard storage.islandEnabled, !isRunning else { return }
        guard areActivitiesEnabled else { throw StartError.disabledBySystem }
        let activity = try Activity.request(
            attributes: MurzikAttributes(name: Strings.name),
            content: content(for: current, now: now),
            pushType: nil
        )
        storage.islandStartedAt = now
        observe(activity)
    }

    nonisolated static func update(state: PetState, now: Date = .now, scene: IslandScene? = nil) async {
        let newContent = content(for: state, now: now, scene: scene)
        if let sent = newContent.state.stage { IslandSceneStore.shared.current = sent }
        for activity in runningActivities {
            await activity.update(newContent)
        }
    }

    static func endAll(storage: PetStorage = PetStorage()) async {
        await IslandQueue.runQuietly { await LiveActivityController.endAllNow(storage: storage) }
    }

    private static func endAllNow(storage: PetStorage) async {
        for activity in Activity<MurzikAttributes>.activities {
            endingOnPurpose.insert(activity.id)
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        storage.islandStartedAt = nil
    }

    /// Watches the running activities for a user swipe (see `observe`) without updating them.
    static func observeRunningActivities() {
        for activity in runningActivities { observe(activity) }
    }

    /// If the user swipes Murzik away, respect it: turn the island setting off
    /// instead of bringing him back on the next app launch.
    /// Only a dismissal straight from a live (active/stale) activity before the 8 h limit counts;
    /// the system ending it at the limit (`.ended` first) does not turn the setting off.
    private static func observe(_ activity: Activity<MurzikAttributes>) {
        guard !observed.contains(activity.id) else { return }
        observed.insert(activity.id)
        let id = activity.id
        Task { @MainActor in
            var previous = activity.activityState
            for await state in activity.activityStateUpdates {
                guard state == .dismissed else {
                    previous = state
                    continue
                }
                let wasLive = previous == .active || previous == .stale
                if wasLive, !LiveActivityController.endingOnPurpose.contains(id),
                   LiveActivityController.isBeforeMaximumDuration(storage: PetStorage()) {
                    PetStorage().islandEnabled = false
                    PetStorage().islandStartedAt = nil
                    NotificationCenter.default.post(name: .murzikStateDidChange, object: nil)
                }
                break
            }
        }
    }

    /// True while the island is clearly within its 8 h lifetime (with a minute of margin).
    private static func isBeforeMaximumDuration(storage: PetStorage, now: Date = .now) -> Bool {
        guard let started = storage.islandStartedAt else { return false }
        return now < started.addingTimeInterval(maximumDuration - 60)
    }
}

/// Runs island operations one after another on the main actor.
@MainActor
enum IslandQueue {
    private static var tail: Task<Void, Never>?

    static func run(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = tail
        let task = Task { @MainActor () -> Result<Void, Error> in
            await previous?.value
            do { try await operation(); return .success(()) } catch { return .failure(error) }
        }
        tail = Task { @MainActor in _ = await task.value }
        try await task.value.get()
    }

    static func runQuietly(_ operation: @escaping @MainActor () async -> Void) async {
        try? await run { () async throws in await operation() }
    }
}

/// The island scene last sent to the Live Activity (app process). Thread-safe; his position is
/// remembered across launches so he is where you left him.
final class IslandSceneStore: @unchecked Sendable {
    static let shared = IslandSceneStore()
    private static let key = "murzik.island.scene.v1"

    private let lock = NSLock()
    private var scene: IslandScene
    private let createdAt = Date.now

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(IslandScene.self, from: data) {
            scene = saved.resting()
        } else {
            scene = .home
        }
    }

    var current: IslandScene {
        get { lock.withLock { scene } }
        set {
            var s = newValue
            s.trailFrom = nil
            s.trailTo = nil
            lock.withLock { scene = s }
            if let data = try? JSONEncoder().encode(s) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    /// Adds the real-time paw-print trail: it fills from "just fed" (fullness 1) to `hungryAt`.
    /// The range does not depend on when the update was sent, so the trail never jumps back.
    static func withTrail(_ scene: IslandScene, hungryAt: Date) -> IslandScene {
        var s = scene
        #if DEBUG
        // UI tests: a short trail so the real-time motion is visible within seconds.
        if ProcessInfo.processInfo.arguments.contains("-uitest-fast-trail") {
            let start = shared.createdAt
            s.trailFrom = start
            s.trailTo = start.addingTimeInterval(75)
            return s
        }
        #endif
        let awakeRate = -PersonalityEngine.rates(sleeping: false).fullness
        let fullSpan = (1 - PersonalityEngine.hungryThreshold) / awakeRate * 3600
        s.trailFrom = hungryAt.addingTimeInterval(-fullSpan)
        s.trailTo = hungryAt
        return s
    }
}

/// The single entry point for changing Murzik's state, used by the app UI and by Live Activity buttons.
enum MurzikActions {
    /// Applies an action, persists it and notifies the UI. Synchronous and fast.
    @discardableResult
    static func apply(_ action: PetAction, storage: PetStorage = PetStorage(), now: Date = .now) -> PetState {
        let newState = PersonalityEngine.apply(action, to: storage.load(now: now), at: now)
        storage.save(newState)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .murzikStateDidChange, object: nil)
        }
        return newState
    }

    /// Pushes the state to the Live Activity. If a short reaction is showing,
    /// sends a second update once it is over so the island settles back to the base mood.
    @MainActor
    static func syncLiveActivity(with state: PetState, storage: PetStorage = PetStorage()) async {
        await syncLiveActivity(with: state, action: nil, storage: storage)
    }

    /// Same, for a known action (e.g. an island button): Murzik walks to that button and reacts
    /// (`IslandChoreographer`), then settles back to his base mood once the reaction is over.
    @MainActor
    static func syncLiveActivity(with state: PetState, action: PetAction?, storage: PetStorage = PetStorage()) async {
        if action != nil, storage.islandEnabled, LiveActivityController.isRunning {
            // An island button: the choreography's first beat carries the new state, so skip
            // reconcile's resting update (it would conflict with the walk).
            LiveActivityController.observeRunningActivities()
        } else {
            // Also restarts the island if it expired (e.g. a button on an ended Lock Screen card).
            try? await LiveActivityController.reconcile(storage: storage, allowStart: true)
        }
        guard LiveActivityController.isRunning else { return }
        await IslandChoreographer.react(to: action, state: state, storage: storage)
    }
}

#endif
