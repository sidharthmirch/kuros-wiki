import Foundation

enum AIProviderKind: String, CaseIterable, Codable, Identifiable {
    case codex
    case claude
    case cursor
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .cursor: return "Cursor-compatible"
        case .custom: return "Custom"
        }
    }

    var defaultCommand: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .cursor: return "cursor ."
        case .custom: return ""
        }
    }

    var bridgeDescription: String {
        switch self {
        case .codex:
            return "Reads root AGENTS.md and canonical skills in skills/."
        case .claude:
            return "Uses .claude/skills/ plus CLAUDE.md bridge files."
        case .cursor:
            return "Uses AGENTS.md and markdown skill files as project rules."
        case .custom:
            return "Uses the configured shell command and canonical skills."
        }
    }

    var provenanceID: String { rawValue }
}

struct AIProviderStatus: Equatable {
    let kind: AIProviderKind
    let command: String
    let isAvailable: Bool
    let message: String
}

protocol AIProviderAdapter {
    var kind: AIProviderKind { get }
    func launchCommand(settings: WorkspaceSettings) -> String
    func status(settings: WorkspaceSettings) -> AIProviderStatus
    func skillBridgePaths(in rootURL: URL) -> [URL]
}

struct ShellAIProviderAdapter: AIProviderAdapter {
    let kind: AIProviderKind

    func launchCommand(settings: WorkspaceSettings) -> String {
        if kind == .custom {
            return settings.customProviderCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return kind.defaultCommand
    }

    func status(settings: WorkspaceSettings) -> AIProviderStatus {
        let command = launchCommand(settings: settings)
        guard !command.isEmpty else {
            return AIProviderStatus(
                kind: kind,
                command: command,
                isAvailable: false,
                message: "No command configured."
            )
        }

        let executable = command.split(separator: " ").first.map(String.init) ?? command
        if executable.contains("/") {
            let exists = FileManager.default.isExecutableFile(atPath: executable)
            return AIProviderStatus(
                kind: kind,
                command: command,
                isAvailable: exists,
                message: exists ? "Executable found." : "Executable not found."
            )
        }

        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let found = paths.contains { path in
            FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: path).appendingPathComponent(executable).path)
        }

        return AIProviderStatus(
            kind: kind,
            command: command,
            isAvailable: found,
            message: found ? "Ready in terminal." : "Command not found on PATH."
        )
    }

    func skillBridgePaths(in rootURL: URL) -> [URL] {
        switch kind {
        case .codex, .cursor, .custom:
            return [
                rootURL.appendingPathComponent("AGENTS.md"),
                rootURL.appendingPathComponent("skills")
            ]
        case .claude:
            return [
                rootURL.appendingPathComponent("CLAUDE.md"),
                rootURL.appendingPathComponent(".claude/skills")
            ]
        }
    }
}

enum AIProviderRegistry {
    static func adapter(for kind: AIProviderKind) -> AIProviderAdapter {
        ShellAIProviderAdapter(kind: kind)
    }

    static func status(for settings: WorkspaceSettings) -> AIProviderStatus {
        adapter(for: settings.activeProvider).status(settings: settings)
    }
}
