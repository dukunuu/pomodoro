import Foundation
import Combine

@MainActor
final class StandupDraft: ObservableObject {
    @Published private(set) var settings = JiraConfig.Settings()
    @Published private(set) var sources: StandupSources?
    @Published private(set) var loading = false
    /// The dates follow the calendar unless one is chosen: the standup is for
    /// today, and "yesterday" is whichever day was last logged in Whistler,
    /// so a Monday reports Friday without being told to. A choice lasts for
    /// the day it was made on.
    @Published private(set) var chosenDay: Date?
    @Published private(set) var chosenYesterday: Date?
    private var chosenOn = ""
    @Published var message = ""
    @Published var yesterdayText = ""
    @Published var todayText = ""
    @Published var projectSelections: [String: String] = [:]
    @Published var eventIDs = Set<String>()
    @Published var issueKeys = Set<String>()
    @Published var selectionChanged = false
    private var process: Process?
    private var generation = 0
    private var account: WhistlerConfig.Settings?
    private var googleIdentity: Data?

    init() { reloadSettings() }
    var connected: Bool { SecretStore.has(SecretStore.jiraToken) && !settings.siteUrl.isEmpty }
    var statuses: Set<String> { Set(settings.statuses.map { $0.lowercased() }) }
    var visibleIssues: [StandupSources.Issue] { sources?.issues.filter { statuses.contains($0.status.lowercased()) } ?? [] }
    var availableStatuses: [String] {
        var seen = Set<String>()
        return ((sources?.issues.map(\.status) ?? []) + settings.statuses + ["In Progress"])
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func reloadSettings() {
        do {
            let saved = try JiraConfig.read()
            if saved != settings || (account != nil && account != WhistlerConfig.readSettings())
                || (sources != nil && (!connected || !WhistlerConfig.isSignedIn || googleIdentity != (try? Data(contentsOf: DataPaths.googleToken)))) { clear() }
            settings = saved
        } catch { clear(); message = "Could not read Jira settings: \(error.localizedDescription)" }
    }

    func clear() {
        generation += 1
        process?.terminate(); process = nil
        loading = false; sources = nil; yesterdayText = ""; todayText = ""
        eventIDs = []; issueKeys = []; projectSelections = [:]
        selectionChanged = false; account = nil; googleIdentity = nil; message = ""
    }

    func disconnect() {
        guard SecretStore.delete(SecretStore.jiraToken) else { message = "Could not remove the Jira token from Keychain."; return }
        clear(); message = "Jira disconnected."
    }

    func toggleStatus(_ status: String, enabled: Bool) {
        var updated = settings
        updated.statuses.removeAll { $0.lowercased() == status.lowercased() }
        if enabled { updated.statuses.append(status) }
        do {
            try JiraConfig.save(updated)
            settings = updated
            if enabled {
                issueKeys.formUnion(sources?.issues.filter { $0.status.lowercased() == status.lowercased() }.map(\.key) ?? [])
            } else {
                issueKeys.subtract(sources?.issues.filter { $0.status.lowercased() == status.lowercased() }.map(\.key) ?? [])
            }
            selectionChanged = true
        } catch { message = error.localizedDescription }
    }

    func generateToday() {
        guard let sources else { return }
        todayText = sources.todayReport(statuses: statuses, eventIDs: eventIDs, issueKeys: issueKeys,
                                        projectSelections: projectSelections)
        selectionChanged = false
    }

    // MARK: - Dates

    func day(today: Date) -> Date { chosenDay ?? today }

    /// The worklog date to show: the chosen one, the one Whistler resolved for
    /// the loaded replies, or — before anything is loaded — the last weekday.
    func yesterday(today: Date) -> Date {
        if let chosenYesterday { return chosenYesterday }
        let day = day(today: today)
        if let sources, sources.day == Self.key(day), let loaded = Self.date(forKey: sources.yesterday) { return loaded }
        return Self.previousWeekday(before: day)
    }

    /// Choosing today's date is the same as not choosing one.
    func choose(day: Date, today: Date) {
        let calendar = Calendar.current
        chosenDay = calendar.isDate(day, inSameDayAs: today) ? nil : calendar.startOfDay(for: day)
        chosenYesterday = nil
        chosenOn = Self.key(today)
        clear()
    }

    /// `nil` goes back to the last day logged in Whistler.
    func choose(yesterday: Date?, today: Date) {
        chosenYesterday = yesterday.map { Calendar.current.startOfDay(for: $0) }
        chosenOn = Self.key(today)
        clear()
    }

    /// Drops a previous day's choices once the calendar has moved on. Loaded
    /// replies are left alone: they may hold edits.
    func followCalendar(today: Date) {
        let key = Self.key(today)
        guard chosenOn != key else { return }
        chosenOn = key
        chosenDay = nil
        chosenYesterday = nil
    }

    func load(today: Date) {
        load(day: Self.key(day(today: today)), yesterday: chosenYesterday.map(Self.key))
    }

    static func key(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(forKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func previousWeekday(before day: Date) -> Date {
        let calendar = Calendar.current
        var previous = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: day)) ?? day
        while calendar.isDateInWeekend(previous) {
            previous = calendar.date(byAdding: .day, value: -1, to: previous) ?? previous
        }
        return previous
    }

    // MARK: - Loading

    /// With no `yesterday`, the bridge reports the last day logged in Whistler.
    func load(day: String, yesterday: String? = nil) {
        clear(); message = ""
        guard connected else { message = "Connect Jira first."; return }
        loading = true
        let request = generation
        let currentSettings = settings
        let currentAccount = WhistlerConfig.readSettings()
        account = currentAccount
        let currentGoogle = try? Data(contentsOf: DataPaths.googleToken)
        googleIdentity = currentGoogle
        let arguments = ["--jira-url", settings.siteUrl, "--jira-email", settings.email, "--day", day]
            + (yesterday.map { ["--yesterday", $0] } ?? [])
        process = Bridge.run(DataPaths.standupScript, arguments,
                             environment: ["JIRA_API_TOKEN": SecretStore.read(SecretStore.jiraToken) ?? ""]) { [weak self] code, output, error in
            guard let self, request == self.generation else { return }
            self.process = nil; self.loading = false
            guard currentSettings == (try? JiraConfig.read()), currentAccount == WhistlerConfig.readSettings(),
                  self.connected, WhistlerConfig.isSignedIn,
                  currentGoogle == (try? Data(contentsOf: DataPaths.googleToken)) else {
                self.clear(); self.message = "Account or Calendar changed. Reload sources."; return
            }
            guard code == 0 else { self.message = error.isEmpty ? "Could not load standup sources." : String(error.prefix(600)); return }
            do {
                self.sources = try JSONDecoder().decode(StandupSources.self, from: Data(output.utf8))
                self.eventIDs = Set(self.sources?.events.map(\.id) ?? [])
                self.issueKeys = Set(self.visibleIssues.map(\.key))
                self.yesterdayText = self.sources?.yesterdayReport() ?? ""
                self.generateToday()
            } catch { self.message = "Standup sources returned invalid data." }
        }
    }
}
