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

    func testCompilerExcludesUnacceptedDrafts() throws {
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("drafts"), withIntermediateDirectories: true)
        let draftURL = workspace.appendingPathComponent("drafts/private.md")
        try """
        ---
        title: "Private Draft"
        type: draft
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

    func testCompilerRemovesStaleHtmlWhenDraftBecomesUnaccepted() throws {
        let workspace = temporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("drafts"), withIntermediateDirectories: true)
        let draftURL = workspace.appendingPathComponent("drafts/private.md")
        try """
        ---
        title: "Private Draft"
        type: draft
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
