import Foundation
import Combine

/// The timer, history, and persistence core. This is a direct behavioral port
/// of the QML service (`Tools/reference/Service.qml`): the same wall-clock
/// deadline model, the same phase accounting, the same file formats. Names are
/// kept close to the original so the two can be diffed against each other.
@MainActor
final class PomodoroService: ObservableObject {

    // MARK: - Timer state

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var running = false
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var completedFocus = 0
    @Published private(set) var activeNote = ""
    @Published private(set) var currentDate = Date()
    @Published private(set) var stateLoaded = false

    /// Bumped whenever anything a report depends on changes.
    @Published private(set) var statsRevision = 0
    @Published private(set) var sessions: [SessionEntry] = []

    private var endAt: EpochMillis = 0
    private var cycleDateKey = ""
    private var cycleMigrationPending = false
    private var legacySessions: [SessionEntry] = []
    private var historyLoaded = false
    private var hasPersistedState = false
    private var applyingState = false

    /// Generic phase accounting: active time excludes pauses, and the segment
    /// list is what the day timeline draws.
    private(set) var phaseStartedAt: EpochMillis = 0
    private var phaseRunStartedAt: EpochMillis = 0
    private var phaseElapsedSeconds = 0
    private(set) var phasePlannedSeconds = 0
    private var phaseSegments: [Segment] = []
    private var phaseRang = false

    let preferences = Preferences.shared
    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?
    private var minuteTimer: Timer?
    private var stateWatcher: FileWatcher?
    private var historyWatcher: FileWatcher?
    private var suppressReload = false

    /// Raised when a phase reaches zero, so the app layer can post a
    /// notification, play the alarm, and flash the floating widget.
    var onPhaseRing: ((Phase, Phase) -> Void)?

    weak var whistler: WhistlerService?

    // MARK: - Derived

    var todayKey: String { Fmt.dateKey(currentDate) }
    var focusSeconds: Int { preferences.duration(for: .focus) }
    var phaseLabel: String { phase.label }
    var remainingText: String { Fmt.duration(remainingSeconds) }

    var statusLabel: String {
        if running { return remainingSeconds < 0 ? "Overtime" : "Running" }
        return remainingSeconds == duration(for: phase) ? "Ready" : "Paused"
    }

    var isOvertime: Bool { phaseStartedAt > 0 && remainingSeconds <= 0 }

    /// 0…1 through the current phase, clamped, matching the Dashboard binding.
    var phaseProgress: Double {
        let total = duration(for: phase)
        guard total > 0 else { return 0 }
        return max(0, min(1, 1 - Double(remainingSeconds) / Double(total)))
    }

    func duration(for phase: Phase) -> Int { preferences.duration(for: phase) }

    // MARK: - Lifecycle

    init() {
        DataPaths.ensureDirectory()
        loadState(AtomicFile.read(DataPaths.state))
        loadHistory(AtomicFile.read(DataPaths.history))

        // A duration change while idle should move the visible clock, the same
        // rule `onSettingsChanged` enforced in QML.
        preferences.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.settingsChanged() }
            }
            .store(in: &cancellables)

        stateWatcher = FileWatcher(url: DataPaths.state) { [weak self] in
            self?.externalReload(state: true)
        }
        historyWatcher = FileWatcher(url: DataPaths.history) { [weak self] in
            self?.externalReload(state: false)
        }

        startTimers()
    }

    private func startTimers() {
        let tick = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick

        // Keeps the calendar day and the reports fresh while the timer is idle.
        let minute = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.minuteTick() }
        }
        RunLoop.main.add(minute, forMode: .common)
        minuteTimer = minute
    }

    private func minuteTick() {
        currentDate = Date()
        ensureCycleDay()
        whistler?.checkReminder(todayKey: todayKey)
        statsRevision += 1
    }

    private func settingsChanged() {
        if stateLoaded && !applyingState && !hasPersistedState && !running {
            remainingSeconds = duration(for: phase)
        }
        objectWillChange.send()
    }

    private func externalReload(state: Bool) {
        guard !suppressReload else { return }
        if state {
            loadState(AtomicFile.read(DataPaths.state))
        } else {
            loadHistory(AtomicFile.read(DataPaths.history))
        }
    }

    // MARK: - Clock

    private func secondsRemaining() -> Int {
        endAt > 0 ? Int(((endAt - nowMillis()) / 1000).rounded(.up)) : remainingSeconds
    }

    private func tick() {
        guard stateLoaded, running else { return }
        let left = secondsRemaining()
        if left <= 0 && !phaseRang {
            phaseRang = true
            remainingSeconds = left
            announcePhaseRing(phase)
            persistState()
        } else if left != remainingSeconds {
            remainingSeconds = left
        }
    }

    func start() {
        guard stateLoaded, !running else { return }
        ensureCycleDay()
        let now = nowMillis()
        if phaseStartedAt <= 0 {
            phaseStartedAt = now
            phaseElapsedSeconds = 0
            phaseSegments = []
            phaseRang = false
            phasePlannedSeconds = duration(for: phase)
        }
        if phasePlannedSeconds <= 0 { phasePlannedSeconds = duration(for: phase) }
        phaseRunStartedAt = now
        if remainingSeconds == 0 { remainingSeconds = duration(for: phase) }
        endAt = now + Double(remainingSeconds) * 1000
        running = true
        persistState()
        if phase == .focus { syncFocusStart() }
    }

    func pause() {
        guard stateLoaded, running else { return }
        let now = nowMillis()
        let left = secondsRemaining()
        stopPhaseClock(now)
        remainingSeconds = left
        endAt = 0
        running = false
        persistState()
    }

    func toggle() { running ? pause() : start() }

    func skip() {
        guard stateLoaded else { return }
        if phaseStartedAt > 0 { recordPhase(nowMillis(), status: .skipped) } else { clearActivePhase() }
        running = false
        endAt = 0
        advancePhase(countFocus: true)
        persistState()
    }

    func reset() {
        guard stateLoaded else { return }
        if phaseStartedAt > 0 { recordPhase(nowMillis(), status: .reset) } else { clearActivePhase() }
        running = false
        endAt = 0
        remainingSeconds = duration(for: phase)
        persistState()
    }

    func resetAll() {
        guard stateLoaded else { return }
        if phaseStartedAt > 0 { recordPhase(nowMillis(), status: .reset) } else { clearActivePhase() }
        running = false
        endAt = 0
        phase = .focus
        completedFocus = 0
        cycleDateKey = todayKey
        cycleMigrationPending = false
        remainingSeconds = duration(for: phase)
        persistState()
    }

    func finishCurrentPhase() {
        guard stateLoaded, phaseStartedAt > 0 else { return }
        finishPhase(announce: false)
    }

    private func finishPhase(announce: Bool) {
        let finished = phase
        let now = nowMillis()
        running = false
        endAt = 0
        recordPhase(now, status: .completed)
        advancePhase(countFocus: true)
        persistState()
        if announce { announcePhaseRing(finished, upcoming: phase) }
    }

    private func advancePhase(countFocus: Bool) {
        ensureCycleDay()
        if phase == .focus {
            if countFocus { completedFocus += 1 }
            phase = completedFocus > 0 && completedFocus % preferences.longBreakEvery == 0 ? .long : .short
        } else {
            phase = .focus
        }
        remainingSeconds = duration(for: phase)
        clearActivePhase()
    }

    private func nextPhase(after phase: Phase) -> Phase {
        guard phase == .focus else { return .focus }
        return (completedFocus + 1) % preferences.longBreakEvery == 0 ? .long : .short
    }

    private func announcePhaseRing(_ phase: Phase, upcoming: Phase? = nil) {
        onPhaseRing?(phase, upcoming ?? nextPhase(after: phase))
    }

    // MARK: - Phase accounting

    func phaseElapsed(at now: EpochMillis) -> Int {
        guard phaseStartedAt > 0 else { return 0 }
        var total = max(0, phaseElapsedSeconds)
        if phaseRunStartedAt > 0 {
            total += max(0, Int(((now - phaseRunStartedAt) / 1000).rounded(.down)))
        }
        return total
    }

    func phaseSegments(at now: EpochMillis) -> [Segment] {
        var result = phaseSegments
        if phaseRunStartedAt > 0 {
            let endedAt = max(now, phaseRunStartedAt)
            if endedAt > phaseRunStartedAt {
                result.append(Segment(startedAt: phaseRunStartedAt, endedAt: endedAt))
            }
        }
        if result.isEmpty && phaseStartedAt > 0 {
            let active = phaseElapsed(at: now)
            if active > 0 {
                result.append(Segment(startedAt: phaseStartedAt,
                                      endedAt: phaseStartedAt + Double(active) * 1000))
            }
        }
        return result
    }

    private func stopPhaseClock(_ now: EpochMillis) {
        if phaseStartedAt > 0 { phaseElapsedSeconds = phaseElapsed(at: now) }
        if phaseRunStartedAt > 0 {
            let segmentEnd = max(now, phaseRunStartedAt)
            if segmentEnd > phaseRunStartedAt {
                phaseSegments.append(Segment(startedAt: phaseRunStartedAt, endedAt: segmentEnd))
            }
        }
        phaseRunStartedAt = 0
    }

    private func clearActivePhase() {
        phaseStartedAt = 0
        phaseRunStartedAt = 0
        phaseElapsedSeconds = 0
        phasePlannedSeconds = 0
        phaseRang = false
        activeNote = ""
    }

    @discardableResult
    private func recordPhase(_ now: EpochMillis, status: EntryStatus) -> Bool {
        guard phaseStartedAt > 0 else { return false }
        let phaseName = phase
        let planned = phasePlannedSeconds > 0 ? phasePlannedSeconds : duration(for: phaseName)
        var active = phaseElapsed(at: now)
        if status == .completed && active <= 0 { active = planned }
        let segments = phaseSegments(at: now)
        let note = phaseName == .focus ? activeNote.normalizedNote : ""
        if phaseName == .focus {
            syncFocusEnd(startedAt: phaseStartedAt, endedAt: now,
                         activeSeconds: active, status: status, note: note)
        }
        sessions.append(SessionEntry(
            id: "\(Int64(now))-\(sessions.count + 1)",
            phase: phaseName,
            status: status,
            startedAt: phaseStartedAt,
            endedAt: now,
            plannedSeconds: planned,
            activeSeconds: max(0, active),
            segments: segments,
            note: note
        ))
        statsRevision += 1
        persistHistory()
        clearActivePhase()
        return true
    }

    // MARK: - Notes

    func setActiveNote(_ value: String) {
        activeNote = value.normalizedNote
    }

    func saveActiveNote(_ value: String) {
        setActiveNote(value)
        persistState()
    }

    // MARK: - Focus cycle

    @discardableResult
    private func ensureCycleDay(persist: Bool = true) -> Bool {
        let key = todayKey
        guard !key.isEmpty else { return false }
        if cycleDateKey.isEmpty {
            cycleDateKey = key
            return false
        }
        if cycleDateKey == key { return false }
        cycleDateKey = key
        completedFocus = 0
        if persist && stateLoaded && !applyingState { persistState() }
        return true
    }

    private func focusCount(forDay key: String) -> Int {
        sessions.reduce(into: 0) { total, entry in
            guard entry.phase == .focus else { return }
            guard entry.status == .completed || entry.status == .skipped else { return }
            if Fmt.dateKey(entry.endedAt) == key { total += 1 }
        }
    }

    @discardableResult
    private func applyCycleMigrationIfReady() -> Bool {
        guard cycleMigrationPending, historyLoaded else { return false }
        cycleDateKey = todayKey
        completedFocus = focusCount(forDay: todayKey)
        cycleMigrationPending = false
        return true
    }

    // MARK: - Persistence

    private func loadState(_ raw: String?) {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var parsed: [String: Any]?
        if !text.isEmpty, let data = text.data(using: .utf8) {
            parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        let version = Persistence.number(parsed?["version"]).map { Int($0) } ?? 0
        let valid = parsed != nil && (1...4).contains(version)
        var needsStatePersist = valid && version != 4

        applyingState = true
        if valid, let parsed {
            hasPersistedState = true
            phase = Phase(normalizing: parsed["phase"] as? String)
            let count = Persistence.number(parsed["completedFocus"]) ?? .nan
            completedFocus = count.isFinite && count >= 0 ? Int(count.rounded(.down)) : 0

            let savedCycleDateKey = (parsed["cycleDateKey"] as? String) ?? ""
            cycleDateKey = savedCycleDateKey
            cycleMigrationPending = savedCycleDateKey.isEmpty
            if cycleMigrationPending { needsStatePersist = true }

            let savedRemaining = Persistence.number(parsed["remainingSeconds"]) ?? .nan
            remainingSeconds = savedRemaining.isFinite ? Int(savedRemaining.rounded(.down)) : duration(for: phase)
            let savedEndAt = Persistence.number(parsed["endAt"]) ?? .nan
            endAt = savedEndAt.isFinite && savedEndAt > 0 ? savedEndAt : 0
            running = (parsed["running"] as? Bool) == true && endAt > 0

            legacySessions = Persistence.normalizedSessions(parsed["sessions"]) { self.duration(for: $0) }
            if !historyLoaded { sessions = legacySessions }
            statsRevision += 1

            // Version 1/2 named these `session*` rather than `phase*`.
            func fallback(_ primary: String, _ legacy: String) -> Double {
                let value = Persistence.number(parsed[primary]) ?? .nan
                if value.isFinite && value > 0 { return value }
                return Persistence.number(parsed[legacy]) ?? .nan
            }
            let savedStartedAt = fallback("phaseStartedAt", "sessionStartedAt")
            let savedRunStartedAt = fallback("phaseRunStartedAt", "sessionRunStartedAt")
            var savedElapsed = Persistence.number(parsed["phaseElapsedSeconds"]) ?? .nan
            if !savedElapsed.isFinite || savedElapsed < 0 {
                savedElapsed = Persistence.number(parsed["sessionElapsedSeconds"]) ?? .nan
            }
            let savedPlanned = fallback("phasePlannedSeconds", "sessionPlannedSeconds")

            phaseStartedAt = savedStartedAt.isFinite && savedStartedAt > 0 ? savedStartedAt : 0
            phaseRunStartedAt = savedRunStartedAt.isFinite && savedRunStartedAt > 0 ? savedRunStartedAt : 0
            phaseElapsedSeconds = savedElapsed.isFinite && savedElapsed > 0 ? Int(savedElapsed.rounded(.down)) : 0
            phasePlannedSeconds = savedPlanned.isFinite && savedPlanned > 0 ? Int(savedPlanned.rounded(.down)) : 0
            phaseSegments = Persistence.normalizedSegments(parsed["phaseSegments"])
            phaseRang = (parsed["phaseRang"] as? Bool) == true || (savedRemaining.isFinite && savedRemaining < 0)
            activeNote = phase == .focus ? ((parsed["activeNote"] as? String) ?? "").normalizedNote : ""
        } else {
            hasPersistedState = false
            phase = .focus
            running = false
            endAt = 0
            completedFocus = 0
            cycleDateKey = todayKey
            cycleMigrationPending = false
            remainingSeconds = duration(for: phase)
            legacySessions = []
            if !historyLoaded { sessions = [] }
            statsRevision += 1
            clearActivePhase()
        }
        applyingState = false
        stateLoaded = true

        if !cycleMigrationPending && ensureCycleDay(persist: false) { needsStatePersist = true }
        if applyCycleMigrationIfReady() { needsStatePersist = true }
        if needsStatePersist { persistState() }

        if running {
            let left = secondsRemaining()
            if phasePlannedSeconds <= 0 { phasePlannedSeconds = duration(for: phase) }
            // Older state carried no phase accounting; rebuild a best-effort
            // elapsed value from the persisted deadline.
            if phaseStartedAt <= 0 {
                phaseStartedAt = max(1, endAt - Double(phasePlannedSeconds) * 1000)
            }
            if phaseElapsedSeconds <= 0 && phaseRunStartedAt <= 0 {
                phaseElapsedSeconds = max(0, phasePlannedSeconds - left)
            }
            if phaseRunStartedAt <= 0 { phaseRunStartedAt = nowMillis() }
            remainingSeconds = left
            if left <= 0 && !phaseRang {
                phaseRang = true
                announcePhaseRing(phase)
                persistState()
            }
            if phase == .focus { syncFocusStart() }
        }
    }

    private func persistState() {
        guard stateLoaded else { return }
        let snapshot: [String: Any] = [
            "version": 4,
            "phase": phase.rawValue,
            "running": running,
            "endAt": Persistence.millis(running ? endAt : 0),
            "remainingSeconds": remainingSeconds,
            "completedFocus": completedFocus,
            "cycleDateKey": cycleDateKey,
            "activeNote": phase == .focus ? activeNote : "",
            "phaseStartedAt": Persistence.millis(phaseStartedAt),
            "phaseRunStartedAt": Persistence.millis(running ? phaseRunStartedAt : 0),
            "phaseElapsedSeconds": phaseElapsedSeconds,
            "phasePlannedSeconds": phasePlannedSeconds,
            "phaseSegments": phaseSegments.map {
                ["startedAt": Persistence.millis($0.startedAt), "endedAt": Persistence.millis($0.endedAt)]
            },
            "phaseRang": phaseRang
        ]
        writeSuppressingReload(Persistence.json(snapshot), to: DataPaths.state)
    }

    private func loadHistory(_ raw: String?) {
        let parsed = Persistence.parseHistory(raw) { self.duration(for: $0) }
        sessions = parsed ?? legacySessions
        historyLoaded = true
        statsRevision += 1
        // A missing history file is also the migration path for sessions that
        // were embedded in version 1/2 timer state.
        if parsed == nil { persistHistory() }
        if applyCycleMigrationIfReady() && stateLoaded { persistState() }
    }

    private func persistHistory() {
        guard historyLoaded else { return }
        writeSuppressingReload(Persistence.historyJSON(sessions), to: DataPaths.history)
    }

    /// Our own writes trip the file watcher; ignore the echo so a save never
    /// re-enters load and clobbers in-flight state.
    private func writeSuppressingReload(_ text: String, to url: URL) {
        suppressReload = true
        AtomicFile.write(text, to: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.suppressReload = false
        }
    }

    // MARK: - Calendar bridge

    private func syncFocusStart() {
        guard phase == .focus, phaseStartedAt > 0, phaseRunStartedAt > 0 else { return }
        Bridge.runDetached(DataPaths.integrationsScript, [
            "focus-start",
            String(Int64(phaseStartedAt)),
            String(Int64(phaseRunStartedAt)),
            String(Int64(endAt))
        ])
    }

    private func syncFocusEnd(startedAt: EpochMillis, endedAt: EpochMillis,
                              activeSeconds: Int, status: EntryStatus, note: String) {
        guard phase == .focus, startedAt > 0 else { return }
        Bridge.runDetached(DataPaths.integrationsScript, [
            "focus-end",
            String(Int64(startedAt)),
            String(Int64(startedAt)),
            String(Int64(endedAt)),
            String(max(0, activeSeconds)),
            status.rawValue,
            note
        ])
    }
}
