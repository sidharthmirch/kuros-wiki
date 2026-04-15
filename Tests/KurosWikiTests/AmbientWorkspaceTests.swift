import Foundation
import XCTest
@testable import KurosWiki

final class AmbientWorkspaceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testScaffoldCreatesAmbientWorkspaceStateAndSkills() throws {
        let workspace = temporaryDirectory().appendingPathComponent("Research")

        try WikiScaffold.create(at: workspace, name: "Research")

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".kuros-wiki/workspace.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".kuros-wiki/provider-bridge.md").path))
        XCTAssertEqual(
            try String(contentsOf: workspace.appendingPathComponent(".claude/active-user"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "kuro"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/capture-source/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".claude/skills/capture-source/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/whoami/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".claude/skills/whoami/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/import-readwise/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".claude/skills/import-readwise/SKILL.md").path))
        let settings = try String(contentsOf: workspace.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
        XCTAssertTrue(settings.contains("active-user"))
        XCTAssertTrue(settings.contains("active-file"))
        let gitignore = try String(contentsOf: workspace.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(gitignore.contains(".kuros-wiki/ambient-index.md"))
        XCTAssertTrue(gitignore.contains(".claude/active-user"))
        XCTAssertTrue(gitignore.contains(".claude/active-file"))
    }

    @MainActor
    func testWorkspaceStoreBootstrapsAndCapturesAmbientItems() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()

        store.open(rootURL: workspace)
        let capturedURL = store.capture(text: "https://example.com/research", as: .inbox)

        let stateURL = workspace.appendingPathComponent(".kuros-wiki/workspace.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(
            try String(contentsOf: workspace.appendingPathComponent(".claude/active-user"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "kuro"
        )
        XCTAssertEqual(capturedURL?.deletingLastPathComponent().lastPathComponent, "sources")
        XCTAssertTrue(store.items.contains { $0.kind == .source && $0.title == "example.com" })
        XCTAssertTrue(
            store.suggestions.contains { $0.skillName == AmbientSkillName.captureSource.rawValue },
            "suggestions: \(store.suggestions.map(\.skillName))"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/capture-source/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/import-readwise/SKILL.md").path))
        let capturedContent = try String(contentsOf: XCTUnwrap(capturedURL), encoding: .utf8)
        XCTAssertTrue(capturedContent.contains("action_level: suggest"))
        XCTAssertTrue(capturedContent.contains("updated_by: kuro"))
    }

    @MainActor
    func testWorkspaceStoreCloseWorkspaceClearsOpenState() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()

        store.open(rootURL: workspace)
        _ = store.capture(text: "# Close Me", as: .note)
        try store.runMaintenance()

        store.closeWorkspace()

        XCTAssertNil(store.rootURL)
        XCTAssertEqual(store.items, [])
        XCTAssertEqual(store.suggestions, [])
        XCTAssertEqual(store.jobs, [])
        XCTAssertEqual(store.profiles, [WorkspaceProfile(id: WorkspaceProfile.defaultID)])
        XCTAssertEqual(store.activeProfileID, WorkspaceProfile.defaultID)
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testWorkspaceStoreInheritsExistingActiveUser() throws {
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try "vidur\n".write(to: workspace.appendingPathComponent(".claude/active-user"), atomically: true, encoding: .utf8)
        let store = WorkspaceStore()

        store.open(rootURL: workspace)

        XCTAssertEqual(store.activeProfileID, "vidur")
        XCTAssertTrue(store.profiles.contains(WorkspaceProfile(id: "vidur")))
        let state = try readWorkspaceState(from: workspace)
        XCTAssertEqual(state.activeProfileID, "vidur")
        XCTAssertTrue(state.profiles.contains(WorkspaceProfile(id: "vidur")))
    }

    @MainActor
    func testSwitchingProfileWritesActiveUserFile() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()

        store.open(rootURL: workspace)
        XCTAssertTrue(store.addProfile(id: "vidur"))
        store.switchProfile(to: "vidur")

        let activeUser = try String(contentsOf: workspace.appendingPathComponent(".claude/active-user"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(activeUser, "vidur")
        XCTAssertEqual(store.activeProfileID, "vidur")
        XCTAssertEqual(try readWorkspaceState(from: workspace).activeProfileID, "vidur")
    }

    @MainActor
    func testAddingProfilesPersistsWithoutSwitching() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()

        store.open(rootURL: workspace)
        XCTAssertTrue(store.addProfile(id: "sidharth"))
        XCTAssertTrue(store.addProfile(id: "vidur"))

        XCTAssertEqual(store.activeProfileID, "kuro")
        let state = try readWorkspaceState(from: workspace)
        XCTAssertEqual(state.profiles.map(\.id), ["kuro", "sidharth", "vidur"])
        XCTAssertEqual(state.activeProfileID, "kuro")
    }

    @MainActor
    func testInvalidProfileIDsAreRejected() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()

        store.open(rootURL: workspace)
        for id in ["Kuro!", "", "   "] {
            XCTAssertFalse(store.addProfile(id: id), "expected rejection for \(id)")
        }

        XCTAssertEqual(store.profiles, [WorkspaceProfile(id: "kuro")])
        XCTAssertEqual(store.activeProfileID, "kuro")
        XCTAssertEqual(store.lastError, "Profile IDs must start with a lowercase letter or number and use only lowercase letters, numbers, hyphens, or underscores.")
        let activeUser = try String(contentsOf: workspace.appendingPathComponent(".claude/active-user"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(activeUser, "kuro")
    }

    @MainActor
    func testWorkspaceStoreMigratesLegacyWorkspaceState() throws {
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent(".wikiwise"), withIntermediateDirectories: true)
        let legacyStateURL = workspace.appendingPathComponent(".wikiwise/workspace.json")
        let legacyState = WorkspaceState(
            schemaVersion: 1,
            activeProfileID: "vidur",
            profiles: [WorkspaceProfile(id: "vidur")],
            settings: .default,
            suggestions: [],
            jobs: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacyState).write(to: legacyStateURL)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try "vidur\n".write(to: workspace.appendingPathComponent(".claude/active-user"), atomically: true, encoding: .utf8)
        let store = WorkspaceStore()

        store.open(rootURL: workspace)

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".kuros-wiki/workspace.json").path))
        XCTAssertEqual(store.activeProfileID, "vidur")
        XCTAssertTrue(store.profiles.contains(WorkspaceProfile(id: "vidur")))
    }

    @MainActor
    func testAmbientMaintenanceWritesIndex() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()

        store.open(rootURL: workspace)
        _ = store.capture(text: "# Thread Note\n\nConnect this.", as: .note)
        try store.runMaintenance()

        let indexURL = workspace.appendingPathComponent(".kuros-wiki/ambient-index.md")
        let index = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(index.contains("generated_by: kuros-wiki"))
        XCTAssertTrue(index.contains("## Notes"))
    }

    func testCompilerUsesPathScopedSlugsForAmbientFolders() throws {
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("wiki"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try "# Alpha Wiki\n".write(to: workspace.appendingPathComponent("wiki/alpha.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: "Alpha Note"
        type: note
        accepted: true
        ---

        # Alpha Note
        """.write(to: workspace.appendingPathComponent("notes/alpha.md"), atomically: true, encoding: .utf8)

        let compiler = Compiler(sourceDir: workspace)
        compiler.scanPages()

        XCTAssertTrue(compiler.compileSingle(slug: "alpha"))
        XCTAssertTrue(compiler.compileSingle(slug: "notes++alpha"))
        let wikiHTML = try String(contentsOf: compiler.outputDir.appendingPathComponent("alpha.html"), encoding: .utf8)
        let noteHTML = try String(contentsOf: compiler.outputDir.appendingPathComponent("notes++alpha.html"), encoding: .utf8)
        XCTAssertTrue(wikiHTML.contains("Alpha Wiki"))
        XCTAssertTrue(noteHTML.contains("Alpha Note"))
    }

    func testCompilerDoesNotCollapsePathSeparatorSlugs() throws {
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("notes/foo"), withIntermediateDirectories: true)
        try "# Hyphen\n".write(to: workspace.appendingPathComponent("notes/foo-bar.md"), atomically: true, encoding: .utf8)
        try "# Double Hyphen\n".write(to: workspace.appendingPathComponent("notes/foo--bar.md"), atomically: true, encoding: .utf8)
        try "# Nested\n".write(to: workspace.appendingPathComponent("notes/foo/bar.md"), atomically: true, encoding: .utf8)
        try "# Space\n".write(to: workspace.appendingPathComponent("notes/foo bar.md"), atomically: true, encoding: .utf8)

        let compiler = Compiler(sourceDir: workspace)
        compiler.scanPages()

        XCTAssertTrue(compiler.compileSingle(slug: "notes++foo-bar"))
        XCTAssertTrue(compiler.compileSingle(slug: "notes++foo--bar"))
        XCTAssertTrue(compiler.compileSingle(slug: "notes++foo++bar"))
        XCTAssertTrue(compiler.compileSingle(slug: "notes++foo%20bar"))
        let hyphenHTML = try String(contentsOf: compiler.outputDir.appendingPathComponent("notes++foo-bar.html"), encoding: .utf8)
        let doubleHyphenHTML = try String(contentsOf: compiler.outputDir.appendingPathComponent("notes++foo--bar.html"), encoding: .utf8)
        let nestedHTML = try String(contentsOf: compiler.outputDir.appendingPathComponent("notes++foo++bar.html"), encoding: .utf8)
        let spaceHTML = try String(contentsOf: compiler.outputDir.appendingPathComponent("notes++foo%20bar.html"), encoding: .utf8)
        XCTAssertTrue(hyphenHTML.contains("Hyphen"))
        XCTAssertTrue(doubleHyphenHTML.contains("Double Hyphen"))
        XCTAssertTrue(nestedHTML.contains("Nested"))
        XCTAssertTrue(spaceHTML.contains("Space"))
    }

    func testCompilerExcludesUnacceptedGeneratedDrafts() throws {
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("drafts"), withIntermediateDirectories: true)
        let draftURL = workspace.appendingPathComponent("drafts/private.md")
        try """
        ---
        title: "Private Draft"
        type: draft
        provider: gemini
        accepted: false
        ---

        # Private Draft
        """.write(to: draftURL, atomically: true, encoding: .utf8)

        let compiler = Compiler(sourceDir: workspace)
        compiler.scanPages()

        XCTAssertFalse(compiler.compileSingle(slug: "drafts++private"))
        XCTAssertFalse(compiler.compileAdhoc(
            filePath: draftURL.path,
            outputPath: compiler.outputDir.appendingPathComponent("drafts++private.html").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: compiler.outputDir.appendingPathComponent("drafts++private.html").path))
    }

    func testCompilerRendersUnacceptedDraftWithoutProvider() throws {
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("notes"), withIntermediateDirectories: true)
        let noteURL = workspace.appendingPathComponent("notes/source-note.md")
        try """
        ---
        title: "Source Note"
        type: claim
        status: active
        accepted: false
        source: "[[sources/442-warmup-summary.md]]"
        ---

        # Source Note

        Content here.
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        let compiler = Compiler(sourceDir: workspace)
        compiler.scanPages()

        XCTAssertTrue(compiler.compileSingle(slug: "notes++source-note"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: compiler.outputDir.appendingPathComponent("notes++source-note.html").path))
    }

    func testCompilerRemovesStaleHtmlWhenDraftBecomesUnaccepted() throws {
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("drafts"), withIntermediateDirectories: true)
        let draftURL = workspace.appendingPathComponent("drafts/private.md")
        try """
        ---
        title: "Private Draft"
        type: draft
        provider: gemini
        accepted: true
        ---

        # Private Draft

        secret
        """.write(to: draftURL, atomically: true, encoding: .utf8)

        let compiler = Compiler(sourceDir: workspace)
        compiler.scanPages()
        XCTAssertTrue(compiler.compileSingle(slug: "drafts++private"))
        let htmlURL = compiler.outputDir.appendingPathComponent("drafts++private.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: htmlURL.path))

        try """
        ---
        title: "Private Draft"
        type: draft
        provider: gemini
        accepted: false
        ---

        # Private Draft

        secret
        """.write(to: draftURL, atomically: true, encoding: .utf8)
        compiler.rescan()

        XCTAssertFalse(FileManager.default.fileExists(atPath: htmlURL.path))
    }

    @MainActor
    func testDailyReviewCreatesUniqueDraftsAndPathScopedLinks() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()

        store.open(rootURL: workspace)
        _ = store.createBlankItem(kind: .question)
        store.createDailyReview()
        store.createDailyReview()

        let drafts = try FileManager.default.contentsOfDirectory(
            at: workspace.appendingPathComponent("drafts"),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("daily-review-") }
        XCTAssertEqual(drafts.count, 2)
        let draftTexts = try drafts.map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertTrue(
            draftTexts.contains { $0.contains("[[questions++untitled-question]]") },
            draftTexts.joined(separator: "\n---\n")
        )
    }

    @MainActor
    func testQueueAcceptsReadableRegularFile() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        let importDir = workspace.appendingPathComponent("imports")
        try FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)
        let fileURL = importDir.appendingPathComponent("source.pdf")
        try Data("hello".utf8).write(to: fileURL)

        let added = store.queueAmbientUploads(from: fileURL.path)

        XCTAssertEqual(added, 1)
        XCTAssertEqual(store.ambientUploadQueue.count, 1)
        XCTAssertEqual(store.ambientUploadQueue[0].status, .queued)
        XCTAssertEqual(store.ambientUploadQueue[0].sourceKind, .localFile)
    }

    @MainActor
    func testQueueRejectsMissingUploadPath() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        let missingURL = workspace.appendingPathComponent("imports/missing.pdf")
        let added = store.queueAmbientUploads(from: missingURL.path)

        XCTAssertEqual(added, 1)
        XCTAssertEqual(store.ambientUploadQueue.count, 1)
        XCTAssertEqual(store.ambientUploadQueue[0].status, .failed)
        XCTAssertEqual(store.ambientUploadQueue[0].error, "File does not exist.")
    }

    @MainActor
    func testCopyQueuedUploadCreatesRawFile() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        let source = workspace.appendingPathComponent("imports/paper.pdf")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("paper".utf8).write(to: source)

        _ = store.queueAmbientUploads(from: source.path)
        XCTAssertEqual(store.copyQueuedAmbientFilesToRaw(), 1)
        XCTAssertEqual(store.ambientUploadQueue[0].status, .copiedToRaw)
        XCTAssertEqual(store.ambientUploadQueue[0].rawRelativePath, "raw/paper.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("raw/paper.pdf").path))
    }

    @MainActor
    func testCopyQueuedUploadCreatesUniqueDestination() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        let rawDir = workspace.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
        let alreadyInRaw = rawDir.appendingPathComponent("already.md")
        try Data("inside raw".utf8).write(to: alreadyInRaw)

        let importA = workspace.appendingPathComponent("imports/a")
        let importB = workspace.appendingPathComponent("imports/b")
        try FileManager.default.createDirectory(at: importA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: importB, withIntermediateDirectories: true)
        let reportA = importA.appendingPathComponent("report.pdf")
        let reportB = importB.appendingPathComponent("report.pdf")
        try Data("A".utf8).write(to: reportA)
        try Data("B".utf8).write(to: reportB)

        _ = store.queueAmbientUploads(from: "\(alreadyInRaw.path)\n\(reportA.path)\n\(reportB.path)")
        let copied = store.copyQueuedAmbientFilesToRaw()

        XCTAssertEqual(copied, 3)
        XCTAssertEqual(store.ambientUploadQueue.count, 3)
        XCTAssertEqual(store.ambientUploadQueue[0].status, .alreadyInRaw)
        XCTAssertEqual(store.ambientUploadQueue[0].rawRelativePath, "raw/already.md")
        XCTAssertEqual(store.ambientUploadQueue[1].status, .copiedToRaw)
        XCTAssertEqual(store.ambientUploadQueue[2].status, .copiedToRaw)

        let rawContents = try FileManager.default.contentsOfDirectory(atPath: rawDir.path)
        XCTAssertTrue(rawContents.contains("already.md"))
        XCTAssertTrue(rawContents.contains("report.pdf"))
        XCTAssertTrue(rawContents.contains("report-2.pdf"))
    }

    @MainActor
    func testIngestCommandUsesRawRelativePaths() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        XCTAssertEqual(store.terminalAgentState.phase, .configured)
        XCTAssertFalse(store.terminalAgentState.isActive)

        let importFile = workspace.appendingPathComponent("imports/ingest.md")
        try FileManager.default.createDirectory(at: importFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("ingest me".utf8).write(to: importFile)

        _ = store.queueAmbientUploads(from: importFile.path)
        XCTAssertEqual(store.copyQueuedAmbientFilesToRaw(), 1)
        XCTAssertNil(store.ingestQueuedAmbientItemsWithProvider())
        XCTAssertEqual(store.ambientUploadQueue[0].status, .copiedToRaw)
        XCTAssertEqual(store.ambientNotifications.first?.level, .warning)

        store.setTerminalAgentActive()
        let command = store.ingestQueuedAmbientItemsWithProvider()

        XCTAssertEqual(
            command,
            "Use the ingest skill on raw/ingest.md. Summarize it into the wiki, update relevant pages, and append provenance."
        )
        XCTAssertEqual(store.ambientUploadQueue[0].status, .ingestSent)
        XCTAssertNotNil(store.ambientUploadQueue[0].sentAt)
    }

    @MainActor
    func testIngestCommandAutoCopiesQueuedFilesToRaw() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        store.setTerminalAgentActive()

        let importFile = workspace.appendingPathComponent("imports/queued.md")
        try FileManager.default.createDirectory(at: importFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("queued".utf8).write(to: importFile)
        _ = store.queueAmbientUploads(from: importFile.path)

        let command = store.ingestQueuedAmbientItemsWithProvider()

        XCTAssertEqual(
            command,
            "Use the ingest skill on raw/queued.md. Summarize it into the wiki, update relevant pages, and append provenance."
        )
        XCTAssertEqual(store.ambientUploadQueue[0].status, .ingestSent)
        XCTAssertEqual(store.ambientUploadQueue[0].rawRelativePath, "raw/queued.md")
    }

    @MainActor
    func testIngestCommandCanBePreparedAgainForPreviouslySentItem() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        store.setTerminalAgentActive()

        let source = workspace.appendingPathComponent("imports/retry.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("retry".utf8).write(to: source)

        _ = store.queueAmbientUploads(from: source.path)
        XCTAssertEqual(store.copyQueuedAmbientFilesToRaw(), 1)
        XCTAssertNotNil(store.ingestQueuedAmbientItemsWithProvider())
        XCTAssertEqual(store.ambientUploadQueue[0].status, .ingestSent)

        let secondCommand = store.ingestQueuedAmbientItemsWithProvider()
        XCTAssertEqual(
            secondCommand,
            "Use the ingest skill on raw/retry.md. Summarize it into the wiki, update relevant pages, and append provenance."
        )
    }

    @MainActor
    func testAmbientNotificationsTrimToLatestEight() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        for index in 0..<10 {
            _ = store.queueAmbientUploads(from: "missing-\(index).md")
        }

        XCTAssertEqual(store.ambientNotifications.count, 8)
        let newest = try XCTUnwrap(store.ambientNotifications.first)
        let oldest = try XCTUnwrap(store.ambientNotifications.last)
        XCTAssertGreaterThanOrEqual(newest.createdAt, oldest.createdAt)
    }

    @MainActor
    func testProviderStatusDoesNotMeanActiveWithoutTerminalLaunch() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }

        XCTAssertEqual(store.terminalAgentState.phase, .configured)
        XCTAssertFalse(store.terminalAgentState.isActive)
    }

    @MainActor
    func testTerminalOutputParserStripsAnsi() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        store.setTerminalAgentActive()

        store.terminalIngestOutput(lines: ["\u{001B}[31moperation success\u{001B}[0m"])

        XCTAssertEqual(store.ambientNotifications.first?.level, .success)
        XCTAssertEqual(store.ambientNotifications.first?.message, "operation success")
    }

    @MainActor
    func testTerminalOutputParserIgnoresPromptNoise() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        store.setTerminalAgentActive()
        let before = store.ambientNotifications.count

        store.terminalIngestOutput(lines: ["$", "sidharth@mac %", "   "])

        XCTAssertEqual(store.ambientNotifications.count, before)
    }

    @MainActor
    func testTerminalOutputParserIgnoresPromptWithTypedCommand() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        store.setTerminalAgentActive()
        let before = store.ambientNotifications.count

        store.terminalIngestOutput(lines: ["sidharth@sudu 77on4 % ccodex"])

        XCTAssertEqual(store.ambientNotifications.count, before)
    }

    @MainActor
    func testTerminalOutputParserDemotesActiveWhenShellPromptReturns() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        store.setTerminalAgentActive()

        store.terminalIngestOutput(lines: ["sidharth@sudu 77on4 %"])

        XCTAssertEqual(store.terminalAgentState.phase, .configured)
        XCTAssertFalse(store.terminalAgentState.isActive)
    }

    @MainActor
    func testTerminalOutputParserIgnoresProviderUiChromeLine() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        store.setTerminalAgentActive()
        let before = store.ambientNotifications.count

        store.terminalIngestOutput(lines: ["breakdown.BooBootBootiBootinBooting \u{203A} Summarize recent commits gpt-5.3-codex high \u{203A} / /model choose what model and reasoning effort"])

        XCTAssertEqual(store.ambientNotifications.count, before)
    }

    @MainActor
    func testTerminalResetBridgeStateClearsAmbientNotifications() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        _ = store.queueAmbientUploads(from: "missing.md")
        XCTAssertFalse(store.ambientNotifications.isEmpty)

        store.terminalResetBridgeState()

        XCTAssertTrue(store.ambientNotifications.isEmpty)
    }

    @MainActor
    func testRemoveAmbientNotificationDeletesSingleEntry() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)

        _ = store.queueAmbientUploads(from: "missing-a.md")
        _ = store.queueAmbientUploads(from: "missing-b.md")
        XCTAssertGreaterThanOrEqual(store.ambientNotifications.count, 2)
        let toRemove = try XCTUnwrap(store.ambientNotifications.first?.id)

        store.removeAmbientNotification(id: toRemove)

        XCTAssertFalse(store.ambientNotifications.contains(where: { $0.id == toRemove }))
    }

    @MainActor
    func testTerminalOutputParserClassifiesErrorLine() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        store.setTerminalAgentActive()

        store.terminalIngestOutput(lines: ["task failed with exception"])

        XCTAssertEqual(store.ambientNotifications.first?.level, .error)
        XCTAssertEqual(store.ambientNotifications.first?.message, "task failed with exception")
    }

    @MainActor
    func testGeminiProviderDetection() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .gemini
            $0.customProviderCommand = "/bin/echo"
        }
        XCTAssertEqual(store.terminalAgentState.phase, .configured,
                       "gemini is on PATH so should start as configured")
        store.setTerminalAgentLaunching(command: "gemini")
        XCTAssertEqual(store.terminalAgentState.phase, .launching)
        store.terminalIngestOutput(lines: ["Gemini is ready"])
        XCTAssertTrue(store.terminalAgentState.isActive,
                      "Gemini activation hint should promote to active from launching")
    }

    @MainActor
    func testOpencodeProviderDetection() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .opencode
        }
        store.setTerminalAgentLaunching(command: "opencode")
        store.terminalIngestOutput(lines: ["opencode session started"])

        XCTAssertEqual(store.terminalAgentState.phase, .active)
    }

    @MainActor
    func testSoulforgeProviderDetection() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .soulforge
        }
        store.setTerminalAgentLaunching(command: "soulforge --headless")
        store.terminalIngestOutput(lines: ["SoulForge agent connected"])

        XCTAssertEqual(store.terminalAgentState.phase, .active)
    }

    @MainActor
    func testHermesProviderActivityDetection() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()
        store.open(rootURL: workspace)
        store.updateSettings {
            $0.activeProvider = .custom
            $0.customProviderCommand = "/bin/echo"
        }
        store.setTerminalAgentActive()

        store.terminalIngestOutput(lines: ["hermes bridge active"])

        XCTAssertTrue(store.terminalAgentState.isActive,
                      "active custom provider stays active after hermes-keyword output")
    }

    @MainActor
    func testNewProvidersHaveDefaultCommands() {
        XCTAssertFalse(AIProviderKind.gemini.defaultCommand.isEmpty)
        XCTAssertFalse(AIProviderKind.opencode.defaultCommand.isEmpty)
        XCTAssertFalse(AIProviderKind.soulforge.defaultCommand.isEmpty)
        XCTAssertFalse(AIProviderKind.hermes.defaultCommand.isEmpty)
    }

    @MainActor
    func testNewProvidersHaveDisplayNames() {
        XCTAssertEqual(AIProviderKind.gemini.displayName, "Gemini")
        XCTAssertEqual(AIProviderKind.opencode.displayName, "OpenCode")
        XCTAssertEqual(AIProviderKind.soulforge.displayName, "SoulForge")
        XCTAssertEqual(AIProviderKind.hermes.displayName, "Hermes")
    }

    @MainActor
    func testNewProvidersSkillBridgePaths() {
        let root = temporaryDirectory()
        let codexPaths = ShellAIProviderAdapter(kind: .codex).skillBridgePaths(in: root)
        let geminiPaths = ShellAIProviderAdapter(kind: .gemini).skillBridgePaths(in: root)
        let opencodePaths = ShellAIProviderAdapter(kind: .opencode).skillBridgePaths(in: root)
        let soulforgePaths = ShellAIProviderAdapter(kind: .soulforge).skillBridgePaths(in: root)
        let hermesPaths = ShellAIProviderAdapter(kind: .hermes).skillBridgePaths(in: root)

        XCTAssertTrue(geminiPaths.contains(where: { $0.lastPathComponent == "GEMINI.md" }))
        XCTAssertTrue(opencodePaths.contains(where: { $0.lastPathComponent == ".opencode" }))
        XCTAssertTrue(soulforgePaths.contains(where: { $0.lastPathComponent == "AGENTS.md" }))
        XCTAssertTrue(hermesPaths.contains(where: { $0.lastPathComponent == ".hermes" }))

        XCTAssertEqual(codexPaths, soulforgePaths, "soulforge should share AGENTS.md bridge with codex")
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuros-wiki-tests")
            .appendingPathComponent(UUID().uuidString)
        temporaryDirectories.append(url)
        return url
    }

    private func readWorkspaceState(from workspace: URL) throws -> WorkspaceState {
        let data = try Data(contentsOf: workspace.appendingPathComponent(".kuros-wiki/workspace.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkspaceState.self, from: data)
    }
}
