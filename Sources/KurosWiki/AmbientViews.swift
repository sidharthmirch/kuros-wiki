import SwiftUI

struct QuickCaptureBox: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    let onCreated: (URL) -> Void
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK CAPTURE")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.sidebarHeader)

            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 58, maxHeight: 78)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.contentBg.opacity(0.75))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.sidebarRule))
                )

            HStack(spacing: 8) {
                Button("Capture") {
                    if let url = workspaceStore.capture(text: text) {
                        text = ""
                        onCreated(url)
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("New Note") {
                    if let url = workspaceStore.createBlankItem(kind: .note) {
                        onCreated(url)
                    }
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct ResearchKindList: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    let onCreated: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WORKSPACE")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.sidebarHeader)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ForEach(ResearchItemKind.sidebarKinds) { kind in
                HStack(spacing: 8) {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sidebarTextMuted)
                        .frame(width: 16)

                    Text(kind.displayName)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(Color.sidebarText)

                    Spacer()

                    Text("\(workspaceStore.items.filter { $0.kind == kind }.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.sidebarTextMuted)

                    Button {
                        if let url = workspaceStore.createBlankItem(kind: kind) {
                            onCreated(url)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.sidebarTextMuted)
                    .help("Create \(kind.singularName)")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 5)
            }
        }
    }
}

struct AmbientRailView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    let selectedFileURL: URL?
    let onOpenFile: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                providerCard
                contextCard
                suggestionsCard
                jobsCard
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var providerCard: some View {
        let status = workspaceStore.providerStatus
        return ambientSection("ACTIVE PROVIDER") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(status.kind.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.infoValue)
                    Spacer()
                    Circle()
                        .fill(status.isAvailable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                }

                Text(status.message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sidebarText)

                Text(status.command.isEmpty ? "No launch command" : status.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.sidebarTextMuted)
                    .textSelection(.enabled)
            }
        }
    }

    private var contextCard: some View {
        ambientSection("CURRENT CONTEXT") {
            VStack(alignment: .leading, spacing: 8) {
                if let selectedFileURL {
                    infoLine("File", selectedFileURL.lastPathComponent)
                    infoLine("Kind", kindLabel(for: selectedFileURL))
                    if let item = workspaceStore.items.first(where: { $0.url == selectedFileURL }) {
                        infoLine("Provider", item.providerID ?? "authored")
                        infoLine("Skill", item.skillName ?? "none")
                    }
                } else {
                    Text("No note selected.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sidebarTextMuted)
                }

                HStack {
                    Button("Maintain") {
                        try? workspaceStore.runMaintenance()
                    }
                    Button("Daily Review") {
                        workspaceStore.createDailyReview()
                    }
                    Button("Close Session") {
                        workspaceStore.closeSession()
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
        }
    }

    private var suggestionsCard: some View {
        ambientSection("SUGGESTIONS") {
            VStack(alignment: .leading, spacing: 10) {
                if workspaceStore.suggestions.isEmpty {
                    Text("Suggestions will appear after captures or file edits.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sidebarTextMuted)
                } else {
                    ForEach(workspaceStore.suggestions.prefix(8)) { suggestion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.infoValue)
                            Text(suggestion.body)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sidebarText)
                                .lineLimit(4)
                            Text("\(suggestion.actionLevel.displayName) · \(suggestion.skillName) · \(suggestion.providerID)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.sidebarTextMuted)
                        }
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.sidebarRule).frame(height: 1)
                        }
                    }

                    Button("Clear Suggestions") {
                        workspaceStore.clearSuggestions()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
            }
        }
    }

    private var jobsCard: some View {
        ambientSection("BACKGROUND JOBS") {
            VStack(alignment: .leading, spacing: 8) {
                if workspaceStore.jobs.isEmpty {
                    Text("No ambient jobs yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sidebarTextMuted)
                } else {
                    ForEach(workspaceStore.jobs.prefix(8)) { job in
                        Button {
                            if let url = jobOutputURL(for: job) {
                                onOpenFile(url)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.infoValue)
                                    .lineLimit(2)
                                Text("\(job.actionLevel.displayName) · \(job.skillName) · \(job.providerID)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color.sidebarTextMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ambientSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("JetBrains Mono", size: 9))
                .tracking(1.6)
                .foregroundStyle(Color.sidebarHeader)
            content()
        }
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.sidebarHeader)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Color.infoValue)
                .lineLimit(1)
        }
    }

    private func kindLabel(for url: URL) -> String {
        workspaceStore.items.first(where: { $0.url == url })?.kind.displayName ?? "File"
    }

    private func jobOutputURL(for job: AmbientJob) -> URL? {
        guard let root = workspaceStore.rootURL,
              let outputPath = job.outputPath,
              !outputPath.hasPrefix("/") else { return nil }

        let components = outputPath.split(separator: "/").map(String.init)
        guard !components.contains("..") else { return nil }

        let candidate = root.appendingPathComponent(outputPath).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else { return nil }
        return candidate
    }
}

struct ProviderSettingsView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @State private var newProfileID = ""

    var body: some View {
        Form {
            Section("Profiles") {
                Picker("Active profile", selection: Binding(
                    get: { workspaceStore.activeProfileID },
                    set: { profileID in
                        workspaceStore.switchProfile(to: profileID)
                    }
                )) {
                    ForEach(workspaceStore.profiles) { profile in
                        Text(profile.id).tag(profile.id)
                    }
                }

                HStack {
                    TextField("New profile ID", text: $newProfileID)

                    Button("Add") {
                        if workspaceStore.addProfile(id: newProfileID) {
                            newProfileID = ""
                        }
                    }
                    .disabled(!canAddProfile)
                }

                Text("Profiles are stored per workspace and written to `.claude/active-user`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Provider") {
                Picker("Active provider", selection: Binding(
                    get: { workspaceStore.settings.activeProvider },
                    set: { provider in
                        workspaceStore.updateSettings { $0.activeProvider = provider }
                    }
                )) {
                    ForEach(AIProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                if workspaceStore.settings.activeProvider == .custom {
                    TextField("Command", text: Binding(
                        get: { workspaceStore.settings.customProviderCommand },
                        set: { command in
                            workspaceStore.updateSettings { $0.customProviderCommand = command }
                        }
                    ))
                }

                Text(workspaceStore.settings.activeProvider.bridgeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ambient Behavior") {
                Picker("Intensity", selection: Binding(
                    get: { workspaceStore.settings.ambientIntensity },
                    set: { intensity in
                        workspaceStore.updateSettings { $0.ambientIntensity = intensity }
                    }
                )) {
                    ForEach(AmbientIntensity.allCases) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }

                Picker("Default action", selection: Binding(
                    get: { workspaceStore.settings.defaultActionLevel },
                    set: { level in
                        workspaceStore.updateSettings { $0.defaultActionLevel = level }
                    }
                )) {
                    ForEach(AmbientActionLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }

                Toggle("Background processing", isOn: Binding(
                    get: { workspaceStore.settings.backgroundProcessingEnabled },
                    set: { enabled in
                        workspaceStore.updateSettings { $0.backgroundProcessingEnabled = enabled }
                    }
                ))

                Toggle("Show provenance", isOn: Binding(
                    get: { workspaceStore.settings.showProvenance },
                    set: { visible in
                        workspaceStore.updateSettings { $0.showProvenance = visible }
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.sidebarBg)
    }

    private var canAddProfile: Bool {
        let id = newProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceStore.isValidProfileID(id) && !workspaceStore.profiles.contains(where: { $0.id == id })
    }
}
