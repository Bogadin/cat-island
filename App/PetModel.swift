import ActivityKit
import Combine
import Foundation
import UIKit

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
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var tickCount = 0

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
        #if DEBUG
        // Unit tests use the app as a host; don't start a Live Activity there.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        Task { await syncIsland(allowStart: true) }
    }

    /// Lightweight clock tick from the UI (once per second) so reactions expire on time.
    func tick() {
        let newNow = Date.now
        now = newNow
        tickCount += 1
        if newNow.timeIntervalSince(state.lastUpdated) > 60 {
            let oldBase = PersonalityEngine.baseMood(for: state)
            state = PersonalityEngine.advance(state, to: newNow)
            // Time alone changed his mood (sleepy, bored, woke up…): keep the island in step.
            if PersonalityEngine.baseMood(for: state) != oldBase {
                Task { await syncIsland(allowStart: false) }
            }
        }
        if tickCount % 5 == 0 {
            refreshIslandStatus()
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
        // Keep running briefly if the user leaves the app, so the island can settle after the reaction.
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "murzik.settle") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
        settleTask = Task { [storage] in
            await MurzikActions.syncLiveActivity(with: newState, storage: storage)
            if !Task.isCancelled { self.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: Dynamic Island

    func setIslandEnabled(_ enabled: Bool) {
        storage.islandEnabled = enabled
        if !enabled { islandStatus = .off }
        objectWillChange.send()
        Task { await syncIsland(allowStart: true) }
    }

    private func syncIsland(allowStart: Bool) async {
        do {
            try await LiveActivityController.reconcile(storage: storage, allowStart: allowStart)
            if case .failed = islandStatus { islandStatus = .off }
        } catch {
            islandStatus = .failed
        }
        refreshIslandStatus()
    }

    private func refreshIslandStatus() {
        if case .failed = islandStatus, storage.islandEnabled,
           LiveActivityController.areActivitiesEnabled, !LiveActivityController.isRunning {
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
