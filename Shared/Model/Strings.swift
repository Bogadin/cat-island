import Foundation

/// All user-facing text in one place (Hebrew). Murzik is male; the user is addressed in the feminine.
enum Strings {
    static let name = "מורזיק"

    static func moodTitle(_ mood: MurzikMood) -> String {
        switch mood {
        case .idle: return "רגוע"
        case .happy: return "שמח"
        case .sleepy: return "ישנוני"
        case .sleeping: return "ישן"
        case .playful: return "שובב"
        case .hungry: return "רעב"
        case .loving: return "אוהב"
        case .surprised: return "מופתע"
        case .blinking: return "ממצמץ"
        case .excited: return "נלהב"
        }
    }

    static func moodMessage(_ mood: MurzikMood) -> String {
        switch mood {
        case .idle: return "מסתכל על העולם בשלווה"
        case .happy: return "מגרגר מאושר"
        case .sleepy: return "העיניים שלו נעצמות…"
        case .sleeping: return "ששש… הוא ישן"
        case .playful: return "מתכנן תעלול קטן"
        case .hungry: return "מיאו! איפה האוכל?"
        case .loving: return "מתכרבל אלייך באהבה"
        case .surprised: return "מה זה היה?!"
        case .blinking: return "ממצמץ אלייך לאט"
        case .excited: return "קופץ מרוב שמחה!"
        }
    }

    static func actionTitle(_ action: PetAction) -> String {
        switch action {
        case .pet: return "ליטוף"
        case .feed: return "אוכל"
        case .play: return "משחק"
        case .sleep: return "לישון"
        case .wake: return "להעיר"
        }
    }

    static let fullness = "שובע"
    static let energy = "אנרגיה"
    static let happiness = "שמחה"
    static let hungryIn = "רעב בעוד"
    static let hungryNow = "רעב עכשיו"

    static let islandTitle = "מורזיק ב-Dynamic Island"
    static let islandOn = "מורזיק גר עכשיו למעלה במסך"
    static let islandOff = "הפעילי כדי שמורזיק יופיע למעלה"
    static let islandEndsIn = "ימשיך עוד"
    static let islandRestartNote = "iOS מכבה אחרי 8 שעות. פתיחת האפליקציה מחזירה אותו."
    static let islandDisabledBySystem = "פעילויות חיות כבויות בהגדרות האייפון"
    static let islandStartFailed = "לא הצלחתי להפעיל את מורזיק למעלה"
    static let tapToPet = "געי בו כדי ללטף"
}
