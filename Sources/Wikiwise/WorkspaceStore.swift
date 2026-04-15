import Combine
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var settings: WorkspaceSettings = .default
    @Published private(set) var items: [ResearchItem] = []
    @Published private(set) var suggestions: [AmbientSuggestion] = []
    @Published private(set) var jobs: [AmbientJob] = []
    @Published private(set) var lastError: String?

    var providerStatus: AIProviderStatus {
        AIProviderRegistry.status(for: settings)
    }

    var isOpen: Bool {
        rootURL != nil
    }

    func open(rootURL: URL) {
        self.rootURL = rootURL
        do {
            try bootstrapIfNeeded(rootURL: rootURL)
            try loadState()
            refresh()
            if settings.backgroundProcessingEnabled && settings.ambientIntensity == .standard {
                try runMaintenance(trigger: .workspaceOpened)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() {
        guard let rootURL else {
            items = []
            return
        }

        items = scanItems(rootURL: rootURL)
    }

    func updateSettings(_ mutate: (inout WorkspaceSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        saveState()
    }

    @discardableResult
    func capture(text: String, as kind: ResearchItemKind = .inbox) -> URL? {
        guard rootURL != nil else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let inferredKind: ResearchItemKind = kind == .inbox && trimmed.lowercased().hasPrefix("http") ? .source : kind
        let title = inferTitle(from: trimmed, fallback: inferredKind.singularName)
        let body: String
        if inferredKind == .source, trimmed.lowercased().hasPrefix("http") {
            body = """
            Source: \(trimmed)

            ## Notes

            Capture why this source matters here.
            """
        } else {
            body = trimmed
        }

        do {
            let url = try createItem(kind: inferredKind, title: title, body: body, skillName: inferredKind == .source ? AmbientSkillName.captureSource.rawValue : nil)
            refresh()
            addSuggestions(for: url, trigger: inferredKind == .source ? .sourceCaptured : .noteCreated)
            return url
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createBlankItem(kind: ResearchItemKind) -> URL? {
        do {
            let url = try createItem(
                kind: kind,
                title: "Untitled \(kind.singularName)",
                body: "Start writing here.",
                skillName: nil
            )
            refresh()
            addSuggestions(for: url, trigger: .noteCreated)
            return url
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func handleMarkdownChanged(paths: Set<String>) {
        refresh()
        guard settings.backgroundProcessingEnabled, settings.ambientIntensity != .off else { return }

        let changedItems = items.filter { paths.contains($0.url.path) }
        for item in changedItems.prefix(settings.ambientIntensity == .quiet ? 2 : 6) {
            appendSuggestions(AmbientOrchestrator.suggestions(for: item, settings: settings))
        }

        if settings.ambientIntensity == .standard {
            do {
                try runMaintenance(trigger: .markdownChanged)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func runMaintenance(trigger: AmbientTrigger = .manual) throws {
        guard let rootURL else { return }
        let job = try AmbientOrchestrator.maintenanceJob(
            rootURL: rootURL,
            items: items,
            settings: settings,
            trigger: trigger
        )
        appendJob(job)
    }

    func createDailyReview() {
        guard let rootURL else { return }
        do {
            let job = try AmbientOrchestrator.dailyReviewJob(rootURL: rootURL, items: items, settings: settings)
            appendJob(job)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func closeSession() {
        guard let rootURL else { return }
        do {
            let job = try AmbientOrchestrator.sessionCloseoutJob(rootURL: rootURL, items: items, settings: settings)
            appendJob(job)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearSuggestions() {
        suggestions = []
        saveState()
    }

    private func bootstrapIfNeeded(rootURL: URL) throws {
        let fm = FileManager.default
        for kind in ResearchItemKind.allCases {
            try fm.createDirectory(
                at: rootURL.appendingPathComponent(kind.folderName),
                withIntermediateDirectories: true
            )
        }
        try fm.createDirectory(at: rootURL.appendingPathComponent(".wikiwise"), withIntermediateDirectories: true)
        try fm.createDirectory(at: rootURL.appendingPathComponent(".claude/skills"), withIntermediateDirectories: true)

        let stateURL = stateURL(rootURL: rootURL)
        if !fm.fileExists(atPath: stateURL.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(WorkspaceState.empty).write(to: stateURL)
        }

        try createReadmeIfMissing(rootURL: rootURL)
        try copyCanonicalSkillsIfAvailable(rootURL: rootURL)
        try createProviderBridgeIfMissing(rootURL: rootURL)
    }

    private func loadState() throws {
        guard let rootURL else { return }
        let url = stateURL(rootURL: rootURL)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(WorkspaceState.self, from: data)
        settings = state.settings
        suggestions = state.suggestions
        jobs = state.jobs
    }

    private func saveState() {
        guard let rootURL else { return }
        let state = WorkspaceState(
            schemaVersion: 1,
            settings: settings,
            suggestions: suggestions,
            jobs: jobs
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: stateURL(rootURL: rootURL))
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stateURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(".wikiwise/workspace.json")
    }

    private func createItem(
        kind: ResearchItemKind,
        title: String,
        body: String,
        skillName: String?
    ) throws -> URL {
        guard let rootURL else { throw CocoaError(.fileNoSuchFile) }
        let folder = rootURL.appendingPathComponent(kind.folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = uniqueMarkdownURL(in: folder, title: title)
        let now = ISO8601DateFormatter().string(from: Date())
        let skillLine = skillName.map { "skill: \($0)\n" } ?? ""
        let content = """
        ---
        title: "\(escapeYAML(title))"
        type: \(kind.rawValue)
        status: active
        provider: \(settings.activeProvider.provenanceID)
        action_level: \(settings.defaultActionLevel.rawValue)
        created_at: \(now)
        updated_at: \(now)
        \(skillLine)accepted: true
        ---

        # \(title)

        \(body)
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func scanItems(rootURL: URL) -> [ResearchItem] {
        let fm = FileManager.default
        var result: [ResearchItem] = []
        let isoFormatter = ISO8601DateFormatter()

        for kind in ResearchItemKind.allCases {
            let folder = rootURL.appendingPathComponent(kind.folderName)
            guard let enumerator = fm.enumerator(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "md" {
                guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                let metadata = MarkdownMetadata.parse(content)
                let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
                let title = MarkdownMetadata.title(from: content, fallback: fallbackTitle)
                let rootPath = rootURL.standardizedFileURL.path
                let filePath = fileURL.standardizedFileURL.path
                let relativePath = filePath.hasPrefix(rootPath + "/")
                    ? String(filePath.dropFirst(rootPath.count + 1))
                    : fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                result.append(ResearchItem(
                    id: fileURL.path,
                    kind: kind,
                    url: fileURL,
                    title: title,
                    summary: metadata["summary"],
                    createdAt: metadata["created_at"].flatMap { isoFormatter.date(from: $0) } ?? values.creationDate,
                    updatedAt: metadata["updated_at"].flatMap { isoFormatter.date(from: $0) } ?? values.contentModificationDate,
                    providerID: metadata["provider"],
                    skillName: metadata["skill"],
                    relativePath: relativePath
                ))
            }
        }

        return result.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    private func addSuggestions(for url: URL, trigger: AmbientTrigger) {
        guard settings.backgroundProcessingEnabled, settings.ambientIntensity != .off else { return }
        refresh()
        let targetPath = url.standardizedFileURL.path
        guard let item = items.first(where: { $0.url.standardizedFileURL.path == targetPath }) else { return }
        appendSuggestions(AmbientOrchestrator.suggestions(for: item, settings: settings))
        if settings.ambientIntensity == .standard {
            try? runMaintenance(trigger: trigger)
        }
    }

    private func appendSuggestions(_ newSuggestions: [AmbientSuggestion]) {
        guard !newSuggestions.isEmpty else { return }
        let existingKeys = Set(suggestions.map { "\($0.skillName)|\($0.sourcePath ?? "")|\($0.title)" })
        let filtered = newSuggestions.filter { !existingKeys.contains("\($0.skillName)|\($0.sourcePath ?? "")|\($0.title)") }
        suggestions = Array((filtered + suggestions).prefix(20))
        saveState()
    }

    private func appendJob(_ job: AmbientJob) {
        jobs = Array(([job] + jobs).prefix(40))
        saveState()
    }

    private func uniqueMarkdownURL(in folder: URL, title: String) -> URL {
        let base = slugify(title.isEmpty ? "untitled" : title)
        var candidate = folder.appendingPathComponent("\(base).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(counter).md")
            counter += 1
        }
        return candidate
    }

    private func createReadmeIfMissing(rootURL: URL) throws {
        let readmeURL = rootURL.appendingPathComponent("README.workspace.md")
        guard !FileManager.default.fileExists(atPath: readmeURL.path) else { return }
        let content = """
        # Ambient Research Workspace

        This folder is local-first. Notes, sources, threads, briefs, sessions, tasks, entities, claims, questions, and drafts are plain markdown.

        The app owns `.wikiwise/workspace.json` for provider selection, ambient settings, suggestions, and job history.

        Canonical skills live in `skills/`. Provider-specific bridges may mirror them, such as `.claude/skills/`.
        """
        try content.write(to: readmeURL, atomically: true, encoding: .utf8)
    }

    private func createProviderBridgeIfMissing(rootURL: URL) throws {
        let bridgeURL = rootURL.appendingPathComponent(".wikiwise/provider-bridge.md")
        guard !FileManager.default.fileExists(atPath: bridgeURL.path) else { return }
        let content = """
        # Provider Bridge

        Wikiwise owns the workspace model. The active AI provider supplies reasoning and execution through the terminal.

        - Canonical skills: `skills/<name>/SKILL.md`
        - Codex and Cursor-style agents: read `AGENTS.md` and `skills/`
        - Claude Code-style agents: read `CLAUDE.md` and `.claude/skills/`

        Generated artifacts should include frontmatter with `provider`, `skill`, `created_at`, `action_level`, and `accepted`.
        """
        try content.write(to: bridgeURL, atomically: true, encoding: .utf8)
    }

    private func copyCanonicalSkillsIfAvailable(rootURL: URL) throws {
        guard let scaffoldURL = wikiwiseBundle.url(forResource: "scaffold", withExtension: nil) else { return }
        let scaffoldSkillsURL = scaffoldURL.appendingPathComponent("skills")
        let fm = FileManager.default
        let canonicalRoot = rootURL.appendingPathComponent("skills")
        let claudeRoot = rootURL.appendingPathComponent(".claude/skills")
        try fm.createDirectory(at: canonicalRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: claudeRoot, withIntermediateDirectories: true)

        let skillFolders = (try? fm.contentsOfDirectory(at: scaffoldSkillsURL, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for skillURL in skillFolders {
            guard (try? skillURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = skillURL.lastPathComponent
            let canonicalDest = canonicalRoot.appendingPathComponent(name)
            let claudeDest = claudeRoot.appendingPathComponent(name)
            if !fm.fileExists(atPath: canonicalDest.path) {
                try fm.copyItem(at: skillURL, to: canonicalDest)
            }
            if !fm.fileExists(atPath: claudeDest.path) {
                try fm.copyItem(at: skillURL, to: claudeDest)
            }
        }
    }

    private func inferTitle(from text: String, fallback: String) -> String {
        if let firstHeading = text.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) {
            return String(firstHeading.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if text.lowercased().hasPrefix("http"), let url = URL(string: text), let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? fallback
        let clipped = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped.isEmpty ? fallback : String(clipped.prefix(64))
    }

    private func slugify(_ value: String) -> String {
        let lowercased = value.lowercased()
        let scalars = lowercased.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let joined = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return joined.isEmpty ? "untitled" : joined
    }

    private func escapeYAML(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
