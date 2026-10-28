import ActivityKit
import Foundation

#if !WIDGET_EXTENSION

/// Starts, updates and ends Murzik's Live Activity. App process only.
enum LiveActivityController {
    enum StartError: Error {
        case disabledBySystem
    }

    /// iOS keeps a Live Activity in the Dynamic Island for at most 8 hours.
    static let maximumDuration: TimeInterval = 8 * 3600

    static var runningActivities: [Activity<MurzikAttributes>] {
        Activity<MurzikAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    static var isRunning: Bool { !runningActivities.isEmpty }

    static var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func content(for state: PetState, now: Date) -> ActivityContent<MurzikAttributes.ContentState> {
        let contentState = MurzikAttributes.ContentState(state: state, now: now)
        // Stale date = the moment Murzik gets hungry; the widget then shows the hungry face.
        let staleDate: Date? = contentState.hungryAt > now ? contentState.hungryAt : nil
        return ActivityContent(state: contentState, staleDate: staleDate, relevanceScore: 100)
    }

    /// Requests a new Live Activity. Must be called while the app is in the foreground.
    @discardableResult
    static func start(state: PetState, now: Date = .now) throws -> Activity<MurzikAttributes> {
        guard areActivitiesEnabled else { throw StartError.disabledBySystem }
        let activity = try Activity.request(
            attributes: MurzikAttributes(name: Strings.name),
            content: content(for: state, now: now),
            pushType: nil
        )
        PetStorage().islandStartedAt = now
        return activity
    }

    static func update(state: PetState, now: Date = .now) async {
        let newContent = content(for: state, now: now)
        for activity in runningActivities {
            await activity.update(newContent)
        }
    }

    static func endAll() async {
        for activity in Activity<MurzikAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        PetStorage().islandStartedAt = nil
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
    static func syncLiveActivity(with state: PetState, storage: PetStorage = PetStorage()) async {
        guard LiveActivityController.isRunning else { return }
        await LiveActivityController.update(state: state, now: .now)

        guard let reaction = state.lastReaction else { return }
        let settleDate = reaction.date.addingTimeInterval(PersonalityEngine.reactionDuration + 0.2)
        let delay = settleDate.timeIntervalSinceNow
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        let now = Date.now
        let latest = PersonalityEngine.advance(storage.load(now: now), to: now)
        await LiveActivityController.update(state: latest, now: now)
    }
}

#endif
