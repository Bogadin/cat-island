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

    nonisolated static func content(for state: PetState, now: Date) -> ActivityContent<MurzikAttributes.ContentState> {
        let contentState = MurzikAttributes.ContentState(state: state, now: now)
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

    nonisolated static func update(state: PetState, now: Date = .now) async {
        let newContent = content(for: state, now: now)
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

    /// If the user swipes Murzik away, respect it: turn the island setting off
    /// instead of bringing him back on the next app launch.
    private static func observe(_ activity: Activity<MurzikAttributes>) {
        guard !observed.contains(activity.id) else { return }
        observed.insert(activity.id)
        let id = activity.id
        Task { @MainActor in
            for await state in activity.activityStateUpdates where state == .dismissed {
                if !LiveActivityController.endingOnPurpose.contains(id) {
                    PetStorage().islandEnabled = false
                    PetStorage().islandStartedAt = nil
                    NotificationCenter.default.post(name: .murzikStateDidChange, object: nil)
                }
                break
            }
        }
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
        // Also restarts the island if it expired (e.g. a button on an ended Lock Screen card).
        try? await LiveActivityController.reconcile(storage: storage, allowStart: true)
        guard LiveActivityController.isRunning else { return }

        guard let reaction = state.lastReaction else { return }
        let settleDate = reaction.date.addingTimeInterval(PersonalityEngine.reactionDuration + 0.2)
        let delay = settleDate.timeIntervalSinceNow
        if delay > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return // superseded by a newer action
            }
        }
        let now = Date.now
        let latest = PersonalityEngine.advance(storage.load(now: now), to: now)
        await LiveActivityController.update(state: latest, now: now)
    }
}

#endif
