import Foundation

/// Local, offline persistence of Murzik's state (UserDefaults, JSON-encoded).
///
/// Live Activity button intents run in the app's process (`LiveActivityIntent`),
/// so the app's standard defaults are shared between the UI and the Dynamic Island
/// without needing an App Group (App Groups are unreliable with free sideload signing).
struct PetStorage {
    static let stateKey = "murzik.state.v1"
    static let islandEnabledKey = "murzik.island.enabled"
    static let islandStartedKey = "murzik.island.startedAt"
    static let bondKey = "murzik.bond.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(now: Date = .now) -> PetState {
        guard
            let data = defaults.data(forKey: Self.stateKey),
            let state = try? JSONDecoder().decode(PetState.self, from: data)
        else {
            return PetState(lastUpdated: now)
        }
        return state
    }

    func save(_ state: PetState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }

    /// Visits, love streak, gifts and mood diary (separate key, so the state JSON stays as it was).
    func loadBond() -> BondState {
        guard
            let data = defaults.data(forKey: Self.bondKey),
            let bond = try? JSONDecoder().decode(BondState.self, from: data)
        else {
            return BondState()
        }
        return bond
    }

    func saveBond(_ bond: BondState) {
        if let data = try? JSONEncoder().encode(bond) {
            defaults.set(data, forKey: Self.bondKey)
        }
    }

    var islandEnabled: Bool {
        get { defaults.object(forKey: Self.islandEnabledKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.islandEnabledKey) }
    }

    var islandStartedAt: Date? {
        get { defaults.object(forKey: Self.islandStartedKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.islandStartedKey) }
    }
}

extension Notification.Name {
    /// Posted (on the main queue) whenever Murzik's state is changed outside the UI, e.g. by a Live Activity button.
    static let murzikStateDidChange = Notification.Name("murzikStateDidChange")
}
