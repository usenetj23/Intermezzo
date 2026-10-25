import Foundation

/// Metadata of a project. Tasks and records refer to a project by NAME;
/// names are unique, ignoring case.
public struct PomodoroProject: Codable, Equatable, Identifiable, Sendable {
    public static let defaultColorHex = "#5AD9A0"
    public static let defaultCurrency = "PLN"

    public var id: UUID
    public var name: String
    public var colorHex: String
    public var client: String
    public var hourlyRate: Double?
    public var currency: String
    public var billable: Bool
    public var archived: Bool

    public static let maxHourlyRate = 1_000_000.0

    /// Parses typed rate text ("12,5" ok). Nil unless a finite number in 0...maxHourlyRate.
    public static func parseRate(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v.isFinite, v >= 0, v <= maxHourlyRate else { return nil }
        return v
    }

    public init(id: UUID = UUID(), name: String, colorHex: String = PomodoroProject.defaultColorHex,
                client: String = "", hourlyRate: Double? = nil,
                currency: String = PomodoroProject.defaultCurrency,
                billable: Bool = false, archived: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.client = client
        self.hourlyRate = hourlyRate
        self.currency = currency
        self.billable = billable
        self.archived = archived
    }

    // Stored data may lack any field except the name.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? Self.defaultColorHex
        client = try c.decodeIfPresent(String.self, forKey: .client) ?? ""
        hourlyRate = try c.decodeIfPresent(Double.self, forKey: .hourlyRate)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Self.defaultCurrency
        billable = try c.decodeIfPresent(Bool.self, forKey: .billable) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}

extension PomodoroLedger {
    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive]) == .orderedSame
    }

    public func project(named name: String) -> PomodoroProject? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return projects.first { Self.sameName($0.name, trimmed) }
    }

    /// Not archived, sorted by name.
    public var activeProjects: [PomodoroProject] {
        projects.filter { !$0.archived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Canonical stored name of an ACTIVE project matching `name`, else nil
    /// (blank, unknown or archived). Used to validate a remembered selection.
    public func activeProjectName(_ name: String) -> String? {
        guard let p = project(named: name), !p.archived else { return nil }
        return p.name
    }

    /// Makes `name` usable for a new task: creates the project, or restores it
    /// if archived. Nil for a blank name.
    public func creatingOrRestoringProject(named name: String) -> (ledger: PomodoroLedger, name: String)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if var existing = project(named: trimmed) {
            existing.archived = false
            return (upsertingProject(existing), existing.name)
        }
        let created = upsertingProject(PomodoroProject(name: trimmed))
        return (created, trimmed)
    }

    /// Adds the project or replaces the one with the same `id`. A blank name,
    /// or a name already taken by another project, leaves the ledger unchanged.
    public func upsertingProject(_ p: PomodoroProject) -> PomodoroLedger {
        var entry = p
        entry.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.name.isEmpty else { return self }
        entry.currency = entry.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let clash = project(named: entry.name), clash.id != entry.id { return self }
        var copy = self
        if let i = copy.projects.firstIndex(where: { $0.id == entry.id }) {
            if copy.projects[i].name != entry.name {
                // A different name must carry the tasks and records along.
                guard let renamed = renamingProject(id: entry.id, to: entry.name) else { return self }
                copy = renamed
            }
            copy.projects[i] = entry
        } else {
            copy.projects.append(entry)
        }
        return copy
    }

    /// Renames a project and rewrites tasks, records and the running pomodoro.
    /// `nil` when the name is blank or taken by another project (ignoring case).
    public func renamingProject(id: UUID, to name: String) -> PomodoroLedger? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return nil }
        if let clash = project(named: trimmed), clash.id != id { return nil }
        let old = projects[index].name
        var copy = self
        copy.projects[index].name = trimmed
        for i in copy.tasks.indices where Self.sameName(copy.tasks[i].project, old) { copy.tasks[i].project = trimmed }
        for i in copy.records.indices where Self.sameName(copy.records[i].project, old) { copy.records[i].project = trimmed }
        if var run = copy.current, Self.sameName(run.project, old) {
            run.project = trimmed
            copy.current = run
        }
        return copy
    }

    /// Money earned per currency for pomodoros ending in [from, to): hours ×
    /// rate, only for billable projects that have a rate.
    public func earnings(from: Date, to: Date) -> [String: Double] {
        var sums: [String: Double] = [:]
        for record in records where record.date >= from && record.date < to {
            guard let p = project(named: record.project), p.billable, let rate = p.hourlyRate else { continue }
            sums[p.currency.uppercased(), default: 0] += Double(record.actualSeconds) / 3600 * rate
        }
        return sums
    }

    /// Gives every project name used by a task (and missing from `projects`) a
    /// default entry. Migrates data saved before projects had metadata.
    public static func backfillingProjects(_ ledger: PomodoroLedger) -> PomodoroLedger {
        var copy = ledger
        for task in ledger.tasks {
            let name = task.project.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, copy.project(named: name) == nil {
                copy.projects.append(PomodoroProject(name: name))
            }
        }
        return copy
    }
}
