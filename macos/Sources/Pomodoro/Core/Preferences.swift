import Foundation
import Combine

/// The QML service read durations from an always-empty `settings` object, so
/// it was fixed at 25/5/15/4. This app exposes them for real, but keeps the
/// identical clamping rules from `configuredMinutes` and `configuredCount` so
/// any value round-trips the same.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: "shortBreakMinutes") } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    @Published var longBreakEvery: Int { didSet { defaults.set(longBreakEvery, forKey: "longBreakEvery") } }
    @Published var showFloatingTimer: Bool { didSet { defaults.set(showFloatingTimer, forKey: "showFloatingTimer") } }
    @Published var menuBarShowsCountdown: Bool { didSet { defaults.set(menuBarShowsCountdown, forKey: "menuBarShowsCountdown") } }
    @Published var playAlarmSound: Bool { didSet { defaults.set(playAlarmSound, forKey: "playAlarmSound") } }

    private init() {
        let store = UserDefaults.standard
        focusMinutes = Self.minutes(store, "focusMinutes", 25)
        shortBreakMinutes = Self.minutes(store, "shortBreakMinutes", 5)
        longBreakMinutes = Self.minutes(store, "longBreakMinutes", 15)
        longBreakEvery = Self.count(store, "longBreakEvery", 4)
        showFloatingTimer = Self.flag(store, "showFloatingTimer", true)
        menuBarShowsCountdown = Self.flag(store, "menuBarShowsCountdown", true)
        playAlarmSound = Self.flag(store, "playAlarmSound", true)
    }

    private static func minutes(_ store: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        guard store.object(forKey: key) != nil else { return fallback }
        let value = store.integer(forKey: key)
        return value >= 1 ? max(1, min(240, value)) : fallback
    }

    private static func count(_ store: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        guard store.object(forKey: key) != nil else { return fallback }
        let value = store.integer(forKey: key)
        return value >= 1 ? max(1, min(12, value)) : fallback
    }

    private static func flag(_ store: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
    }

    func duration(for phase: Phase) -> Int {
        switch phase {
        case .focus: return focusMinutes * 60
        case .short: return shortBreakMinutes * 60
        case .long: return longBreakMinutes * 60
        }
    }
}
