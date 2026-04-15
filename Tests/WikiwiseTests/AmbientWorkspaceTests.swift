import Foundation
import XCTest
@testable import Wikiwise

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

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".wikiwise/workspace.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".wikiwise/provider-bridge.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/capture-source/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".claude/skills/capture-source/SKILL.md").path))
        let gitignore = try String(contentsOf: workspace.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(gitignore.contains(".wikiwise/ambient-index.md"))
    }

    @MainActor
    func testWorkspaceStoreBootstrapsAndCapturesAmbientItems() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()

        store.open(rootURL: workspace)
        let capturedURL = store.capture(text: "https://example.com/research", as: .inbox)

        let stateURL = workspace.appendingPathComponent(".wikiwise/workspace.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(capturedURL?.deletingLastPathComponent().lastPathComponent, "sources")
        XCTAssertTrue(store.items.contains { $0.kind == .source && $0.title == "example.com" })
        XCTAssertTrue(
            store.suggestions.contains { $0.skillName == AmbientSkillName.captureSource.rawValue },
            "suggestions: \(store.suggestions.map(\.skillName))"
        )
        let capturedContent = try String(contentsOf: XCTUnwrap(capturedURL), encoding: .utf8)
        XCTAssertTrue(capturedContent.contains("action_level: suggest"))
    }

    @MainActor
    func testAmbientMaintenanceWritesIndex() throws {
        let workspace = temporaryDirectory()
        let store = WorkspaceStore()

        store.open(rootURL: workspace)
        _ = store.capture(text: "# Thread Note\n\nConnect this.", as: .note)
        try store.runMaintenance()

        let indexURL = workspace.appendingPathComponent(".wikiwise/ambient-index.md")
        let index = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(index.contains("generated_by: wikiwise"))
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
            .appendingPathComponent("wikiwise-tests")
            .appendingPathComponent(UUID().uuidString)
        temporaryDirectories.append(url)
        return url
    }
}
