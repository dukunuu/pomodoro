import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Feedback to members, laid out around the form it ends in: write what
/// happened and convert it on the left, check the item's competency and
/// level, and watch the filled-in form on the right. The typed note is not
/// kept once it is converted.
struct FeedbackView: View {
    @ObservedObject var desk: FeedbackDesk
    @ObservedObject private var reminder = FeedbackReminder.shared
    @State private var picking = false
    @State private var reminding = false

    private var people: Int { Set((desk.setup?.members ?? []).map(\.name)).count }
    private var submitted: Int { Set((desk.setup?.members ?? []).filter { desk.submitted($0) }.map(\.name)).count }

    var body: some View {
        PageHeading(title: "Feedback") {
            if desk.setup != nil {
                Text("\(submitted) of \(people) submitted").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { reminding = true } label: {
                Label("Reminder", systemImage: reminder.enabled ? "bell.badge.fill" : "bell").labelStyle(.iconOnly)
            }
            .buttonStyle(.iconFilled)
            .help("Remind me to write feedback")
            .popover(isPresented: $reminding, arrowEdge: .bottom) { FeedbackReminderSettings(reminder: reminder) }
            Menu {
                Button("Import setup file…") { pick("--import-setup", [.json]) }
                Button("Export setup file…") { export() }
                Divider()
                Button("Import form page…") { pick("--import-form", [.html]) }
                Button("Import member list…") { pick("--import-members", [.html, .commaSeparatedText]) }
                Button("Import competency framework…") { pick("--import-framework", [.json]) }
            } label: { Label("Setup", systemImage: "square.and.arrow.down").labelStyle(.iconOnly) }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Import or export the form, member list and framework")
        }
        .onAppear { desk.load() }

        if !desk.message.isEmpty { Notice(.error, desk.message) }

        if let setup = desk.setup {
            toolbar
            if let member = desk.member {
                FeedbackWorkspace(desk: desk, member: member, setup: setup).id(member.key)
            } else {
                Card {
                    Button { picking = true } label: { Label("Pick a member", systemImage: "person.crop.circle") }
                        .buttonStyle(.primary).controlSize(.large)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
        } else {
            setupCard
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { picking = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                    if let member = desk.member {
                        Text(member.name).fontWeight(.semibold)
                        Text(Self.shortGrade(member)).foregroundStyle(.secondary)
                    } else {
                        Text("Choose a member").foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .help("Search members (⌘K)")
            .popover(isPresented: $picking, arrowEdge: .bottom) { FeedbackMemberPicker(desk: desk, isPresented: $picking) }
            if let member = desk.member { Text(member.groups).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            if let member = desk.member {
                if desk.openedFor == member.key {
                    Text("Submitted in the browser?").font(.caption).foregroundStyle(.secondary)
                    Button("Yes") { desk.markSubmitted() }.buttonStyle(.secondary)
                }
                Button { desk.openForm() } label: { Label("Open form", systemImage: "arrow.up.forward.square") }
                    .buttonStyle(.primary)
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(!desk.ready(member))
                    .help(desk.ready(member) ? "Opens the form filled in" : "Every item needs a competency and a level")
            }
        }
    }

    static func shortGrade(_ member: FeedbackMember) -> String {
        member.gradeName.isEmpty ? "No grade" : String(member.gradeName.split(separator: "(").first ?? "").trimmingCharacters(in: .whitespaces)
    }

    private var setupCard: some View {
        Card("Set up feedback", subtitle: "Import a setup file, or the three parts. They stay on this Mac.") {
            VStack(spacing: 0) {
                setupRow("Setup file", nil) { pick("--import-setup", [.json]) }
                RowDivider()
                setupRow("Feedback form", FeedbackDesk.formFile) { pick("--import-form", [.html]) }
                RowDivider()
                setupRow("Member list", FeedbackDesk.membersFile) { pick("--import-members", [.html, .commaSeparatedText]) }
                RowDivider()
                setupRow("Competency framework", FeedbackDesk.frameworkFile) { pick("--import-framework", [.json]) }
            }
        }
    }

    private func setupRow(_ title: String, _ file: URL?, action: @escaping () -> Void) -> some View {
        let ready = file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        return HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle").foregroundStyle(ready ? Theme.longBreak : Theme.textFaint)
            Text(title)
            Spacer()
            Button(ready ? "Replace…" : "Import…", action: action).buttonStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func pick(_ flag: String, _ types: [UTType]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        desk.importFile(flag, from: url)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "feedback-setup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        desk.exportSetup(to: url)
    }
}

/// Searches members by their name as the form lists it, or the Latin spelling from the sheet.
private struct FeedbackMemberPicker: View {
    @ObservedObject var desk: FeedbackDesk
    @Binding var isPresented: Bool
    @State private var search = ""

    private var groups: [(String, [FeedbackMember])] {
        // Spaces and dots are ignored: a form may write one name "Э. Байгаль"
        // and the rest "Б.Бат", and people type either.
        func key(_ value: String) -> String { value.lowercased().filter { !$0.isWhitespace && $0 != "." } }
        let query = key(search)
        let members = (desk.setup?.members ?? []).filter {
            query.isEmpty || key($0.name).contains(query) || key($0.latin ?? "").contains(query)
        }
        // Someone in several groups is listed under each of them.
        var order: [String] = []
        for member in members { for role in member.roles where !order.contains(role.group) { order.append(role.group) } }
        for member in members where !order.contains(member.group) { order.append(member.group) }
        return order.map { group in (group, members.filter { $0.group == group || $0.roles.contains { $0.group == group } }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InputField(label: "Search", text: $search, prompt: "Name, in Cyrillic or Latin", icon: "magnifyingglass") {
                if let first = groups.first?.1.first { choose(first) }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(groups, id: \.0) { group, members in
                        SectionLabel(group).padding(.top, 8).padding(.horizontal, 6).padding(.bottom, 2)
                        ForEach(members) { member in row(member) }
                    }
                    if groups.isEmpty { Text("No one matches.").font(.callout).foregroundStyle(.secondary).padding(8) }
                }
            }
        }
        .padding(12)
        .frame(width: 340, height: 440)
    }

    private func row(_ member: FeedbackMember) -> some View {
        let pending = desk.pending(member).count
        return Button { choose(member) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(member.name).font(.system(size: 13, weight: desk.selected == member.key ? .semibold : .regular))
                        if let latin = member.latin, !latin.isEmpty { Text(latin).font(.caption).foregroundStyle(Theme.textFaint) }
                    }
                    Text(FeedbackView.shortGrade(member)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if member.grade == nil {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Theme.urgent)
                } else if desk.submitted(member) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.longBreak)
                } else if pending > 0 {
                    Text("\(pending)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(desk.selected == member.key ? Theme.accent.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ member: FeedbackMember) {
        desk.selected = member.key
        desk.focused = nil
        desk.refreshAnswers()
        isPresented = false
    }
}

private struct FeedbackReminderSettings: View {
    @ObservedObject var reminder: FeedbackReminder

    private static let next: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d HH:mm")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Remind me to write feedback", isOn: $reminder.enabled).toggleStyle(.switch)
            HStack {
                Text("Every")
                Stepper(value: $reminder.everyDays, in: 1...30) {
                    Text("\(reminder.everyDays) day\(reminder.everyDays == 1 ? "" : "s")").monospacedDigit()
                }
                Text("at")
                DatePicker("", selection: $reminder.time, displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
            }
            .disabled(!reminder.enabled)
            if reminder.enabled, let next = reminder.occurrences().first {
                Text("Next: \(Self.next.string(from: next))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}

/// The note box and the selected item on the left; the form, as it will be sent, on the right.
private struct FeedbackWorkspace: View {
    @ObservedObject var desk: FeedbackDesk
    var member: FeedbackMember
    var setup: FeedbackSetup
    @State private var text = ""
    @FocusState private var writing: Bool

    private var notes: [FeedbackNote] { desk.pending(member) }
    private var focused: FeedbackNote? { notes.first { $0.id == desk.focused } ?? notes.last }
    private var unplaced: [FeedbackNote] {
        notes.filter { desk.converting($0) || $0.level == nil || $0.competency == nil }
    }

    var body: some View {
        if member.grade == nil, let ladder = member.ladder, let grades = setup.grades[ladder] {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.focus)
                Text("Not in the member sheet.").font(.callout)
                Spacer()
                Menu("Set grade") {
                    ForEach(grades) { grade in Button(grade.name) { desk.setGrade(grade.id, for: member.key) } }
                }
                .fixedSize()
            }
            .padding(12)
            .background(Theme.focus.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                composer
                if let focused {
                    FeedbackItemEditor(desk: desk, note: focused, member: member, setup: setup, latest: focused.id == notes.last?.id)
                } else {
                    Card { Text("Converted items appear here.").font(.callout).foregroundStyle(.secondary) }
                }
                if !unplaced.isEmpty { unplacedList }
            }
            .frame(maxWidth: .infinity)
            FeedbackFormPreview(desk: desk, member: member, setup: setup, focused: focused?.id)
                .frame(maxWidth: .infinity)
        }
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ZStack(alignment: .topLeading) {
                FieldChrome(icon: nil, focused: writing, padding: EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10)) {
                    TextEditor(text: $text)
                        .font(.system(size: 13.5))
                        .scrollContentBackground(.hidden)
                        .focused($writing)
                        .frame(height: 76)
                }
                if text.isEmpty {
                    Text("What happened?").font(.system(size: 13.5)).foregroundStyle(Theme.textFaint)
                        .padding(.leading, 15).padding(.top, 9).allowsHitTesting(false)
                }
            }
            HStack(spacing: 10) {
                Text("⌘↩").font(.caption.monospaced()).foregroundStyle(Theme.textFaint)
                Button {
                    desk.add(text)
                    text = ""
                    writing = true
                } label: { Label("Convert to SBI", systemImage: "wand.and.stars") }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || member.grade == nil)
            }
        }
    }

    private var unplacedList: some View {
        Card {
            Text("NOT IN THE FORM YET · \(unplaced.count)")
                .font(.system(size: 11, weight: .semibold)).kerning(0.7).foregroundStyle(Theme.focus)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(unplaced) { note in
                    Button { desk.focused = note.id } label: {
                        HStack(spacing: 6) {
                            if desk.converting(note) && desk.working { ProgressView().controlSize(.mini) }
                            Text(desk.converting(note) ? (desk.working ? "Converting…" : "Couldn't convert") : String(desk.settled(note).sentence.prefix(80)))
                                .font(.callout).lineLimit(1)
                                .foregroundStyle(desk.converting(note) ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 6)
                        .background(desk.focused == note.id ? Theme.accent.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

func feedbackLevelTint(_ level: String?) -> Color {
    switch level {
    case "exceptional", "exceeds": return Theme.longBreak
    case "meets": return Theme.shortBreak
    case "minimum": return Theme.focus
    case "needs": return Theme.urgent
    default: return .secondary
    }
}

/// The selected item: its sentence, editable, and its competency and level as one-click choices.
private struct FeedbackItemEditor: View {
    @ObservedObject var desk: FeedbackDesk
    var note: FeedbackNote
    var member: FeedbackMember
    var setup: FeedbackSetup
    var latest: Bool
    @FocusState private var editing: Bool
    @State private var editingSentence = false
    @State private var hoveringSentence = false

    private var hints: [String] {
        (note.hints ?? []).compactMap { hint in
            switch hint {
            case "situation": return "no when/where"
            case "behavior": return "no action"
            case "impact": return "no result"
            case "action": return "no suggestion"
            case let other where other.hasPrefix("number:") || other.hasPrefix("word:"):
                return "“\(other.split(separator: ":", maxSplits: 1).last ?? "")” not in note"
            default: return nil
            }
        }
    }

    var body: some View {
        Card(latest ? "Just converted" : "Selected item") {
            if desk.converting(note) {
                HStack(spacing: 8) {
                    if desk.working { ProgressView().controlSize(.small) }
                    Text(desk.working ? "Converting…" : "Couldn't convert").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    if !desk.working {
                        Button("Try again") { desk.convertAgain(note.id) }.buttonStyle(.secondary).controlSize(.small)
                        Button("Discard") { desk.delete(note.id) }.buttonStyle(.ghost).controlSize(.small)
                    }
                }
                Text(note.text).font(.caption).foregroundStyle(Theme.textFaint).fixedSize(horizontal: false, vertical: true)
            } else {
                // Read as text; a click turns it into an editor, Return or
                // clicking away turns it back.
                Group {
                    if editingSentence {
                        TextField("SBI sentence", text: Binding(get: { desk.editableSentence(note) }, set: { desk.setSentence(note.id, $0) }),
                                  axis: .vertical)
                            .textFieldStyle(.plain)
                            .focused($editing)
                            .onSubmit { editingSentence = false }
                            .onChange(of: editing) { _, focused in if !focused { editingSentence = false } }
                            .onAppear { editing = true }
                    } else {
                        Text(desk.editableSentence(note))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { editingSentence = true }
                            .onHover { hoveringSentence = $0 }
                            .help("Click to edit")
                    }
                }
                .font(.system(size: 14))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(editingSentence ? Theme.fieldFill : Color.primary.opacity(hoveringSentence ? 0.06 : 0.03),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(editingSentence ? Theme.accent : .clear, lineWidth: 1.5))
                if !hints.isEmpty { Text(hints.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.textFaint) }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Competency")
                    if member.severalRoles {
                        // The choice also says which form the item goes to.
                        ForEach(member.roles, id: \.group) { role in
                            Text(role.group).font(.caption).foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(role.competencies, id: \.self) { id in
                                    choice(setup.competencies[id] ?? id,
                                           selected: note.competency == id && member.group(of: note) == role.group, tint: nil) {
                                        desk.choose(competency: id, group: role.group, for: note.id)
                                    }
                                }
                            }
                        }
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(member.competencies, id: \.self) { id in
                                choice(setup.competencies[id] ?? id, selected: note.competency == id, tint: nil) {
                                    desk.choose(competency: id, for: note.id)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        SectionLabel("Level")
                        if note.level == nil { Text("choose one").font(.caption).foregroundStyle(Theme.focus) }
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(setup.levels) { level in
                            choice(level.name.replacingOccurrences(of: " expectation", with: "").replacingOccurrences(of: " Performance", with: ""),
                                   selected: note.level == level.id, tint: feedbackLevelTint(level.id)) {
                                desk.choose(level: level.id, for: note.id)
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Delete item", role: .destructive) { desk.delete(note.id) }.buttonStyle(.ghost).controlSize(.small)
                }
            }
        }
    }

    private func choice(_ title: String, selected: Bool, tint: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let tint { Circle().fill(tint).frame(width: 7, height: 7) }
                Text(title)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(selected ? (tint ?? Theme.accent).opacity(0.2) : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(selected ? (tint ?? Theme.accent) : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The feedback form as Open form will fill it, on the form's own paper. A line selects its item.
private struct FeedbackFormPreview: View {
    @ObservedObject var desk: FeedbackDesk
    var member: FeedbackMember
    var setup: FeedbackSetup
    var focused: String?

    private static let paper = Color(red: 0.95, green: 0.94, blue: 0.98)
    private static let ink = Color(red: 0.13, green: 0.13, blue: 0.14)
    private static let faint = Color(red: 0.38, green: 0.39, blue: 0.41)
    private static let band = Color(red: 0.36, green: 0.30, blue: 0.86)
    private static let pick = Color(red: 0.84, green: 0.81, blue: 0.99)

    /// Only areas to improve so far. The feedback guide asks for balance: name what went well too.
    private func unbalanced(_ forms: [(group: String, lines: FeedbackDesk.FormLines)]) -> Bool {
        let placed = forms.flatMap(\.lines).filter { !$0.items.isEmpty }.map(\.level.id)
        return !placed.isEmpty && placed.allSatisfy { $0 == "minimum" || $0 == "needs" }
    }

    var body: some View {
        let forms = desk.formLines(member, levels: setup.levels)
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Self.band).frame(height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(setup.form).font(.system(size: 17, weight: .semibold))
                Text("What Open form fills in · \(member.name)").font(.caption).foregroundStyle(Self.faint)
                if unbalanced(forms) {
                    Text("Only areas to improve so far. Balanced feedback also names something done well.")
                        .font(.caption).foregroundStyle(Self.band).padding(.top, 4)
                }
            }
            .padding(16)
            ForEach(forms, id: \.group) { group, lines in
                if forms.count > 1 {
                    Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
                    Text("\(group) · one response").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
                }
                levelFields(lines)
            }
        }
        .foregroundStyle(Self.ink)
        .background(Self.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    private func levelFields(_ lines: FeedbackDesk.FormLines) -> some View {
        ForEach(lines, id: \.level.id) { level, items in
                Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(feedbackLevelTint(level.id)).frame(width: 7, height: 7)
                        Text(level.name).font(.system(size: 13, weight: .semibold))
                    }
                    if items.isEmpty {
                        Text("Your answer").font(.system(size: 12.5)).foregroundStyle(Self.faint.opacity(0.7))
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, note in
                        Button { desk.focused = note.id } label: {
                            Text("\(index + 1). [\(setup.competencies[note.competency ?? ""] ?? "")] \(desk.settled(note).sentence)")
                                .font(.system(size: 12.5))
                                .lineSpacing(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background(note.id == focused ? Self.pick : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}
