import Foundation
import Combine

struct WhistlerProjectTotal: Identifiable {
    var name: String
    var minutes: Double
    var id: String { name }
}

struct WhistlerWorklogDetail {
    var key: String
    var minutes: Double
    var startMinutes: Double
    var endMinutes: Double
    var breakMinutes: Double
    var projects: [WhistlerProjectTotal]
}

struct WhistlerHoliday {
    var key: String
    var name: String
}

struct WhistlerMonthlyStats {
    var expectedMinutes: Double = 0
    var loggedMinutes: Double = 0
    var loggedToDateMinutes: Double = 0
    var expectedToDateMinutes: Double = 0
    var balanceMinutes: Double = 0
    var dailyTargetMinutes: Double = 480
    var workdayCount: Int = 0
    var elapsedWorkdayCount: Int = 0
    var loggedDays: Int = 0
}

struct WhistlerMonthCell: Identifiable {
    var id: Int
    var inMonth: Bool
    var key: String = ""
    var dayNumber: Int = 0
    var complete: Bool = false
    var incomplete: Bool = false
    var holiday: Bool = false
    var holidayName: String = ""
    var required: Bool = false
    var loggedMinutes: Double = 0
    var isToday: Bool = false
}

/// Whistler and Google Calendar integration state. Ported from the Whistler
/// half of `Service.qml`; all network and API work stays in the Python bridge.
@MainActor
final class WhistlerService: ObservableObject {

    // Reminder settings, persisted as pomodoro-whistler-settings.json
    @Published var reminderEnabled = false
    @Published var reminderTime = "18:00"
    @Published private(set) var settingsLoaded = false
    private var lastReminderDate = ""

    // AI mapping instructions
    @Published var instructionsText = ""
    @Published private(set) var instructionsLoaded = false

    // Import
    @Published private(set) var importRunning = false
    @Published private(set) var importProgress = 0
    @Published private(set) var importStatus = ""
    @Published private(set) var importedDays: Set<String> = []

    // Month status
    @Published private(set) var monthStatusKey = ""
    @Published private(set) var monthStatusLoading = false
    @Published private(set) var monthStatusLoaded = false
    @Published private(set) var monthStatusMessage = ""
    @Published private(set) var incompleteDays: Set<String> = []
    @Published private(set) var completeDays: Set<String> = []
    @Published private(set) var worklogDetails: [String: WhistlerWorklogDetail] = [:]
    @Published private(set) var projectTotals: [WhistlerProjectTotal] = []
    @Published private(set) var holidays: [String: WhistlerHoliday] = [:]
    @Published private(set) var monthlyStats = WhistlerMonthlyStats()
    @Published private(set) var calendarEventDays = 0

    private var reminderStatusPending = false
    private var importProcess: Process?
    private var statusProcess: Process?
    private var clearStatusWork: DispatchWorkItem?
    private var watchers: [FileWatcher] = []

    /// Set by the app layer so a fired reminder becomes a real notification.
    var onReminder: ((String, String) -> Void)?

    /// Prerequisite state, so a send can explain itself instead of failing in
    /// a bridge with a missing-file traceback.
    weak var integrations: IntegrationStatus?

    init() {
        loadSettings(AtomicFile.read(DataPaths.whistlerSettings))
        loadInstructions(AtomicFile.read(DataPaths.whistlerInstructions))
        loadImportState(AtomicFile.read(DataPaths.whistlerImportState))

        watchers = [
            FileWatcher(url: DataPaths.whistlerSettings) { [weak self] in
                self?.loadSettings(AtomicFile.read(DataPaths.whistlerSettings))
            },
            FileWatcher(url: DataPaths.whistlerInstructions) { [weak self] in
                self?.loadInstructions(AtomicFile.read(DataPaths.whistlerInstructions))
            },
            FileWatcher(url: DataPaths.whistlerImportState) { [weak self] in
                self?.loadImportState(AtomicFile.read(DataPaths.whistlerImportState))
            }
        ]
    }

    // MARK: - Settings

    static func normalizeReminderTime(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return "\(Fmt.pad(hour)):\(Fmt.pad(minute))"
    }

    private func loadSettings(_ raw: String?) {
        if let data = raw?.data(using: .utf8),
           let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let enabled = parsed["reminderEnabled"] as? Bool { reminderEnabled = enabled }
            if let time = parsed["reminderTime"] as? String,
               let normalized = Self.normalizeReminderTime(time) { reminderTime = normalized }
            if let last = parsed["lastReminderDate"] as? String { lastReminderDate = last }
        }
        settingsLoaded = true
    }

    private func settingsJSON() -> String {
        Persistence.json([
            "version": 1,
            "reminderEnabled": reminderEnabled,
            "reminderTime": reminderTime,
            "lastReminderDate": lastReminderDate
        ])
    }

    @discardableResult
    func saveSettings(reminderEnabled: Bool, reminderTime: String) -> Bool {
        guard let normalized = Self.normalizeReminderTime(reminderTime) else { return false }
        self.reminderEnabled = reminderEnabled
        self.reminderTime = normalized
        return AtomicFile.write(settingsJSON(), to: DataPaths.whistlerSettings)
    }

    // MARK: - Instructions

    private func loadInstructions(_ raw: String?) {
        if let raw {
            instructionsText = raw
        } else {
            // Seed the template the first time, matching the Qt behavior.
            AtomicFile.write(DataPaths.whistlerInstructionsTemplate, to: DataPaths.whistlerInstructions)
            instructionsText = DataPaths.whistlerInstructionsTemplate
        }
        instructionsLoaded = true
    }

    @discardableResult
    func saveInstructions(_ text: String) -> Bool {
        instructionsText = text
        return AtomicFile.write(text, to: DataPaths.whistlerInstructions)
    }

    // MARK: - Import state

    private func loadImportState(_ raw: String?) {
        var days: Set<String> = []
        if let data = raw?.data(using: .utf8),
           let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let imported = parsed["importedDays"] as? [String: Any] {
            for key in imported.keys where Fmt.dayStart(forKey: key) != nil {
                days.insert(key)
            }
        }
        importedDays = days
    }

    func isDayImported(_ key: String) -> Bool { importedDays.contains(key) }

    // MARK: - Import

    func importDay(_ key: String) {
        guard !importRunning else { return }
        importRunning = true
        importProgress = 0
        importStatus = "Starting import"
        clearStatusWork?.cancel()

        importProcess = Bridge.run(
            DataPaths.whistlerImportScript, [key],
            onLine: { [weak self] line in self?.handleProgress(line) },
            completion: { [weak self] code, _, stderr in
                guard let self else { return }
                self.importRunning = false
                self.importProcess = nil
                if code == 0 {
                    self.importProgress = 100
                    self.importStatus = "Complete"
                } else {
                    self.importProgress = 0
                    let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.importStatus = detail.isEmpty
                        ? "Import failed"
                        : String(detail.split(separator: "\n").first ?? "").prefix(180).description
                }
                self.loadImportState(AtomicFile.read(DataPaths.whistlerImportState))
                self.scheduleStatusClear()
            }
        )
        if importProcess == nil {
            importRunning = false
            importStatus = "Import bridge unavailable"
            scheduleStatusClear()
        }
    }

    func cancelImport() {
        importProcess?.terminate()
    }

    /// The bridge reports progress as `PROGRESS\t<percent>\t<message>`.
    private func handleProgress(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("PROGRESS\t") else { return }
        let parts = trimmed.components(separatedBy: "\t")
        guard parts.count >= 3 else { return }
        if let progress = Double(parts[1]) {
            importProgress = max(0, min(100, Int(progress.rounded())))
        }
        importStatus = parts[2...].joined(separator: "\t")
    }

    private func scheduleStatusClear() {
        clearStatusWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.importProgress = 0
            self?.importStatus = ""
        }
        clearStatusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: - Month status

    @discardableResult
    func refreshMonthStatus(_ monthKey: String) -> Bool {
        guard !monthStatusLoading, Fmt.monthParts(monthKey) != nil else { return false }
        monthStatusKey = monthKey
        monthStatusMessage = "Checking Calendar and Whistler…"
        monthStatusLoading = true
        monthStatusLoaded = false

        statusProcess = Bridge.run(
            DataPaths.whistlerImportScript, ["--month-status", monthKey],
            completion: { [weak self] code, stdout, stderr in
                guard let self else { return }
                self.monthStatusLoading = false
                self.statusProcess = nil
                if code == 0 {
                    self.applyMonthStatus(stdout)
                    if self.reminderStatusPending {
                        self.reminderStatusPending = false
                        DispatchQueue.main.async { self.checkReminder(todayKey: Fmt.dateKey(Date())) }
                    }
                } else {
                    self.monthStatusLoaded = false
                    self.reminderStatusPending = false
                    let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.monthStatusMessage = detail.isEmpty
                        ? "Could not read Calendar / Whistler status."
                        : String(detail.split(separator: "\n").first ?? "").prefix(180).description
                }
            }
        )
        if statusProcess == nil {
            monthStatusLoading = false
            monthStatusMessage = "Status bridge unavailable."
            return false
        }
        return true
    }

    private func applyMonthStatus(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            monthStatusMessage = "Calendar / Whistler status returned invalid data."
            return
        }
        monthStatusKey = (parsed["month"] as? String) ?? monthStatusKey
        incompleteDays = Set((parsed["incompleteDays"] as? [String]) ?? [])
        completeDays = Set((parsed["completeDays"] as? [String]) ?? [])

        var details: [String: WhistlerWorklogDetail] = [:]
        for item in (parsed["worklogDetails"] as? [[String: Any]]) ?? [] {
            guard let key = item["key"] as? String else { continue }
            let projects = ((item["projects"] as? [[String: Any]]) ?? []).map {
                WhistlerProjectTotal(name: ($0["name"] as? String) ?? "Project",
                                     minutes: Persistence.number($0["minutes"]) ?? 0)
            }
            details[key] = WhistlerWorklogDetail(
                key: key,
                minutes: Persistence.number(item["minutes"]) ?? 0,
                startMinutes: Persistence.number(item["startMinutes"]) ?? 0,
                endMinutes: Persistence.number(item["endMinutes"]) ?? 0,
                breakMinutes: Persistence.number(item["breakMinutes"]) ?? 0,
                projects: projects
            )
        }
        worklogDetails = details

        projectTotals = ((parsed["projectTotals"] as? [[String: Any]]) ?? []).map {
            WhistlerProjectTotal(name: ($0["name"] as? String) ?? "Project",
                                 minutes: Persistence.number($0["minutes"]) ?? 0)
        }

        var holidayMap: [String: WhistlerHoliday] = [:]
        for item in (parsed["holidayDays"] as? [[String: Any]]) ?? [] {
            guard let key = item["key"] as? String else { continue }
            holidayMap[key] = WhistlerHoliday(key: key,
                                              name: (item["name"] as? String) ?? "Public holiday")
        }
        holidays = holidayMap

        if let stats = parsed["monthlyStats"] as? [String: Any] {
            monthlyStats = WhistlerMonthlyStats(
                expectedMinutes: Persistence.number(stats["expectedMinutes"]) ?? 0,
                loggedMinutes: Persistence.number(stats["loggedMinutes"]) ?? 0,
                loggedToDateMinutes: Persistence.number(stats["loggedToDateMinutes"]) ?? 0,
                expectedToDateMinutes: Persistence.number(stats["expectedToDateMinutes"]) ?? 0,
                balanceMinutes: Persistence.number(stats["balanceMinutes"]) ?? 0,
                dailyTargetMinutes: Persistence.number(stats["dailyTargetMinutes"]) ?? 480,
                workdayCount: Int(Persistence.number(stats["workdayCount"]) ?? 0),
                elapsedWorkdayCount: Int(Persistence.number(stats["elapsedWorkdayCount"]) ?? 0),
                loggedDays: Int(Persistence.number(stats["loggedDays"]) ?? 0)
            )
        } else {
            monthlyStats = WhistlerMonthlyStats()
        }

        calendarEventDays = ((parsed["eventDays"] as? [Any]) ?? []).count
        monthStatusLoaded = true

        if incompleteDays.count == 1 {
            monthStatusMessage = "1 Calendar day missing in Whistler."
        } else if incompleteDays.count > 1 {
            monthStatusMessage = "\(incompleteDays.count) Calendar days missing in Whistler."
        } else if calendarEventDays > 0 {
            monthStatusMessage = "All counted event days are complete."
        } else {
            monthStatusMessage = "No counted Calendar event days."
        }
    }

    // MARK: - Calendar cells

    func monthCells(_ monthKey: String, todayKey: String) -> [WhistlerMonthCell] {
        guard let parts = Fmt.monthParts(monthKey) else { return [] }
        let cal = Fmt.calendar
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month + 1
        components.day = 1
        guard let first = cal.date(from: components),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }

        let leading = Fmt.mondayFirstIndex(first)
        var cells: [WhistlerMonthCell] = (0..<leading).map { WhistlerMonthCell(id: $0, inMonth: false) }
        for dayNumber in range {
            guard let date = cal.date(byAdding: .day, value: dayNumber - 1, to: first) else { continue }
            let key = Fmt.dateKey(date)
            let holiday = holidays[key]
            let weekday = cal.component(.weekday, from: date)
            cells.append(WhistlerMonthCell(
                id: leading + dayNumber,
                inMonth: true,
                key: key,
                dayNumber: dayNumber,
                complete: completeDays.contains(key),
                incomplete: incompleteDays.contains(key),
                holiday: holiday != nil,
                holidayName: holiday?.name ?? "",
                required: weekday != 1 && weekday != 7 && holiday == nil,
                loggedMinutes: worklogDetails[key]?.minutes ?? 0,
                isToday: key == todayKey
            ))
        }
        while cells.count % 7 != 0 {
            cells.append(WhistlerMonthCell(id: 1000 + cells.count, inMonth: false))
        }
        return cells
    }

    func dayTooltip(_ cell: WhistlerMonthCell) -> String {
        guard cell.inMonth else { return "" }
        var text = cell.key
        if let holiday = holidays[cell.key] {
            text += "\nHoliday · \(holiday.name)"
        } else if !cell.required {
            text += "\nWeekend / non-working day"
        } else {
            text += "\nTarget · \(Fmt.whistlerMinutes(monthlyStats.dailyTargetMinutes))"
        }
        if let detail = worklogDetails[cell.key] {
            text += "\nLogged · \(Fmt.whistlerMinutes(detail.minutes))"
            if detail.startMinutes > 0 || detail.endMinutes > 0 {
                text += " (\(Fmt.whistlerClock(detail.startMinutes))–\(Fmt.whistlerClock(detail.endMinutes)))"
            }
            if detail.breakMinutes > 0 {
                text += "\nBreak · \(Fmt.whistlerMinutes(detail.breakMinutes))"
            }
            for project in detail.projects.prefix(5) {
                text += "\n\(project.name) · \(Fmt.whistlerMinutes(project.minutes))"
            }
            if detail.projects.count > 5 {
                text += "\n+\(detail.projects.count - 5) more projects"
            }
        } else {
            text += "\nNo Whistler worklog"
        }
        if cell.incomplete {
            text += "\nCalendar time not logged"
        } else if cell.complete {
            text += "\nCalendar day covered"
        }
        return text
    }

    // MARK: - Reminder

    /// Ported from `Service.checkWhistlerReminder`: fires once a day, after the
    /// configured time, only when the day is genuinely missing from Whistler.
    func checkReminder(todayKey key: String) {
        guard settingsLoaded, reminderEnabled, !importRunning, !key.isEmpty else { return }
        guard lastReminderDate != key, !isDayImported(key) else { return }

        let parts = reminderTime.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return }
        let now = Fmt.calendar.dateComponents([.hour, .minute], from: Date())
        guard (now.hour ?? 0) * 60 + (now.minute ?? 0) >= hour * 60 + minute else { return }

        let monthKey = String(key.prefix(7))
        guard monthStatusLoaded, monthStatusKey == monthKey else {
            if !reminderStatusPending {
                reminderStatusPending = true
                if !refreshMonthStatus(monthKey) { reminderStatusPending = false }
            }
            return
        }
        guard incompleteDays.contains(key) else { return }

        lastReminderDate = key
        saveSettings(reminderEnabled: reminderEnabled, reminderTime: reminderTime)
        onReminder?("Whistler log reminder",
                    "Review today's Calendar events and send the worklog to Whistler.")
    }

    // MARK: - Setup flows

    func authorizeGoogle() {
        Bridge.runInTerminal(DataPaths.googleAuthScript, [], title: "Authorize Google Calendar")
    }

    func configureWhistler() {
        Bridge.runInTerminal(DataPaths.whistlerSetupScript, [], title: "Configure Whistler")
    }
}
