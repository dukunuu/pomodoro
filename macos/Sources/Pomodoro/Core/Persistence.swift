import Foundation

/// Reading and writing the two files the Qt front end owns as well. Both the
/// accepted input shapes and the emitted output are deliberately identical to
/// `Service.qml` — the README commits to no history migration, so a file
/// written here must stay loadable there and vice versa.
enum Persistence {

    // MARK: - Normalization

    /// Port of `Service.normalizedSegments`. Drops malformed spans, clamps to
    /// the owning phase, and sorts by start.
    static func normalizedSegments(_ raw: Any?,
                                   minimumStart: EpochMillis? = nil,
                                   maximumEnd: EpochMillis? = nil) -> [Segment] {
        guard let array = raw as? [Any] else { return [] }
        var result: [Segment] = []
        for item in array {
            guard let dict = item as? [String: Any] else { continue }
            guard var startedAt = number(dict["startedAt"]),
                  var endedAt = number(dict["endedAt"]),
                  startedAt.isFinite, endedAt.isFinite,
                  startedAt > 0, endedAt > startedAt else { continue }
            if let minimum = minimumStart, minimum > 0 { startedAt = max(startedAt, minimum) }
            if let maximum = maximumEnd, maximum > 0 { endedAt = min(endedAt, maximum) }
            guard endedAt > startedAt else { continue }
            result.append(Segment(startedAt: startedAt, endedAt: endedAt))
        }
        result.sort { $0.startedAt < $1.startedAt }
        return result
    }

    /// Port of `Service.normalizedSessions`. `durationFor` supplies the
    /// fallback planned length for entries written before that field existed.
    static func normalizedSessions(_ raw: Any?, durationFor: (Phase) -> Int) -> [SessionEntry] {
        guard let array = raw as? [Any] else { return [] }
        var result: [SessionEntry] = []
        for (index, item) in array.enumerated() {
            guard let dict = item as? [String: Any] else { continue }
            let phase = Phase(normalizing: dict["phase"] as? String)
            let status = EntryStatus(normalizing: dict["status"] as? String,
                                     legacyCompleted: dict["completed"] as? Bool)

            guard let endedAt = number(dict["endedAt"]), endedAt.isFinite, endedAt > 0 else { continue }
            var startedAt = number(dict["startedAt"]) ?? .nan
            if !startedAt.isFinite || startedAt <= 0 { startedAt = endedAt }
            guard startedAt <= endedAt else { continue }

            var planned = number(dict["plannedSeconds"]) ?? .nan
            if !planned.isFinite || planned <= 0 { planned = Double(durationFor(phase)) }

            var active = number(dict["activeSeconds"]) ?? number(dict["focusedSeconds"]) ?? .nan
            if !active.isFinite || active < 0 { active = 0 }
            let activeSeconds = Int(active.rounded(.down))
            // A completed phase with no measured time is a corrupt row, not a
            // zero-length session; QML skipped these and so do we.
            if status == .completed && activeSeconds <= 0 { continue }

            var segments = normalizedSegments(dict["segments"],
                                              minimumStart: startedAt,
                                              maximumEnd: endedAt)
            if segments.isEmpty && activeSeconds > 0 {
                segments.append(Segment(startedAt: startedAt,
                                        endedAt: min(endedAt, startedAt + Double(activeSeconds) * 1000)))
            }

            let id = (dict["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? "legacy-\(index)-\(Int64(endedAt))"

            result.append(SessionEntry(
                id: id,
                phase: phase,
                status: status,
                startedAt: startedAt,
                endedAt: endedAt,
                plannedSeconds: Int(planned.rounded(.down)),
                activeSeconds: activeSeconds,
                segments: segments,
                note: phase == .focus ? ((dict["note"] as? String) ?? "").normalizedNote : ""
            ))
        }
        return result
    }

    // MARK: - History

    /// Returns nil when the file is absent or unparseable, which the service
    /// treats as "fall back to the sessions embedded in timer state".
    static func parseHistory(_ raw: String?, durationFor: (Phase) -> Int) -> [SessionEntry]? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let array = parsed as? [Any] {
            return normalizedSessions(array, durationFor: durationFor)
        }
        guard let object = parsed as? [String: Any] else { return nil }
        if let entries = object["entries"] as? [Any] {
            return normalizedSessions(entries, durationFor: durationFor)
        }
        if let sessions = object["sessions"] as? [Any] {
            return normalizedSessions(sessions, durationFor: durationFor)
        }
        return nil
    }

    static func historyJSON(_ entries: [SessionEntry]) -> String {
        let snapshot: [String: Any] = [
            "version": 1,
            "entries": entries.map(encode)
        ]
        return json(snapshot)
    }

    static func encode(_ entry: SessionEntry) -> [String: Any] {
        [
            "id": entry.id,
            "phase": entry.phase.rawValue,
            "status": entry.status.rawValue,
            "completed": entry.status == .completed,
            "startedAt": millis(entry.startedAt),
            "endedAt": millis(entry.endedAt),
            "plannedSeconds": entry.plannedSeconds,
            "activeSeconds": entry.activeSeconds,
            "focusedSeconds": entry.focusedSeconds,
            "segments": entry.segments.map { ["startedAt": millis($0.startedAt), "endedAt": millis($0.endedAt)] },
            "note": entry.note
        ]
    }

    // MARK: - Helpers

    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// Epoch milliseconds are always whole; emit them as integers so the file
    /// keeps the exact formatting the QML `JSON.stringify` produced.
    static func millis(_ value: EpochMillis) -> Any {
        value.isFinite ? Int64(value.rounded()) : 0
    }

    /// `JSON.stringify(value, null, 2) + "\n"`
    static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else { return "{}\n" }
        return text + "\n"
    }
}
