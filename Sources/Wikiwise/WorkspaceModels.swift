import Foundation

enum ResearchItemKind: String, CaseIterable, Codable, Identifiable {
    case inbox
    case note
    case source
    case thread
    case brief
    case session
    case task
    case entity
    case claim
    case question
    case draft

    var id: String { rawValue }

    var folderName: String {
        switch self {
        case .inbox: return "inbox"
        case .note: return "notes"
        case .source: return "sources"
        case .thread: return "threads"
        case .brief: return "briefs"
        case .session: return "sessions"
        case .task: return "tasks"
        case .entity: return "entities"
        case .claim: return "claims"
        case .question: return "questions"
        case .draft: return "drafts"
        }
    }

    var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .note: return "Notes"
        case .source: return "Sources"
        case .thread: return "Threads"
        case .brief: return "Briefs"
        case .session: return "Sessions"
        case .task: return "Tasks"
        case .entity: return "Entities"
        case .claim: return "Claims"
        case .question: return "Questions"
        case .draft: return "Drafts"
        }
    }

    var singularName: String {
        switch self {
        case .inbox: return "Capture"
        case .note: return "Note"
        case .source: return "Source"
        case .thread: return "Thread"
        case .brief: return "Brief"
        case .session: return "Session"
        case .task: return "Task"
        case .entity: return "Entity"
        case .claim: return "Claim"
        case .question: return "Question"
        case .draft: return "Draft"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: return "tray"
        case .note: return "note.text"
        case .source: return "link"
        case .thread: return "point.3.connected.trianglepath.dotted"
        case .brief: return "doc.richtext"
        case .session: return "clock"
        case .task: return "checklist"
        case .entity: return "person.2"
        case .claim: return "quote.bubble"
        case .question: return "questionmark.circle"
        case .draft: return "square.and.pencil"
        }
    }

    static var sidebarKinds: [ResearchItemKind] {
        [.inbox, .note, .source, .thread, .brief, .draft, .session, .task, .entity, .claim, .question]
    }
}

enum AmbientActionLevel: String, CaseIterable, Codable, Identifiable {
    case suggest
    case draft
    case maintain

    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

enum AmbientIntensity: String, CaseIterable, Codable, Identifiable {
    case off
    case quiet
    case standard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .quiet: return "Quiet"
        case .standard: return "Standard"
        }
    }
}

enum AmbientJobStatus: String, Codable {
    case queued
    case completed
    case failed
}

enum AmbientTrigger: String, Codable {
    case workspaceOpened
    case markdownChanged
    case noteCreated
    case sourceCaptured
    case sessionEnded
    case dailyReview
    case manual
}

enum AmbientSkillName: String, CaseIterable, Codable, Identifiable {
    case captureSource = "capture-source"
    case distillNote = "distill-note"
    case connectThread = "connect-thread"
    case buildBrief = "build-brief"
    case sessionCloseout = "session-closeout"
    case contradictionCheck = "contradiction-check"
    case dailyReview = "daily-review"
    case researchSprint = "research-sprint"

    var id: String { rawValue }
}

struct ResearchItem: Identifiable, Hashable {
    let id: String
    let kind: ResearchItemKind
    let url: URL
    let title: String
    let summary: String?
    let createdAt: Date?
    let updatedAt: Date?
    let providerID: String?
    let skillName: String?

    var relativePath: String
}

struct AmbientSuggestion: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var title: String
    var body: String
    var actionLevel: AmbientActionLevel
    var skillName: String
    var providerID: String
    var sourcePath: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        body: String,
        actionLevel: AmbientActionLevel,
        skillName: String,
        providerID: String,
        sourcePath: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.actionLevel = actionLevel
        self.skillName = skillName
        self.providerID = providerID
        self.sourcePath = sourcePath
    }
}

struct AmbientJob: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var completedAt: Date?
    var trigger: AmbientTrigger
    var actionLevel: AmbientActionLevel
    var status: AmbientJobStatus
    var skillName: String
    var providerID: String
    var sourcePath: String?
    var outputPath: String?
    var summary: String
    var error: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        trigger: AmbientTrigger,
        actionLevel: AmbientActionLevel,
        status: AmbientJobStatus,
        skillName: String,
        providerID: String,
        sourcePath: String? = nil,
        outputPath: String? = nil,
        summary: String,
        error: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.trigger = trigger
        self.actionLevel = actionLevel
        self.status = status
        self.skillName = skillName
        self.providerID = providerID
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.summary = summary
        self.error = error
    }
}

struct WorkspaceSettings: Codable, Equatable {
    var activeProvider: AIProviderKind
    var customProviderCommand: String
    var ambientIntensity: AmbientIntensity
    var backgroundProcessingEnabled: Bool
    var defaultActionLevel: AmbientActionLevel
    var showProvenance: Bool

    static let `default` = WorkspaceSettings(
        activeProvider: .codex,
        customProviderCommand: "",
        ambientIntensity: .quiet,
        backgroundProcessingEnabled: true,
        defaultActionLevel: .suggest,
        showProvenance: true
    )
}

struct WorkspaceState: Codable {
    var schemaVersion: Int
    var settings: WorkspaceSettings
    var suggestions: [AmbientSuggestion]
    var jobs: [AmbientJob]

    static let empty = WorkspaceState(
        schemaVersion: 1,
        settings: .default,
        suggestions: [],
        jobs: []
    )
}

struct MarkdownFrontmatter {
    var values: [String: String]
    var body: String

    subscript(_ key: String) -> String? {
        values[key]
    }
}

enum MarkdownMetadata {
    static func parse(_ markdown: String) -> MarkdownFrontmatter {
        guard markdown.hasPrefix("---\n"),
              let endRange = markdown.range(of: "\n---", options: [], range: markdown.index(markdown.startIndex, offsetBy: 4)..<markdown.endIndex)
        else {
            return MarkdownFrontmatter(values: [:], body: markdown)
        }

        let frontmatterText = String(markdown[markdown.index(markdown.startIndex, offsetBy: 4)..<endRange.lowerBound])
        var values: [String: String] = [:]
        for line in frontmatterText.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                values[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        var bodyStart = endRange.upperBound
        if bodyStart < markdown.endIndex, markdown[bodyStart] == "\n" {
            bodyStart = markdown.index(after: bodyStart)
        }
        return MarkdownFrontmatter(values: values, body: String(markdown[bodyStart...]))
    }

    static func title(from markdown: String, fallback: String) -> String {
        let parsed = parse(markdown)
        if let title = parsed["title"], !title.isEmpty {
            return title
        }
        if let match = parsed.body.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) {
            return String(match.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return fallback
    }
}
