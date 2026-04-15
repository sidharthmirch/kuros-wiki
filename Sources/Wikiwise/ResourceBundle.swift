import Foundation

// Custom resource bundle accessor that works both in SwiftPM development
// and when packaged as a macOS .app bundle.
//
// SwiftPM's auto-generated Bundle.module checks Bundle.main.bundleURL
// which is the .app root — but code signing requires resources to be
// inside Contents/Resources/. This accessor checks both locations.
private class BundleLocator {}

let wikiwiseBundle: Bundle = {
    let bundleName = "Wikiwise_Wikiwise"
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let testBundleURL = Bundle(for: BundleLocator.self).bundleURL
    let testResourceURL = Bundle(for: BundleLocator.self).resourceURL

    let candidates: [URL] = [
        // Standard .app layout: Contents/Resources/
        Bundle.main.resourceURL,
        // SwiftPM development: adjacent to executable
        Bundle.main.bundleURL,
        // Fallback: same directory as this code's bundle
        testResourceURL,
        testBundleURL,
        // SwiftPM tests put target resource bundles next to the .xctest bundle.
        testResourceURL?.deletingLastPathComponent(),
        testBundleURL.deletingLastPathComponent(),
        // Command-line tests run from the package root.
        currentDirectory.appendingPathComponent(".build/arm64-apple-macosx/debug"),
        currentDirectory.appendingPathComponent(".build/debug"),
    ].compactMap { $0?.appendingPathComponent(bundleName + ".bundle") }

    for candidate in candidates {
        if let bundle = Bundle(path: candidate.path) {
            return bundle
        }
    }

    fatalError("Could not find resource bundle '\(bundleName)' in: \(candidates.map(\.path))")
}()
