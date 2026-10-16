import Foundation
import AppKit

/// One observation about a member, with what the user has settled and the
/// latest draft. The shape is shared with scripts/pomodoro_feedback.py, which
/// reads this file but never writes it.
struct FeedbackNote: Codable, Identifiable, Equatable {
    struct Draft: Codable, Equatable {
        var basis: String
        var competency: String?
        var level: String?
        var group: String?
        var sentence: String
        var questions: [String]
    }

    var id: String
    var member: String
    var date: String
    /// The typed note. Only kept until it is converted, then emptied: what is
    /// stored afterwards is the sentence, competency, level and hints.
    var text: String
    var createdAt: Double
    /// Settled by the user, so Jev is not asked again.
    var competency: String?
    var level: String?
    /// The form group the item goes to, for someone the form lists under several groups.
    var group: String?
    var additions: [String: String]?
    var omit: [String]?
    var dismissed: [String]?
    var draft: Draft?
    var sentence: String?
    /// What the note did not say, from the conversion. Never blocks the form.
    var hints: [String]?
    var submittedAt: Double?
}

struct FeedbackMember: Decodable, Identifiable, Equatable {
    /// One of a person's form groups, with the competencies feedback in it can be about.
    struct Role: Decodable, Equatable { var group: String; var competencies: [String] }

    var key: String
    /// Every key the person has: one per form group they are listed under.
    var keys: [String]
    var group: String
    var name: String
    var title: String
    /// The Latin spelling from the member sheet, for search.
    var latin: String?
    var ladder: String?
    var grade: String?
    var gradeName: String
    var role: String?
    var competencies: [String]
    var roles: [Role]
    var issues: [String]
    var id: String { key }

    var severalRoles: Bool { roles.count > 1 }
    /// "ETM + Инженер" for someone the form lists under several groups.
    var groups: String { severalRoles ? roles.map(\.group).joined(separator: " + ") : group }

    /// The form group an item is filed under: the role chosen for it, the only role holding its
    /// competency, or the group it was written under. As scripts/pomodoro_feedback.py decides it.
    func group(of note: FeedbackNote) -> String {
        let names = roles.isEmpty ? [group] : roles.map(\.group)
        if let chosen = note.group, names.contains(chosen) { return chosen }
        let holding = roles.filter { role in note.competency.map(role.competencies.contains) ?? false }
        if holding.count == 1 { return holding[0].group }
        let written = String(note.member.prefix { $0 != ":" })
        return names.contains(written) ? written : group
    }
}

struct FeedbackSetup: Decodable, Equatable {
    struct Choice: Decodable, Equatable, Identifiable { var id: String; var name: String }
    var form: String
    var framework: String
    var members: [FeedbackMember]
    var grades: [String: [Choice]]
    var competencies: [String: String]
    var levels: [Choice]
}

struct FeedbackAnswers: Decodable, Equatable {
    struct Blocker: Decodable, Equatable { var noteId: String; var reason: String }
    /// One response per role that has items; a single role is always one.
    struct Form: Decodable, Equatable { var group: String; var fields: [String: String]; var url: String? }
    var forms: [Form]
    var blockers: [Blocker]
}

/// The Feedback tab's state: the imported setup, the observation log, and the
/// bridge runs that draft items and build the form link.
@MainActor
final class FeedbackDesk: ObservableObject {
    @Published private(set) var setup: FeedbackSetup?
    @Published private(set) var notes: [FeedbackNote] = []
    @Published private(set) var answers: FeedbackAnswers?
    @Published private(set) var working = false
    @Published var selected: String?
    @Published var message = ""
    /// The member whose form was opened, until the user says it was submitted.
    @Published var openedFor: String?
    /// The item shown in the editor: the one just converted, or one picked in the form preview.
    @Published var focused: String?
    /// A change arrived while drafting; draft again once the run finishes.
    private var improveAgain = false

    static var notesFile: URL { DataPaths.directory.appendingPathComponent("pomodoro-feedback-notes.json") }
    static var membersFile: URL { DataPaths.directory.appendingPathComponent("pomodoro-feedback-members.json") }
    static var formFile: URL { DataPaths.directory.appendingPathComponent("pomodoro-feedback-form.json") }
    static var frameworkFile: URL { DataPaths.directory.appendingPathComponent("pomodoro-feedback-framework.json") }

    var member: FeedbackMember? { setup?.members.first { $0.key == selected } }

    /// A member's open notes, including any written under another of their roles' keys.
    func pending(_ member: FeedbackMember) -> [FeedbackNote] {
        notes.filter { member.keys.contains($0.member) && $0.submittedAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    func submitted(_ member: FeedbackMember) -> Bool {
        pending(member).isEmpty && notes.contains { member.keys.contains($0.member) && $0.submittedAt != nil }
    }

    // MARK: Loading

    func load() {
        readNotes()
        run(["--members"]) { [weak self] output in
            guard let self else { return }
            self.setup = try JSONDecoder().decode(FeedbackSetup.self, from: Data(output.utf8))
            if let selected = self.selected, self.setup?.members.contains(where: { $0.key == selected }) != true { self.selected = nil }
            self.refreshAnswers()
        } failed: { [weak self] error in
            self?.setup = nil
            self?.message = error
        }
    }

    private func readNotes() {
        guard let text = AtomicFile.read(Self.notesFile) else { notes = []; return }
        struct File: Decodable { var notes: [FeedbackNote] }
        do {
            notes = try JSONDecoder().decode(File.self, from: Data(text.utf8)).notes
            // Notes converted before typed text was dropped still carry it.
            if notes.contains(where: { $0.draft != nil }) {
                for index in notes.indices { if let draft = notes[index].draft { Self.adopt(draft, into: &notes[index]) } }
                save()
            }
        } catch { message = "The feedback notes file is unreadable: \(error.localizedDescription)" }
    }

    /// A conversion becomes the item itself, and the typed note is let go.
    private static func adopt(_ draft: FeedbackNote.Draft, into note: inout FeedbackNote) {
        if (note.sentence ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { note.sentence = draft.sentence }
        note.competency = note.competency ?? draft.competency
        note.level = note.level ?? draft.level
        note.group = note.group ?? draft.group
        note.hints = draft.questions.filter { $0 != "competency" && $0 != "level" }
        note.text = ""
        note.draft = nil
    }

    private func save() {
        struct File: Encodable { var version = 1; var notes: [FeedbackNote] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(File(notes: notes)), let text = String(data: data, encoding: .utf8),
              AtomicFile.write(text + "\n", to: Self.notesFile) else {
            message = "Could not save feedback notes."
            return
        }
    }

    // MARK: Imports

    func importFile(_ flag: String, from url: URL) {
        run([flag, url.path]) { [weak self] _ in self?.load() } failed: { [weak self] error in self?.message = error }
    }

    /// One file holding the form, members and framework: what a release bakes in
    /// through FEEDBACK_SETUP_JSON, or what a colleague imports.
    func exportSetup(to url: URL) {
        run(["--export-setup", url.path]) { [weak self] _ in self?.message = "" } failed: { [weak self] error in self?.message = error }
    }

    /// A grade the title did not give, kept across member-list imports.
    func setGrade(_ grade: String, for key: String) {
        // A bundled setup has no file here yet; overrides start one.
        var file = (try? Data(contentsOf: Self.membersFile)).flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        } ?? [:]
        var overrides = file["overrides"] as? [String: Any] ?? [:]
        var entry = overrides[key] as? [String: Any] ?? [:]
        entry["grade"] = grade
        overrides[key] = entry
        file["overrides"] = overrides
        guard let output = try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys]),
              AtomicFile.write((String(data: output, encoding: .utf8) ?? "") + "\n", to: Self.membersFile) else {
            message = "Could not save the grade."
            return
        }
        load()
    }

    // MARK: Notes

    func add(_ text: String, date: Date = Date()) {
        guard let key = selected, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        notes.append(FeedbackNote(id: UUID().uuidString, member: key, date: Fmt.dateKey(date),
                                  text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                  createdAt: (Date().timeIntervalSince1970 * 1000).rounded()))
        focused = notes.last?.id
        save()
        improve()
    }

    func update(_ id: String, _ change: (inout FeedbackNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        change(&notes[index])
        save()
    }

    func delete(_ id: String) {
        notes.removeAll { $0.id == id }
        save()
        refreshAnswers()
    }

    /// The user's own wording. It replaces the draft in the form and is never
    /// overwritten by a later conversion.
    func setSentence(_ id: String, _ text: String) {
        update(id) { $0.sentence = text }
    }

    /// For someone in several groups a competency comes with its role, which says which form it goes to.
    func choose(competency: String? = nil, group: String? = nil, level: String? = nil, for id: String) {
        update(id) { note in
            if let competency { note.competency = competency }
            if let group { note.group = group }
            if let level { note.level = level }
        }
    }

    /// Retries a note whose conversion failed; its typed text is still there.
    func convertAgain(_ id: String) {
        update(id) { $0.sentence = nil; $0.draft = nil }
        improve()
    }

    /// The text in the editor, exactly as typed: trimming it on every keystroke
    /// would swallow a space before the next word arrives.
    func editableSentence(_ note: FeedbackNote) -> String {
        note.sentence ?? ""
    }

    func converting(_ note: FeedbackNote) -> Bool {
        (note.sentence ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the form will say for a note.
    func settled(_ note: FeedbackNote) -> (sentence: String, competency: String?, level: String?) {
        ((note.sentence ?? "").trimmingCharacters(in: .whitespacesAndNewlines), note.competency, note.level)
    }

    typealias FormLines = [(level: FeedbackSetup.Choice, items: [FeedbackNote])]

    /// The form's five fields as the preview shows them: numbered, in the order Open form sends,
    /// once per role that has items (always one form for a single role).
    func formLines(_ member: FeedbackMember, levels: [FeedbackSetup.Choice]) -> [(group: String, lines: FormLines)] {
        let open = pending(member).filter { note in
            let value = settled(note)
            return !value.sentence.isEmpty && value.competency != nil && value.level != nil
        }
        func rank(_ note: FeedbackNote) -> Int { member.competencies.firstIndex(of: note.competency ?? "") ?? member.competencies.count }
        let forms: [(group: String, lines: FormLines)] = (member.roles.isEmpty ? [member.group] : member.roles.map(\.group)).map { group in
            (group, levels.map { level in
                (level, open.filter { $0.level == level.id && member.group(of: $0) == group }.sorted {
                    (rank($0), $0.date, $0.createdAt) < (rank($1), $1.date, $1.createdAt)
                })
            })
        }
        let filled = forms.filter { $0.lines.contains { !$0.items.isEmpty } }
        return filled.isEmpty ? Array(forms.prefix(1)) : filled
    }

    /// Every open note has a sentence, a competency and a level.
    func ready(_ member: FeedbackMember) -> Bool {
        let open = pending(member)
        return !open.isEmpty && !working && open.allSatisfy { note in
            let value = settled(note)
            return !value.sentence.isEmpty && value.competency != nil && value.level != nil
        }
    }

    // MARK: Bridge

    /// Drafts every note that changed since its last draft. Runs on its own
    /// after a note is added or answered, so drafting is not a step to learn.
    func improve() {
        guard let key = selected else { return }
        if working { improveAgain = true; return }
        working = true
        run(["--improve", key]) { [weak self] output in
            guard let self else { return }
            self.finishImproving()
            struct Result: Decodable {
                struct Item: Decodable {
                    var noteId: String; var basis: String; var competency: String?; var level: String?; var group: String?
                    var sentence: String; var questions: [String]
                }
                var drafts: [Item]
            }
            let result = try JSONDecoder().decode(Result.self, from: Data(output.utf8))
            self.readNotes()
            for item in result.drafts {
                guard let index = self.notes.firstIndex(where: { $0.id == item.noteId }) else { continue }
                Self.adopt(.init(basis: item.basis, competency: item.competency, level: item.level, group: item.group,
                                 sentence: item.sentence, questions: item.questions), into: &self.notes[index])
            }
            if let last = result.drafts.last { self.focused = last.noteId }
            self.save()
            self.refreshAnswers()
        } failed: { [weak self] error in self?.message = error; self?.finishImproving() }
    }

    private func finishImproving() {
        working = false
        if improveAgain { improveAgain = false; improve() }
    }

    func refreshAnswers() {
        guard let key = selected, setup != nil else { answers = nil; return }
        run(["--form-link", key], clearsMessage: false) { [weak self] output in
            guard let self, self.selected == key else { return }
            self.answers = try JSONDecoder().decode(FeedbackAnswers.self, from: Data(output.utf8))
        } failed: { [weak self] error in self?.message = error }
    }

    /// Builds the link from what is on disk right now, so the latest edits are in it.
    func openForm() {
        guard let key = selected else { return }
        run(["--form-link", key]) { [weak self] output in
            guard let self else { return }
            let answers = try JSONDecoder().decode(FeedbackAnswers.self, from: Data(output.utf8))
            self.answers = answers
            // One form per role: someone in two groups gets two responses.
            let urls = answers.forms.compactMap { $0.url.flatMap(URL.init(string:)) }
            guard !urls.isEmpty, urls.count == answers.forms.count else {
                self.message = "Every item needs a sentence, competency and level."
                return
            }
            urls.forEach { NSWorkspace.shared.open($0) }
            self.openedFor = key
        } failed: { [weak self] error in self?.message = error }
    }

    /// The user pressed Submit in the browser: these notes are done.
    func markSubmitted() {
        guard let key = openedFor, let member = setup?.members.first(where: { $0.key == key }) else { return }
        let now = (Date().timeIntervalSince1970 * 1000).rounded()
        for index in notes.indices where member.keys.contains(notes[index].member) && notes[index].submittedAt == nil {
            notes[index].submittedAt = now
        }
        save()
        openedFor = nil
        refreshAnswers()
    }

    private func run(_ arguments: [String], clearsMessage: Bool = true,
                     done: @escaping (String) throws -> Void, failed: @escaping (String) -> Void) {
        if clearsMessage { message = "" }
        Bridge.run(DataPaths.feedbackScript, arguments) { code, output, error in
            guard code == 0 else {
                failed(error.isEmpty ? "The feedback bridge failed." : String(error.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600)))
                return
            }
            do { try done(output) } catch { failed("The feedback bridge returned invalid data.") }
        }
    }
}
