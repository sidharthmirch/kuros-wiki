import Foundation
import XCTest
@testable import KurosWiki

final class VaultRecentsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "VaultRecentsStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testRecordStoresNewPath() {
        let store = VaultRecentsStore(defaults: defaults)

        store.record(path: "/tmp/wiki")

        XCTAssertEqual(store.load(), ["/tmp/wiki"])
    }

    func testRecordMovesExistingPathToTop() {
        let store = VaultRecentsStore(defaults: defaults)

        store.record(path: "/tmp/first")
        store.record(path: "/tmp/second")
        store.record(path: "/tmp/first")

        XCTAssertEqual(store.load(), ["/tmp/first", "/tmp/second"])
    }

    func testRecordCapsRecentPathsAtTen() {
        let store = VaultRecentsStore(defaults: defaults)

        for index in 0..<12 {
            store.record(path: "/tmp/wiki-\(index)")
        }

        XCTAssertEqual(store.load().count, 10)
        XCTAssertEqual(store.load().first, "/tmp/wiki-11")
        XCTAssertEqual(store.load().last, "/tmp/wiki-2")
    }

    func testClearRemovesPersistedPaths() {
        let store = VaultRecentsStore(defaults: defaults)

        store.record(path: "/tmp/wiki")
        store.clear()

        XCTAssertEqual(store.load(), [])
    }

    func testInvalidPersistedDataReturnsEmptyList() {
        defaults.set(Data("not-json".utf8), forKey: VaultRecentsStore.storageKey)
        let store = VaultRecentsStore(defaults: defaults)

        XCTAssertEqual(store.load(), [])
    }

    func testEmptyPathIsIgnored() {
        let store = VaultRecentsStore(defaults: defaults)

        store.record(path: "   ")

        XCTAssertEqual(store.load(), [])
    }
}
