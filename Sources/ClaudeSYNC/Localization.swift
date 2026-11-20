import ClaudeSYNCCore
import Foundation

struct L10n: Equatable {
    let isTurkish: Bool

    init(isTurkish: Bool) {
        self.isTurkish = isTurkish
    }

    init(language: AppLanguage) {
        self.isTurkish = language.resolvedIsTurkish
    }

    @inline(__always)
    func t(_ turkish: String, _ english: String) -> String {
        isTurkish ? turkish : english
    }

    func percent(_ value: Int) -> String {
        isTurkish ? "%\(value)" : "\(value)%"
    }

    func relativeDate(_ date: Date) -> String {
        LocalizedDateFormatter.relativeString(from: date, isTurkish: isTurkish)
    }

    func countdown(until date: Date) -> String {
        LocalizedDateFormatter.countdownString(until: date, isTurkish: isTurkish)
    }

    func shortClock(_ date: Date) -> String {
        LocalizedDateFormatter.shortClockTime(date, isTurkish: isTurkish)
    }

    func compactReset(_ date: Date) -> String {
        LocalizedDateFormatter.compactResetTime(date, isTurkish: isTurkish)
    }

    func profileDisplayName(_ rawName: String, isDefault: Bool) -> String {
        if isDefault && (rawName == "Ana Profil" || rawName == "Primary Profile") {
            return isTurkish ? "Ana Profil" : "Primary Profile"
        }
        if rawName == "2. Profil" || rawName == "Profile 2" {
            return isTurkish ? "2. Profil" : "Profile 2"
        }
        return rawName
    }

    func languageName(_ lang: AppLanguage) -> String {
        switch lang {
        case .system: return t("Sistem", "System")
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }
}
