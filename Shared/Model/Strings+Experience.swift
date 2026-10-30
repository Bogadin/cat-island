import Foundation

/// Text for the redesigned app experience (Hebrew). Murzik is male; she is addressed in the feminine.
extension Strings {
    // MARK: Greetings

    static func greetingTitle(_ greeting: Greeting) -> String {
        switch greeting {
        case .firstMeeting: return "נעים מאוד, אני מורזיק!"
        case .goodMorning: return "בוקר טוב, אהובה!"
        case .missedYou: return "התגעגעתי אלייך!"
        case .lateNight: return "התגעגעתי אלייך…"
        }
    }

    static func greetingSubtitle(_ greeting: Greeting) -> String {
        switch greeting {
        case .firstMeeting: return "מעכשיו אני החתול שלך. ליטוף קטן?"
        case .goodMorning: return "חיכיתי שתתעוררי. מה נעשה היום?"
        case let .missedYou(hours):
            if hours >= 24 { return "לא ראיתי אותך יותר מיום שלם. אל תלכי שוב!" }
            if hours >= 6 { return "חיכיתי לך ליד הדלת כל היום" }
            return "טוב שחזרת, היה לי משעמם בלעדייך"
        case .lateNight: return "כבר מאוחר. בואי, נתכרבל קצת לפני השינה"
        }
    }

    static func greetingSymbol(_ greeting: Greeting) -> String {
        switch greeting {
        case .firstMeeting: return "pawprint.fill"
        case .goodMorning: return "sun.horizon.fill"
        case .missedYou: return "heart.fill"
        case .lateNight: return "moon.stars.fill"
        }
    }

    // MARK: Surprises

    static let surpriseMessages: [String] = [
        "את האדם האהוב עליי בעולם",
        "חשבתי עלייך עכשיו",
        "את יודעת שאת מושלמת?",
        "מיאו = אני אוהב אותך בשפת חתולים",
        "שמרתי לך מקום חם על הספה",
        "כשאת מחייכת, הזנב שלי מתנפנף",
        "את הכי יפה פה (אחריי, כמובן)",
        "רק רציתי להגיד שטוב לי איתך",
        "מצמוץ איטי = נשיקה של חתולים",
        "בואי נעשה היום משהו כיף ביחד",
    ]

    static func surpriseMessage(_ index: Int) -> String {
        surpriseMessages[Int(index.magnitude % UInt(surpriseMessages.count))]
    }

    static func giftName(_ gift: Gift) -> String {
        switch gift {
        case .flower: return "פרח מהגינה"
        case .leaf: return "עלה שלכת יפה"
        case .feather: return "נוצה רכה"
        case .star: return "כוכב קטן שמצא"
        case .heart: return "לב גדול"
        case .yarn: return "כדור צמר"
        }
    }

    static let giftTitle = "מורזיק הביא לך מתנה!"
    static let surpriseTitle = "מורזיק רוצה להגיד לך משהו"
    static let thanks = "תודה, מתוק"

    // MARK: Stage & interactions

    static let purring = "גררר… גררר…"
    static let purrHint = "החזיקי עליו את האצבע כדי שיגרגר"
    static let bedtimeMessage = "כבר מאוחר… נלך לישון?"
    static let morningMessage = "מתמתח לאור הבוקר"
    static let toyFeather = "נוצה"
    static let toyLaser = "לייזר"
    static let toyHint = "גררי את הצעצוע ומורזיק ירדוף אחריו"
    static let toyDone = "סיימנו"
    static let toyCaught = "תפסתי!"
    static let catLabel = "מורזיק, החתול שלך"

    static func phaseTitle(_ phase: DayPhase) -> String {
        switch phase {
        case .morning: return "בוקר"
        case .day: return "צהריים"
        case .evening: return "ערב"
        case .night: return "לילה"
        }
    }

    // MARK: Bond

    static let loveToday = "אהבה היום"
    static let streak = "ימים ברצף"
    static let gifts = "מתנות"
    static let totalLove = "סך הכול אהבה"
    static let purrTime = "דקות גרגור"
    static let todaysMoods = "מצבי הרוח של היום"
    static let noMoodsYet = "עוד לא היה היום מספיק זמן לגלות"

    static func streakDays(_ days: Int) -> String {
        days == 1 ? "יום אחד" : "\(days) ימים"
    }

    // MARK: Settings

    static let settingsTitle = "הגדרות"
    static let settingsDone = "סיום"
    static let settingsOpen = "הגדרות"
    static let sectionWhereHeLives = "איפה מורזיק גר"
    static let sectionFeel = "חוויה"
    static let sectionUs = "אני ומורזיק"
    static let walkerTitle = "מורזיק מטייל במסך"
    static let walkerSubtitle = "מסתובב ליד ה-Dynamic Island כשהאפליקציה פתוחה"
    static let soundTitle = "צלילים"
    static let soundSubtitle = "גרגור עדין (מכבד את מתג השקט)"
    static let hapticsTitle = "רטט"
    static let hapticsSubtitle = "מרגישים את הגרגור בכף היד"
    static let showNameTitle = "להציג את השם שלו"
    static let showNameSubtitle = "השם \"מורזיק\" בראש המסך"
    static let openSystemSettings = "פתיחת הגדרות האייפון"
    static let islandSubtitle = "פעילות חיה למעלה במסך ובמסך הנעילה"
    static let madeWithLove = "נעשה באהבה, במיוחד בשבילך"
}
