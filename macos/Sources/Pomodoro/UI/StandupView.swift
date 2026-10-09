import SwiftUI
import AppKit

/// Two replies to paste when Dobby asks. The page is the task in order: what
/// is still missing, then prepare, then the two replies to check and copy.
/// Dates and the Jira account are configuration, and open in a sheet.
struct StandupView: View {
    @ObservedObject var draft: StandupDraft
    /// Today's date key. The dates follow it unless one is chosen.
    var today: String
    @EnvironmentObject private var integrations: IntegrationStatus
    @Environment(\.openSection) private var openSection
    @State private var connecting = false
    @State private var configuring = false
    @State private var refreshing = false
    @State private var yesterdayCopied = false
    @State private var todayCopied = false

    private var ready: Bool { integrations.googleReady && WhistlerConfig.isSignedIn && draft.connected }
    private var todayDate: Date { Fmt.dayStart(forKey: today) ?? Date() }
    private var day: Date { draft.day(today: todayDate) }
    private var copiedCount: Int { (yesterdayCopied ? 1 : 0) + (todayCopied ? 1 : 0) }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    /// Which two days the replies are for, in words: they are picked for the
    /// user now, so the page has to say what was picked.
    private var datesLine: String {
        let label = Self.dayFormatter.string(from: day)
        let standup = draft.chosenDay == nil ? "Today, \(label)" : label
        let yesterday = Self.dayFormatter.string(from: draft.yesterday(today: todayDate))
        if draft.chosenYesterday != nil { return "\(standup) · Yesterday from \(yesterday)" }
        if let sources = draft.sources, sources.day == StandupDraft.key(day) {
            return "\(standup) · Yesterday from \(yesterday), the last day logged in Whistler"
        }
        return "\(standup) · Yesterday from the last day logged in Whistler"
    }

    /// Replies left over from another day: kept, because they may hold edits.
    private var staleDay: String? {
        guard let loaded = draft.sources?.day, loaded != StandupDraft.key(day) else { return nil }
        return loaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PageHeading(title: "Daily standup") {
                if draft.loading {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { draft.clear() }
                        .buttonStyle(.secondary)
                } else if draft.sources != nil {
                    Text("\(copiedCount) / 2 copied")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(copiedCount == 2 ? AnyShapeStyle(Theme.longBreak) : AnyShapeStyle(.secondary))
                        .accessibilityLabel("Replies copied")
                        .accessibilityValue("\(copiedCount) of 2")
                    Button { refreshing = true } label: {
                        Label("Refresh sources", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.secondary)
                    .disabled(!ready)
                }
                Button { configuring = true } label: {
                    Label("Dates and Jira account", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.iconFilled)
                .help("Dates and Jira account")
                .disabled(draft.loading)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(datesLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Change") { configuring = true }
                    .buttonStyle(.ghost)
                    .controlSize(.small)
                    .disabled(draft.loading)
            }
            .sheet(isPresented: $configuring) { StandupConfigSheet(draft: draft, todayDate: todayDate) }
        }
        .confirmationDialog("Refresh sources and replace both replies?", isPresented: $refreshing, titleVisibility: .visible) {
            Button("Refresh and replace replies", role: .destructive) { load() }
        } message: {
            Text("Any edits to Yesterday and Today will be replaced. Copy them first if you want to keep them.")
        }
        .sheet(isPresented: $connecting) { JiraCredentialsSheet { draft.reloadSettings() } }
        .onAppear { draft.followCalendar(today: todayDate); draft.reloadSettings() }
        .onChange(of: today) { _, _ in draft.followCalendar(today: todayDate) }

        if let staleDay { Notice(.info, "These replies were prepared for \(staleDay). Refresh sources to prepare the current dates.") }
        if !draft.message.isEmpty { Notice(.error, draft.message) }

        if let sources = draft.sources {
            StandupReplyCard(title: "Yesterday", question: "What did you do yesterday?",
                             source: "Whistler · \(sources.yesterday) · original logged durations",
                             text: $draft.yesterdayText, copied: $yesterdayCopied)
            StandupReplyCard(title: "Today", question: "What will you do today?",
                             source: "Calendar + Jira · \(sources.day) · selected work only",
                             text: $draft.todayText, copied: $todayCopied,
                             selectionChanged: draft.selectionChanged)
            Disclosure("Review today's sources and project assignments", indented: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sourceCards(sources)
                    HStack(spacing: 10) {
                        Button("Rebuild Today from selection") { draft.generateToday(); todayCopied = false }
                            .buttonStyle(AppButtonStyle(kind: draft.selectionChanged ? .primary : .secondary))
                        Text("Rebuild replaces only Today. Yesterday's edits stay unchanged.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: draft.selectionChanged) { _, changed in
                if changed { todayCopied = false }
            }
        } else if ready {
            prepare
        } else {
            readiness
        }
    }

    /// Nothing loaded yet: one thing to do.
    private var prepare: some View {
        Card {
            VStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.textFaint)
                Text("Prepare today's two answers")
                    .font(.system(size: 15, weight: .semibold))
                Text("Copy the work answers when Dobby asks. Personal questions stay in Slack. Nothing is posted automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
                Button { load() } label: {
                    Label(draft.loading ? "Loading sources…" : "Prepare daily standup",
                          systemImage: "arrow.down.doc")
                        .frame(minWidth: 170)
                }
                .buttonStyle(.primary)
                .controlSize(.large)
                .disabled(draft.loading)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    /// What has to be connected first, each with the way to do it, instead of
    /// a sentence listing three things and a button that stays grey.
    private var readiness: some View {
        Card("Before you start",
             subtitle: "Yesterday comes from Whistler; today comes from Calendar and Jira. Calendar selection uses your existing Jev mapping setup.") {
            VStack(spacing: 0) {
                StandupReadinessRow(title: "Jira Cloud",
                                    detail: draft.connected ? "\(draft.settings.siteUrl) · \(draft.settings.email)" : "Not connected",
                                    ready: draft.connected, action: "Connect Jira…") { connecting = true }
                RowDivider()
                StandupReadinessRow(title: "Google Calendar",
                                    detail: integrations.googleReady ? "Authorized" : "Not authorized yet",
                                    ready: integrations.googleReady, action: "Open Whistler Setup") { openSection(.whistler) }
                RowDivider()
                StandupReadinessRow(title: "Whistler",
                                    detail: WhistlerConfig.isSignedIn ? "Signed in" : "Not signed in",
                                    ready: WhistlerConfig.isSignedIn, action: "Open Whistler Setup") { openSection(.whistler) }
            }
        }
    }

    @ViewBuilder private func sourceCards(_ sources: StandupSources) -> some View {
        Card("Today's Calendar · \(sources.day)",
             subtitle: "Only timed invitations you answered Yes to and Jev includes in Whistler. Original titles are kept; skipped events and all-day events are excluded.") {
            if sources.events.isEmpty {
                Text("No accepted, Jev-approved Calendar work.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(sources.events) { event in
                        sourceRow(isOn: selected(event.id, in: $draft.eventIDs),
                                  sourceID: event.sourceID, defaultID: event.projectId, sources: sources) {
                            Text(event.title)
                        }
                        if event.id != sources.events.last?.id { RowDivider() }
                    }
                }
            }
        }
        Card("Jira tasks", subtitle: "Assigned to you across active sprints. Select the statuses to include; In Progress is the default.") {
            FlowLayout(spacing: 6) {
                ForEach(draft.availableStatuses, id: \.self) { status in
                    FilterChip(text: status, isOn: Binding(get: { draft.statuses.contains(status.lowercased()) },
                                                           set: { draft.toggleStatus(status, enabled: $0) }))
                }
            }
            if sources.issues.isEmpty {
                Text("No tasks assigned to you in active sprints.").font(.callout).foregroundStyle(.secondary)
            } else if draft.visibleIssues.isEmpty {
                Text("No tasks match the selected statuses.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(draft.visibleIssues) { issue in
                        sourceRow(isOn: selected(issue.key, in: $draft.issueKeys),
                                  sourceID: issue.sourceID, defaultID: issue.projectId, sources: sources) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(issue.key) — \(issue.summary)")
                                Text("\(issue.project) · \(issue.status)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if issue.id != draft.visibleIssues.last?.id { RowDivider() }
                    }
                }
            }
        }
    }

    /// One piece of work: whether it is in the reply, and under which project.
    private func sourceRow<Label: View>(isOn: Binding<Bool>, sourceID: String, defaultID: String,
                                        sources: StandupSources,
                                        @ViewBuilder label: () -> Label) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: isOn, label: label)
                .toggleStyle(.check)
            Spacer(minLength: 8)
            projectMenu(sourceID, defaultID: defaultID, sources: sources)
                .frame(width: 210)
                .disabled(!isOn.wrappedValue)
        }
        .padding(.vertical, 7)
    }

    private func load() {
        yesterdayCopied = false; todayCopied = false
        draft.load(today: todayDate)
    }

    private func projectMenu(_ sourceID: String, defaultID: String, sources: StandupSources) -> some View {
        let selection = draft.projectSelections[sourceID] ?? defaultID
        func name(_ project: StandupSources.PlanningProject) -> String {
            let duplicate = sources.planningProjects.filter { $0.name.lowercased() == project.name.lowercased() }.count > 1
            return duplicate ? "\(project.name) · \(project.id)" : project.name
        }
        let current = sources.planningProjects.first { $0.id == selection }.map(name) ?? "Other planned work"
        return MenuField(label: "Report project", value: current, icon: "folder") {
            Picker("Report project", selection: Binding(get: { selection }, set: {
                draft.projectSelections[sourceID] = $0
                draft.selectionChanged = true
            })) {
                Text("Other planned work / choose a project").tag("")
                ForEach(sources.planningProjects) { project in
                    Text(name(project)).tag(project.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private func selected(_ id: String, in values: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { enabled in
            if enabled { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
            draft.selectionChanged = true
        })
    }
}

/// Which days the standup covers and which Jira account it reads: set rarely,
/// so it sits in a sheet instead of taking room on the page.
struct StandupConfigSheet: View {
    @ObservedObject var draft: StandupDraft
    var todayDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var connecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "calendar",
                        title: "Dates and Jira account",
                        subtitle: "The dates pick themselves each day. A date chosen here applies for today only, and changing either one clears both replies.")

            VStack(spacing: 10) {
                SettingRow("Standup date",
                           subtitle: draft.chosenDay == nil ? "Follows today's date." : "Chosen for today.") {
                    if draft.chosenDay != nil {
                        Button("Use Today") { draft.choose(day: todayDate, today: todayDate) }
                            .buttonStyle(.ghost)
                    }
                    DayField(day: Binding(get: { draft.day(today: todayDate) },
                                          set: { draft.choose(day: $0, today: todayDate) }))
                }
                RowDivider()
                SettingRow("Yesterday worklog",
                           subtitle: draft.chosenYesterday == nil
                               ? "The last day logged in Whistler before the standup date, so a Monday reports Friday."
                               : "Chosen for today.") {
                    if draft.chosenYesterday != nil {
                        Button("Use Last Logged") { draft.choose(yesterday: nil, today: todayDate) }
                            .buttonStyle(.ghost)
                    }
                    DayField(day: Binding(get: { draft.yesterday(today: todayDate) },
                                          set: { draft.choose(yesterday: $0, today: todayDate) }))
                }
                RowDivider()
                SettingRow("Jira Cloud",
                           subtitle: draft.connected ? "\(draft.settings.siteUrl) · \(draft.settings.email)" : "Not connected") {
                    if draft.connected {
                        Button("Disconnect") { draft.disconnect() }.buttonStyle(.destructive)
                    }
                    Button(draft.connected ? "Switch Account…" : "Connect Jira…") { connecting = true }
                        .buttonStyle(.secondary)
                }
            }
            .disabled(draft.loading)

            if !draft.message.isEmpty { Notice(.info, draft.message) }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 540)
        .sheet(isPresented: $connecting) { JiraCredentialsSheet { draft.reloadSettings() } }
    }
}

/// One thing the standup needs, whether it is in place, and the way to fix it.
private struct StandupReadinessRow: View {
    var title: String
    var detail: String
    var ready: Bool
    var action: String
    var perform: () -> Void

    var body: some View {
        let tint = ready ? Theme.longBreak : Color.secondary
        HStack(spacing: 11) {
            Image(systemName: ready ? "checkmark" : "circle.dotted")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ready ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !ready {
                Button(action, action: perform)
                    .buttonStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// A reply as it will be pasted: the text is the clipboard, with no question
/// or report wrapper around it. It reads as a message rather than a form
/// field, grows with its text, and can be edited in place.
struct StandupReplyCard: View {
    let title: String
    let question: String
    let source: String
    @Binding var text: String
    @Binding var copied: Bool
    var selectionChanged = false
    @State private var copyFailed = false
    @FocusState private var editing: Bool

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Card {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(title)
                    Text(question).font(.system(size: 15, weight: .semibold))
                }
                Spacer(minLength: 8)
                if copied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.longBreak)
                        .transition(.opacity)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    let done = NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(.easeOut(duration: 0.15)) { copied = done }
                    copyFailed = !done
                } label: { Label(copied ? "Copy Again" : "Copy Reply", systemImage: "doc.on.doc") }
                    .buttonStyle(AppButtonStyle(kind: copied ? .secondary : .primary))
                    .disabled(empty || selectionChanged)
            }
            .accessibilityAddTraits(.updatesFrequently)
            if selectionChanged { Notice(.info, "Selection changed. Rebuild Today in Review sources before copying.") }
            // Sized by its text and scrolled by the page, not a fixed box with
            // a scroll bar of its own.
            TextEditor(text: $text)
                .font(.system(size: 13))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .top)
                .focused($editing)
                .padding(.horizontal, 7)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.controlFill, in: shape)
                .overlay(shape.strokeBorder(editing ? Theme.accent : Color.clear, lineWidth: 1.5))
                .animation(.easeOut(duration: 0.15), value: editing)
                .accessibilityLabel("\(title) reply")
            Text(source)
                .font(.caption)
                .foregroundStyle(Theme.textFaint)
            if copyFailed { Notice(.error, "Clipboard unavailable. Select and copy your answer manually.") }
        }
        .onChange(of: text) { _, _ in copied = false; copyFailed = false }
    }
}

private struct JiraCredentialsSheet: View {
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var site = ""
    @State private var email = ""
    @State private var token = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "checklist",
                        title: "Connect Jira Cloud",
                        subtitle: "Your API token is validated with Jira and stored in the login Keychain, never in a file.")
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("Site URL") {
                    InputField(label: "Site URL", text: $site, prompt: "https://your-team.atlassian.net", icon: "globe")
                }
                FieldLabel("Atlassian email") {
                    InputField(label: "Atlassian email", text: $email, prompt: "you@example.com", icon: "envelope")
                }
                FieldLabel("API token", hint: "Create it without scopes.") {
                    InputField(label: "API token", text: $token, prompt: "API token", icon: "key",
                               secure: true, font: Theme.mono(12), onSubmit: connect)
                }
            }
            .disabled(busy)
            if !error.isEmpty { Notice(.error, error) }
            HStack(spacing: 8) {
                Link(destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!) {
                    Label("Create an Atlassian API token", systemImage: "arrow.up.right")
                }
                .buttonStyle(.ghost)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Cancel") { token = ""; dismiss() }
                    .buttonStyle(.secondary).keyboardShortcut(.cancelAction).disabled(busy)
                Button(busy ? "Checking…" : "Validate and Save", action: connect)
                    .buttonStyle(.primary).keyboardShortcut(.defaultAction)
                    .disabled(busy || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)
        }
        .padding(20).frame(width: 480)
        .interactiveDismissDisabled(busy)
        .onAppear {
            if let saved = try? JiraConfig.read() { site = saved.siteUrl; email = saved.email }
        }
    }

    private func connect() {
        do {
            let resolved = try JiraConfig.site(site)
            let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty else { throw JiraConfig.Failure("An email is required.") }
            busy = true; error = ""
            Bridge.run(DataPaths.standupScript, ["--validate-jira", "--jira-url", resolved, "--jira-email", email],
                       environment: ["JIRA_API_TOKEN": replacement]) { code, _, failure in
                busy = false
                guard code == 0 else { error = failure.isEmpty ? "Jira validation failed." : String(failure.prefix(600)); return }
                do {
                    let old = try JiraConfig.read()
                    var saved = JiraConfig.Settings(siteUrl: resolved, email: email)
                    if old.siteUrl == resolved && old.email.lowercased() == email.lowercased() { saved.statuses = old.statuses }
                    let previousToken = SecretStore.read(SecretStore.jiraToken) ?? ""
                    guard SecretStore.write(SecretStore.jiraToken, replacement) else { throw JiraConfig.Failure("Could not store the Jira token in Keychain.") }
                    do { try JiraConfig.save(saved) }
                    catch { SecretStore.write(SecretStore.jiraToken, previousToken); throw error }
                    token = ""; onSaved(); dismiss()
                } catch let failure { error = failure.localizedDescription }
            }
        } catch let failure { error = failure.localizedDescription }
    }
}
