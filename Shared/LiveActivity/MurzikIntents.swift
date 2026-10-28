import AppIntents
import Foundation

// Buttons inside the expanded Dynamic Island and the Lock Screen Live Activity.
// `LiveActivityIntent` makes iOS run `perform()` in the app's process (launching it
// in the background if needed), so the extension build compiles them as no-ops.

struct PetMurzikIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pet Murzik"
    static var description = IntentDescription("Give Murzik a gentle pet.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let state = MurzikActions.apply(.pet)
        await MurzikActions.syncLiveActivity(with: state)
        #endif
        return .result()
    }
}

struct FeedMurzikIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Feed Murzik"
    static var description = IntentDescription("Give Murzik something tasty.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let state = MurzikActions.apply(.feed)
        await MurzikActions.syncLiveActivity(with: state)
        #endif
        return .result()
    }
}
