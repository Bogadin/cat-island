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
    /// Visits, love streak, gifts and mood diary.
    @Published private(set) var bond: BondState
    /// Welcome card to show (set when she opens the app after a while).
    @Published private(set) var greeting: Greeting?
    /// A spontaneous cute moment to show (gift or sweet message).
    @Published private(set) var surprise: Surprise?

    /// Calendar used for the day rhythm and streaks.
    var calendar: Calendar = .current
    /// Debug/UI-test override of the time of day (launch argument `-uitest-phase evening`).
    private(set) var phaseOverride: DayPhase?
    private var activeSince: Date = .now

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
        var initialBond = storage.loadBond()
        #if DEBUG
        Self.applyUITestFixtures(storage: storage, bond: &initialBond, now: now)
        #endif
        self.bond = initialBond
        #if DEBUG
        phaseOverride = UserDefaults.standard.string(forKey: "uitest-phase").flatMap(DayPhase.init(rawValue:))
        #endif
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.wentToBackground() }
        })
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

    /// The mood shown in the app: engine mood + daily rhythm, and a loving welcome while greeting her.
    var mood: MurzikMood {
        if greeting != nil, !state.isSleeping, !hasActiveReaction { return .loving }
        return PersonalityEngine.displayMood(for: state, at: now, calendar: calendar)
    }

    private var hasActiveReaction: Bool {
        state.lastReaction.map { PersonalityEngine.isReactionActive($0, at: now) } ?? false
    }

    var dayPhase: DayPhase { phaseOverride ?? PersonalityEngine.dayPhase(at: now, calendar: calendar) }
    var loveToday: Int { PersonalityEngine.loveToday(bond, at: now, calendar: calendar) }
    var streak: Int { PersonalityEngine.currentStreak(bond, at: now, calendar: calendar) }
    var moodsToday: [MoodSample] { PersonalityEngine.moodsToday(bond, at: now, calendar: calendar) }
    var isBedtime: Bool {
        if let phaseOverride { return phaseOverride == .night && !state.isSleeping }
        return PersonalityEngine.isBedtime(for: state, at: now, calendar: calendar)
    }
    var islandEnabled: Bool { storage.islandEnabled }

    // MARK: Lifecycle

    /// Call when the app becomes active: catches up on elapsed time and restores the island.
    func becameActive() {
        reload()
        let current = Date.now
        if greeting == nil, let welcome = PersonalityEngine.greeting(bond: bond, at: current, calendar: calendar) {
            greeting = welcome
        }
        activeSince = current
        updateBond { PersonalityEngine.recordVisit($0, at: current) }
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
        let currentMood = mood
        updateBond { PersonalityEngine.recordMood(currentMood, in: $0, at: newNow) }
        if tickCount % 40 == 0 {
            considerSurprise()
        }
    }

    private func wentToBackground() {
        let current = Date.now
        updateBond { PersonalityEngine.recordVisit($0, at: current) }
    }

    private func updateBond(_ change: (BondState) -> BondState) {
        let newBond = change(bond)
        guard newBond != bond else { return }
        bond = newBond
        storage.saveBond(newBond)
    }

    // MARK: Moments

    func dismissGreeting() {
        greeting = nil
    }

    func dismissSurprise() {
        surprise = nil
    }

    /// Rolls the dice for a spontaneous cute moment (only while she is looking and nothing else is showing).
    private func considerSurprise() {
        guard greeting == nil, surprise == nil, now.timeIntervalSince(activeSince) > 20 else { return }
        if let lastAction, now.timeIntervalSince(lastAction.date) < PersonalityEngine.reactionDuration { return }
        guard let moment = PersonalityEngine.surprise(
            for: state, bond: bond, at: now,
            roll: Double.random(in: 0..<1), pick: Int.random(in: 0..<10_000)
        ) else { return }
        showSurprise(moment)
    }

    func showSurprise(_ moment: Surprise) {
        let current = Date.now
        surprise = moment
        updateBond { PersonalityEngine.applySurprise(moment, to: $0, at: current) }
    }

    /// A purring session (long press / stroke) ended.
    func recordPurr(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        updateBond { PersonalityEngine.recordPurr($0, seconds: seconds) }
    }

    #if DEBUG
    /// Launch arguments used by UI tests to show specific moments.
    private static func applyUITestFixtures(storage: PetStorage, bond: inout BondState, now: Date) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitest-missed") {
            let calendar = Calendar.current
            var b = BondState(
                lastVisit: now.addingTimeInterval(-9 * 3600),
                lastLoveDate: calendar.date(byAdding: .day, value: -1, to: now),
                streakDays: 4, loveOnLastDay: 9, totalLove: 57, giftsReceived: 3,
                lastSurprise: now.addingTimeInterval(-3600), purrSeconds: 640
            )
            let moods: [MurzikMood] = [.sleeping, .hungry, .happy, .playful, .loving, .idle]
            for (i, mood) in moods.enumerated() {
                let date = now.addingTimeInterval(Double(i - moods.count) * 600)
                if calendar.isDate(date, inSameDayAs: now) {
                    b.moodHistory.append(MoodSample(mood: mood, date: date))
                }
            }
            bond = b
            storage.saveBond(b)
        }
    }
    #endif

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
        if action == .pet || action == .feed || action == .play {
            let current = now
            updateBond { PersonalityEngine.recordLove($0, at: current, calendar: calendar) }
        }
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
