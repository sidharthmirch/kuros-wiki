import SwiftUI
import AppKit

extension Notification.Name {
    static let openFolder = Notification.Name("openFolder")
    static let openVault = Notification.Name("openVault")
    static let openRecentVault = Notification.Name("openRecentVault")
    static let showWelcomeScreen = Notification.Name("showWelcomeScreen")
    static let showGettingStartedGuide = Notification.Name("showGettingStartedGuide")
    static let vaultRecentsDidChange = Notification.Name("vaultRecentsDidChange")
    static let goBack = Notification.Name("goBack")
    static let goForward = Notification.Name("goForward")
    static let refreshWiki = Notification.Name("refreshWiki")
}

final class VaultRecentsMenuState: ObservableObject {
    @Published private(set) var recentVaultPaths: [String]

    private let store: VaultRecentsStore
    private var observer: NSObjectProtocol?

    init(store: VaultRecentsStore = VaultRecentsStore()) {
        self.store = store
        self.recentVaultPaths = store.load()
        self.observer = NotificationCenter.default.addObserver(
            forName: .vaultRecentsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func clear() {
        store.clear()
        reload()
        NotificationCenter.default.post(name: .vaultRecentsDidChange, object: nil)
    }

    private func reload() {
        recentVaultPaths = store.load()
    }
}

struct KurosWikiCommands: Commands {
    @ObservedObject var vaultRecentsMenuState: VaultRecentsMenuState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Vault…") {
                NotificationCenter.default.post(name: .openVault, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent Vault") {
                if vaultRecentsMenuState.recentVaultPaths.isEmpty {
                    Button("No Recent Vaults") {}
                        .disabled(true)
                } else {
                    ForEach(vaultRecentsMenuState.recentVaultPaths, id: \.self) { path in
                        Button(path) {
                            NotificationCenter.default.post(name: .openRecentVault, object: path)
                        }
                    }

                    Divider()

                    Button("Clear Recent Vaults") {
                        vaultRecentsMenuState.clear()
                    }
                }
            }

            Divider()

            Button("Show Welcome Screen") {
                NotificationCenter.default.post(name: .showWelcomeScreen, object: nil)
            }

            Button("Show Getting Started Guide") {
                NotificationCenter.default.post(name: .showGettingStartedGuide, object: nil)
            }

            Divider()

            Button("Go Back") {
                NotificationCenter.default.post(name: .goBack, object: nil)
            }
            .keyboardShortcut("[", modifiers: .command)

            Button("Go Forward") {
                NotificationCenter.default.post(name: .goForward, object: nil)
            }
            .keyboardShortcut("]", modifiers: .command)

            Divider()

            Button("Refresh Page") {
                NotificationCenter.default.post(name: .refreshWiki, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"

    var nsAppearance: NSAppearance? {
        switch self {
        case .auto:  return nil              // follow system
        case .light: return NSAppearance(named: .aqua)
        case .dark:  return NSAppearance(named: .darkAqua)
        }
    }
}

@main
struct KurosWikiApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.auto.rawValue
    @StateObject private var vaultRecentsMenuState = VaultRecentsMenuState()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let mode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "Auto") ?? .auto
        NSApplication.shared.appearance = mode.nsAppearance

        // Set app icon from bundled .icns
        if let icnsURL = kurosWikiBundle.url(forResource: "KurosWiki", withExtension: "icns"),
           let icon = NSImage(contentsOf: icnsURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: appearanceMode) { _, newValue in
                    let mode = AppearanceMode(rawValue: newValue) ?? .auto
                    NSApplication.shared.appearance = mode.nsAppearance
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1500, height: 1000)
        .commands {
            KurosWikiCommands(vaultRecentsMenuState: vaultRecentsMenuState)
        }
    }
}
