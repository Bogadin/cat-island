import ActivityKit
import Combine
import Foundation

/// UI-facing model. The source of truth is `PetStorage`; this object mirrors it for SwiftUI
/// and keeps the Live Activity in sync.
@MainActor
final class PetModel: ObservableObject {
    enum IslandStatus: Equatable {
        case off
        case running(endsAt: Date?)
        case disabledBySystem
        case failed
    }

    @Published private(set) var state: PetState
    @Published private(set) var now: Date
    @Published private(set) var islandStatus: IslandStatus = .off
    @Published private(set) var lastAction: (action: PetAction, date: Date)?

    private let storage: PetStorage
    private var observers: [NSObjectProtocol] = []
    private var settleTask: Task<Void, Never>?

    init(storage: PetStorage = PetStorage()) {
        self.storage = storage
        let now = Date.now
        self.now = now
        self.state = PersonalityEngine.advance(storage.load(now: now), to: now)
        observers.append(NotificationCenter.default.addObserver(
            forName: .murzikStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var mood: MurzikMood { PersonalityEngine.mood(for: state, at: now) }
    var islandEnabled: Bool { storage.islandEnabled }

    // MARK: Lifecycle

    /// Call when the app becomes active: catches up on elapsed time and restores the island.
    func becameActive() {
        reload()
        Task { await syncIsland(allowStart: true) }
    }

    /// Lightweight clock tick from the UI (once per second) so reactions expire on time.
    func tick() {
        let newNow = Date.now
        now = newNow
        if newNow.timeIntervalSince(state.lastUpdated) > 60 {
            state = PersonalityEngine.advance(state, to: newNow)
        }
    }

    func reload() {
        let newNow = Date.now
        now = newNow
        state = PersonalityEngine.advance(storage.load(now: newNow), to: newNow)
        refreshIslandStatus()
    }

    // MARK: Actions

    func perform(_ action: PetAction) {
        let newState = MurzikActions.apply(action, storage: storage)
        state = newState
        now = .now
        lastAction = (action, now)
        settleTask?.cancel()
        settleTask = Task { [storage] in
            await MurzikActions.syncLiveActivity(with: newState, storage: storage)
        }
    }

    // MARK: Dynamic Island

    func setIslandEnabled(_ enabled: Bool) {
        storage.islandEnabled = enabled
        objectWillChange.send()
        Task {
            if enabled {
                await syncIsland(allowStart: true)
            } else {
                await LiveActivityController.endAll()
                refreshIslandStatus()
            }
        }
    }

    private func syncIsland(allowStart: Bool) async {
        defer { refreshIslandStatus() }
        guard storage.islandEnabled else { return }
        guard LiveActivityController.areActivitiesEnabled else { return }

        let current = PersonalityEngine.advance(storage.load(now: .now), to: .now)
        if LiveActivityController.isRunning {
            await LiveActivityController.update(state: current)
        } else if allowStart {
            do {
                // Clear any ended activity lingering on the Lock Screen before starting a fresh one.
                await LiveActivityController.endAll()
                try LiveActivityController.start(state: current)
            } catch {
                islandStatus = .failed
                return
            }
        }
    }

    private func refreshIslandStatus() {
        if case .failed = islandStatus, storage.islandEnabled, !LiveActivityController.isRunning {
            return
        }
        if !LiveActivityController.areActivitiesEnabled {
            islandStatus = .disabledBySystem
        } else if LiveActivityController.isRunning {
            let endsAt = storage.islandStartedAt?.addingTimeInterval(LiveActivityController.maximumDuration)
            islandStatus = .running(endsAt: endsAt)
        } else {
            islandStatus = .off
        }
    }
}
