import Foundation

/// A read-only snapshot. Filtering and drafting never contact an AI or mutate worklogs.
struct StandupSources: Codable {
    struct Project: Codable, Identifiable {
        let id: String
        let name: String
        let minutes: Int
        let logs: [String]
    }
    struct PlanningProject: Codable, Identifiable {
        let id: String
        let name: String
    }
    struct Event: Codable, Identifiable {
        let id: String
        let title: String
        let when: String
        let projectId: String
        let taskGroup: String?
        var sourceID: String { "calendar:" + id }
    }
    struct Issue: Codable, Identifiable {
        let key: String
        let summary: String
        let status: String
        let project: String
        let projectId: String
        var id: String { key }
        var sourceID: String { "jira:" + key }
    }
    let day: String
    let yesterday: String
    let projects: [Project]
    let events: [Event]
    let issues: [Issue]
    let planningProjects: [PlanningProject]

    func yesterdayReport() -> String {
        guard !projects.isEmpty else { return "No Whistler worklog recorded for this date." }
        return projects.map { project in
            let hours = project.minutes / 60, minutes = project.minutes % 60
            let duration = hours == 0 ? "\(minutes)m" : (minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m")
            let notes = project.logs.isEmpty ? "Work logged; no task notes." : project.logs.joined(separator: "\n\n")
            return "\(project.name) (\(duration))\n" + notes
        }.joined(separator: "\n\n")
    }

    /// Copy-ready project/task bullets, without an agenda or invented logged time.
    func todayReport(statuses: Set<String>, eventIDs: Set<String>, issueKeys: Set<String>,
                     projectSelections: [String: String] = [:]) -> String {
        struct Group {
            var tasks: [String] = []
        }
        let names = Dictionary(planningProjects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var groups: [String: Group] = [:]
        var order: [String] = []
        func projectID(_ sourceID: String, _ defaultID: String) -> String {
            let id = projectSelections[sourceID] ?? defaultID
            let valid = names[id] != nil ? id : ""
            if groups[valid] == nil { groups[valid] = Group(); order.append(valid) }
            return valid
        }
        for event in events where eventIDs.contains(event.id) {
            let id = projectID(event.sourceID, event.projectId)
            // Categories decide eligibility, but the answer keeps only original task titles.
            if !groups[id]!.tasks.contains(event.title) {
                groups[id]!.tasks.append(event.title)
            }
        }
        let includedStatuses = Set(statuses.map { $0.lowercased() })
        for issue in issues where issueKeys.contains(issue.key) && includedStatuses.contains(issue.status.lowercased()) {
            let id = projectID(issue.sourceID, issue.projectId)
            groups[id]!.tasks.append("\(issue.key) — \(issue.summary)")
        }
        guard !order.isEmpty else { return "No Calendar events or Jira tasks selected." }
        return order.map { id in
            let heading = names[id] ?? "Other planned work (project not selected)"
            return ([heading] + groups[id]!.tasks.map { "- " + $0 }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
