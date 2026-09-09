import Foundation

/// Milliseconds since the Unix epoch. The history format was defined by the
/// QML service, which wrote `Date.now()` values, so the native app keeps the
/// same unit rather than converting to `Date` on disk.
typealias EpochMillis = Double

func nowMillis() -> EpochMillis { Date().timeIntervalSince1970 * 1000 }

enum Phase: String, Codable, CaseIterable {
    case focus, short, long

    /// Matches `Service.normalizePhase`: anything unrecognized becomes focus.
    init(normalizing raw: String?) {
        switch raw {
        case "short": self = .short
        case "long": self = .long
        default: self = .focus
        }
    }

    var label: String {
        switch self {
        case .focus: return "Focus"
        case .short: return "Short break"
        case .long: return "Long break"
        }
    }

    var shortLabel: String {
        switch self {
        case .focus: return "Focus"
        case .short: return "Short"
        case .long: return "Long"
        }
    }
}

enum EntryStatus: String, Codable {
    case completed, skipped, reset, running, paused, interrupted

    /// Matches `Service.entryStatus`, including the legacy `completed: true`
    /// boolean that predates the status field. QML treated an empty status
    /// string as absent, so an empty value falls back the same way here.
    init(normalizing raw: String?, legacyCompleted: Bool?) {
        let stored = raw ?? ""
        let value = stored.isEmpty ? (legacyCompleted == true ? "completed" : "interrupted") : stored
        self = EntryStatus(rawValue: value) ?? .interrupted
    }

    var label: String {
        switch self {
        case .completed: return "Completed"
        case .skipped: return "Skipped"
        case .reset: return "Reset"
        case .running: return "Running"
        case .paused: return "Paused"
        case .interrupted: return "Interrupted"
        }
    }
}

/// One uninterrupted run of the clock. A phase that was paused and resumed
/// contributes several segments, which is what makes the day timeline show
/// real working time rather than wall-clock spans.
struct Segment: Equatable {
    var startedAt: EpochMillis
    var endedAt: EpochMillis

    var durationSeconds: Double { max(0, (endedAt - startedAt) / 1000) }
}

struct SessionEntry: Identifiable, Equatable {
    var id: String
    var phase: Phase
    var status: EntryStatus
    var startedAt: EpochMillis
    var endedAt: EpochMillis
    var plannedSeconds: Int
    var activeSeconds: Int
    var segments: [Segment]
    var note: String
    /// True only for the synthetic entry representing the phase in progress.
    var isLive: Bool = false

    var completed: Bool { status == .completed }
    var focusedSeconds: Int { phase == .focus ? activeSeconds : 0 }

    /// Matches `Service.isCompletedFocusSession`.
    var isCompletedFocus: Bool {
        phase == .focus && status == .completed && activeSeconds > 0
    }
}

extension String {
    /// Matches `Service.normalizeNote`: collapse whitespace, trim, cap at 240.
    var normalizedNote: String {
        let collapsed = self
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(240))
    }
}
