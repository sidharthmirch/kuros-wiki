import Foundation

enum AmbientOrchestrator {
    static func suggestions(
        for item: ResearchItem,
        settings: WorkspaceSettings
    ) -> [AmbientSuggestion] {
        let providerID = settings.activeProvider.provenanceID
        var results: [AmbientSuggestion] = []

        switch item.kind {
        case .inbox:
            results.append(AmbientSuggestion(
                title: "Distill this capture",
                body: "Turn this rough capture into a structured note, then move durable claims into notes, entities, or questions.",
                actionLevel: .suggest,
                skillName: AmbientSkillName.distillNote.rawValue,
                providerID: providerID,
                sourcePath: item.relativePath
            ))
        case .source:
            results.append(AmbientSuggestion(
                title: "Capture source provenance",
                body: "Extract the source title, author, URL, core claims, and links to related notes before using it in a brief.",
                actionLevel: .suggest,
                skillName: AmbientSkillName.captureSource.rawValue,
                providerID: providerID,
                sourcePath: item.relativePath
            ))
        case .note:
            results.append(AmbientSuggestion(
                title: "Connect this note to a thread",
                body: "Look for nearby notes, open questions, entities, and claims that should be linked or spun into a research thread.",
                actionLevel: .suggest,
                skillName: AmbientSkillName.connectThread.rawValue,
                providerID: providerID,
                sourcePath: item.relativePath
            ))
        case .thread:
            results.append(AmbientSuggestion(
                title: "Build a brief from this thread",
                body: "Create a reviewable draft brief with thesis, evidence, open questions, and next-source requests.",
                actionLevel: .draft,
                skillName: AmbientSkillName.buildBrief.rawValue,
                providerID: providerID,
                sourcePath: item.relativePath
            ))
        default:
            break
        }

        return results
    }

    static func maintenanceJob(
        rootURL: URL,
        items: [ResearchItem],
        settings: WorkspaceSettings,
        trigger: AmbientTrigger
    ) throws -> AmbientJob {
        let index = buildAmbientIndex(items: items, settings: settings)
        let outputURL = rootURL.appendingPathComponent(".kuros-wiki/ambient-index.md")
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try index.write(to: outputURL, atomically: true, encoding: .utf8)

        return AmbientJob(
            completedAt: Date(),
            trigger: trigger,
            actionLevel: .maintain,
            status: .completed,
            skillName: AmbientSkillName.connectThread.rawValue,
            providerID: settings.activeProvider.provenanceID,
            outputPath: ".kuros-wiki/ambient-index.md",
            summary: "Updated the ambient workspace index from local markdown."
        )
    }

    static func dailyReviewJob(
        rootURL: URL,
        items: [ResearchItem],
        settings: WorkspaceSettings
    ) throws -> AmbientJob {
        let now = Date()
        let outputURL = uniqueOutputURL(
            in: rootURL.appendingPathComponent("drafts"),
            baseName: "daily-review-\(slugTimestamp(now))"
        )
        let outputPath = "drafts/\(outputURL.lastPathComponent)"
        let body = draftHeader(
            title: "Daily Review",
            kind: .draft,
            skill: .dailyReview,
            settings: settings
        ) + """

        # Daily Review

        ## Recent Workspace Movement

        \(recentItemsList(items))

        ## Open Questions

        \(items.filter { $0.kind == .question }.prefix(8).map { "- [[\(slug(for: $0))]]" }.joined(separator: "\n"))

        ## Suggested Next Actions

        - Pick one active thread and run `research-sprint`.
        - Promote useful inbox captures into notes.
        - Review claims that lack a source link.

        ## Provider Handoff

        Active provider: \(settings.activeProvider.displayName)

        To deepen this review, run the `daily-review` skill from `skills/daily-review/SKILL.md`.
        """

        try body.write(to: outputURL, atomically: true, encoding: .utf8)
        return AmbientJob(
            completedAt: now,
            trigger: .dailyReview,
            actionLevel: .draft,
            status: .completed,
            skillName: AmbientSkillName.dailyReview.rawValue,
            providerID: settings.activeProvider.provenanceID,
            outputPath: outputPath,
            summary: "Created a reviewable daily review draft."
        )
    }

    static func sessionCloseoutJob(
        rootURL: URL,
        items: [ResearchItem],
        settings: WorkspaceSettings
    ) throws -> AmbientJob {
        let now = Date()
        let outputURL = uniqueOutputURL(
            in: rootURL.appendingPathComponent("sessions"),
            baseName: "session-closeout-\(slugTimestamp(now))"
        )
        let outputPath = "sessions/\(outputURL.lastPathComponent)"
        let body = draftHeader(
            title: "Session Closeout",
            kind: .session,
            skill: .sessionCloseout,
            settings: settings
        ) + """

        # Session Closeout

        ## What Changed

        \(recentItemsList(items))

        ## Promising Threads

        \(items.filter { $0.kind == .thread }.prefix(6).map { "- [[\(slug(for: $0))]]" }.joined(separator: "\n"))

        ## Next Steps

        - Decide which draft should become an authored note.
        - Attach source material to any claims that changed today.
        - Run `contradiction-check` before publishing a brief.

        ## Provenance

        Created by Kuro's Wiki ambient maintain mode for \(settings.activeProvider.displayName).
        """

        try body.write(to: outputURL, atomically: true, encoding: .utf8)
        return AmbientJob(
            completedAt: now,
            trigger: .sessionEnded,
            actionLevel: .draft,
            status: .completed,
            skillName: AmbientSkillName.sessionCloseout.rawValue,
            providerID: settings.activeProvider.provenanceID,
            outputPath: outputPath,
            summary: "Created a session closeout draft."
        )
    }

    private static func buildAmbientIndex(items: [ResearchItem], settings: WorkspaceSettings) -> String {
        let grouped = Dictionary(grouping: items, by: \.kind)
        let sections = ResearchItemKind.sidebarKinds.map { kind -> String in
            let rows = (grouped[kind] ?? [])
                .prefix(20)
                .map { "- `\($0.relativePath)` \(escapeListTitle($0.title))" }
                .joined(separator: "\n")
            return "## \(kind.displayName)\n\n\(rows.isEmpty ? "_None yet._" : rows)"
        }.joined(separator: "\n\n")

        return """
        ---
        type: ambient-index
        generated_by: kuros-wiki
        provider: \(settings.activeProvider.provenanceID)
        generated_at: \(ISO8601DateFormatter().string(from: Date()))
        ---

        # Ambient Workspace Index

        This file is generated from local markdown. It is safe to replace.

        \(sections)
        """
    }

    private static func draftHeader(
        title: String,
        kind: ResearchItemKind,
        skill: AmbientSkillName,
        settings: WorkspaceSettings
    ) -> String {
        """
        ---
        title: "\(title)"
        type: \(kind.rawValue)
        status: draft
        action_level: draft
        provider: \(settings.activeProvider.provenanceID)
        skill: \(skill.rawValue)
        created_at: \(ISO8601DateFormatter().string(from: Date()))
        accepted: false
        ---
        """
    }

    private static func recentItemsList(_ items: [ResearchItem]) -> String {
        let rows = items
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .prefix(10)
            .map { "- \(escapeListTitle($0.title)) (`\($0.relativePath)`)" }
            .joined(separator: "\n")
        return rows.isEmpty ? "_No recent local items found._" : rows
    }

    private static func slugTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }

    private static func slug(for item: ResearchItem) -> String {
        let path = item.relativePath
        if path.hasPrefix("wiki/") {
            return item.url.deletingPathExtension().lastPathComponent
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
        }
        let pathWithoutExtension = stripMarkdownExtension(path)
        return pathWithoutExtension
            .split(separator: "/")
            .map { slugComponent(String($0)) }
            .joined(separator: "++")
    }

    private static func stripMarkdownExtension(_ path: String) -> String {
        path.lowercased().hasSuffix(".md") ? String(path.dropLast(3)) : path
    }

    private static func slugComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.lowercased().addingPercentEncoding(withAllowedCharacters: allowed) ?? value.lowercased()
    }

    private static func uniqueOutputURL(in folder: URL, baseName: String) -> URL {
        var candidate = folder.appendingPathComponent("\(baseName).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName)-\(counter).md")
            counter += 1
        }
        return candidate
    }

    private static func escapeListTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "\n", with: " ")
    }
}
