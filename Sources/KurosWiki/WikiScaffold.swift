import Foundation

/// Creates a new ambient research workspace with wiki-compatible
/// markdown, canonical skills, provider bridges, and build tooling.
enum WikiScaffold {

    enum ScaffoldError: Error {
        case missingResources
    }

    /// Create a new wiki at the given URL.
    /// - Parameters:
    ///   - url: The directory to create the wiki in (will be created if needed).
    ///   - name: Human-readable wiki name, used in CLAUDE.md.
    static func create(at url: URL, name: String) throws {
        let fm = FileManager.default

        // Create directory structure
        let dirs = [
            url.path,
            url.appendingPathComponent("inbox").path,
            url.appendingPathComponent("notes").path,
            url.appendingPathComponent("sources").path,
            url.appendingPathComponent("threads").path,
            url.appendingPathComponent("briefs").path,
            url.appendingPathComponent("sessions").path,
            url.appendingPathComponent("tasks").path,
            url.appendingPathComponent("entities").path,
            url.appendingPathComponent("claims").path,
            url.appendingPathComponent("questions").path,
            url.appendingPathComponent("drafts").path,
            url.appendingPathComponent("raw").path,
            url.appendingPathComponent("wiki").path,
            url.appendingPathComponent("wiki/sources").path,
            url.appendingPathComponent("site").path,
            url.appendingPathComponent("site/out").path,
            url.appendingPathComponent(".kuros-wiki").path,
            url.appendingPathComponent("skills").path,
            url.appendingPathComponent(".claude").path,
            url.appendingPathComponent(".claude/skills").path,
        ]
        for dir in dirs {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        // Copy scaffold templates from the app bundle
        guard let scaffoldDir = kurosWikiBundle.url(forResource: "scaffold", withExtension: nil) else {
            throw ScaffoldError.missingResources
        }

        // CLAUDE.md — replace placeholder with wiki name
        let claudeTemplate = try String(contentsOf: scaffoldDir.appendingPathComponent("CLAUDE.md"), encoding: .utf8)
        let claudeContent = claudeTemplate.replacingOccurrences(of: "{{WIKI_NAME}}", with: name)
        try claudeContent.write(to: url.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        // AGENTS.md — cross-agent instructions (Cursor, Codex, Windsurf, etc.)
        let agentsSource = scaffoldDir.appendingPathComponent("AGENTS.md")
        try fm.copyItem(at: agentsSource, to: url.appendingPathComponent("AGENTS.md"))

        // llm-wiki.md — Karpathy's pattern description (read-only reference)
        let llmWikiSource = scaffoldDir.appendingPathComponent("llm-wiki.md")
        if fm.fileExists(atPath: llmWikiSource.path) {
            try fm.copyItem(at: llmWikiSource, to: url.appendingPathComponent("llm-wiki.md"))
        }

        // Wiki seed files
        let wikiFiles = ["home.md", "index.md", "log.md"]
        for file in wikiFiles {
            let source = scaffoldDir.appendingPathComponent("wiki/\(file)")
            let dest = url.appendingPathComponent("wiki/\(file)")
            // home.md has a {{WIKI_PATH}} placeholder for the terminal snippet
            if file == "home.md" {
                let template = try String(contentsOf: source, encoding: .utf8)
                let content = template.replacingOccurrences(of: "{{WIKI_PATH}}", with: url.path)
                try content.write(to: dest, atomically: true, encoding: .utf8)
            } else {
                try fm.copyItem(at: source, to: dest)
            }
        }

        // Canonical skills plus provider-specific mirrors.
        for skill in ScaffoldSkillCatalog.currentSkillDirs {
            let source = scaffoldDir.appendingPathComponent("skills/\(skill)")
            guard fm.fileExists(atPath: source.path) else { continue }
            try fm.copyItem(at: source, to: url.appendingPathComponent("skills/\(skill)"))
            try fm.copyItem(at: source, to: url.appendingPathComponent(".claude/skills/\(skill)"))
        }

        // Workspace state — the app owns this file, agents may read it.
        let workspaceState = """
        {
          "activeProfileID" : "kuro",
          "jobs" : [],
          "profiles" : [
            {
              "id" : "kuro"
            }
          ],
          "schemaVersion" : 1,
          "settings" : {
            "activeProvider" : "codex",
            "ambientIntensity" : "quiet",
            "backgroundProcessingEnabled" : true,
            "customProviderCommand" : "",
            "defaultActionLevel" : "suggest",
            "showProvenance" : true
          },
          "suggestions" : []
        }
        """
        try workspaceState.write(to: url.appendingPathComponent(".kuros-wiki/workspace.json"), atomically: true, encoding: .utf8)
        try "kuro\n".write(to: url.appendingPathComponent(".claude/active-user"), atomically: true, encoding: .utf8)

        let providerBridge = """
        # Provider Bridge

        Kuro's Wiki owns the workspace model. The active provider supplies reasoning and execution through the terminal.

        - Canonical skills: `skills/<name>/SKILL.md`
        - Codex and Cursor-style agents: read `AGENTS.md` and `skills/`
        - Claude Code-style agents: read `CLAUDE.md` and `.claude/skills/`
        - Active profile: `.claude/active-user`

        Generated artifacts should include `provider`, `skill`, `created_at`, `action_level`, `updated_by`, and `accepted` in frontmatter.
        """
        try providerBridge.write(to: url.appendingPathComponent(".kuros-wiki/provider-bridge.md"), atomically: true, encoding: .utf8)

        // Claude Code settings.json to register skills
        let settings = """
        {
          "permissions": {
            "allow": ["Read", "Write", "Edit", "Glob", "Grep", "Bash(*)"]
          },
          "hooks": {
            "UserPromptSubmit": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo \\"[Active user: $(cat .claude/active-user 2>/dev/null || echo kuro)] [Active file: $(cat .claude/active-file 2>/dev/null || echo none)]\\"",
                    "timeout": 2000
                  }
                ]
              }
            ]
          }
        }
        """
        try settings.write(to: url.appendingPathComponent(".claude/settings.json"), atomically: true, encoding: .utf8)

        // Copy build.js and style.css into site/
        if let buildJS = kurosWikiBundle.url(forResource: "build", withExtension: "js"),
           let styleCSS = kurosWikiBundle.url(forResource: "style", withExtension: "css") {
            try fm.copyItem(at: buildJS, to: url.appendingPathComponent("site/build.js"))
            try fm.copyItem(at: styleCSS, to: url.appendingPathComponent("site/style.css"))
        }

        // Copy supporting JS files (markdown-it, app.js, graph.js, map.html)
        let supportFiles: [(resource: String, ext: String, dest: String)] = [
            ("markdown-it.min", "js", "site/markdown-it.min.js"),
            ("app", "js", "site/app.js"),
            ("graph", "js", "site/graph.js"),
            ("map", "html", "site/map.html"),
            ("map-3d", "html", "site/map-3d.html"),
        ]
        for file in supportFiles {
            if let source = kurosWikiBundle.url(forResource: file.resource, withExtension: file.ext) {
                try fm.copyItem(at: source, to: url.appendingPathComponent(file.dest))
            }
        }

        // Scaffold version marker — records when this wiki was created so /upgrade
        // can diff against the latest scaffold on GitHub.
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let versionInfo = "created:\(dateFormatter.string(from: Date()))\n"
        try versionInfo.write(to: url.appendingPathComponent(".claude/scaffold-version"), atomically: true, encoding: .utf8)

        // .gitignore for compiled output
        let gitignore = "site/out/\npublish.json\n.rebuild\n.kuros-wiki/ambient-index.md\n.claude/active-user\n.claude/active-file\n"
        try gitignore.write(to: url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    }
}
