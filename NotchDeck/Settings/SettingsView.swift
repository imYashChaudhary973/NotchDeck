import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLoginService
    let calendar: CalendarProvider
    let clipboard: ClipboardProvider

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.status == .requiresApproval {
                    LabeledContent {
                        Button("Open Login Items…", action: launchAtLogin.openLoginItemsSettings)
                    } label: {
                        Text("Approval needed in System Settings")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker("Display", selection: $settings.displayPreference) {
                    ForEach(DisplayPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                Toggle("Peek when the pointer hovers over the notch", isOn: $settings.peeksOnHover)
                Toggle("Collapse when the pointer leaves", isOn: $settings.collapsesWhenPointerExits)
                Toggle("Peek automatically when something needs attention", isOn: $settings.peeksForAttention)
            } header: {
                Text("Notch")
            } footer: {
                Text(settings.displayPreference.explanation)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Feature.allCases, id: \.self) { feature in
                    Toggle(feature.title, isOn: featureBinding(feature))
                }
            } header: {
                Text("Features")
            } footer: {
                Text("A feature that is off shows nothing and does no work. Turning off Timers cancels running timers; turning off Keep Awake lets the Mac sleep again. Turning on Calendar asks for calendar access. Clipboard history is off until you turn it on.")
                    .foregroundStyle(.secondary)
            }

            Section("Feature Options") {
                Toggle("Play a sound when a timer finishes", isOn: $settings.timerPlaysSound)
                    .disabled(!settings.timersEnabled)
                Toggle("Scroll over the notch to change the volume", isOn: $settings.scrollAdjustsVolume)
                    .disabled(!settings.audioEnabled)
            }

            Section {
                Text("Shows what is playing in Music or Spotify. Playback controls ask for permission to control the app the first time you use them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Now Playing")
            }
            .disabled(!settings.musicEnabled)

            CalendarSettingsSection(settings: settings, calendar: calendar)

            Section {
                Toggle("Open the shelf as a drag approaches the notch", isOn: $settings.shelfOpensOnApproach)
                Picker("Keep items", selection: $settings.shelfItemLifetime) {
                    ForEach(ShelfLifetime.allCases) { lifetime in
                        Text(lifetime.title).tag(lifetime)
                    }
                }
            } header: {
                Text("File Shelf")
            } footer: {
                Text("Drop files, links or text on the notch to keep them close. Files are referenced, not copied. Pinned items stay until removed; turning the shelf off removes everything on it.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.shelfEnabled)

            ClipboardSettingsSection(settings: settings, clipboard: clipboard)

            DeveloperSettingsSection(settings: settings)

            Section("About") {
                LabeledContent("Version", value: Bundle.main.versionDescription)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension SettingsView {
    func featureBinding(_ feature: Feature) -> Binding<Bool> {
        switch feature {
        case .timers: $settings.timersEnabled
        case .keepAwake: $settings.keepAwakeEnabled
        case .systemMetrics: $settings.systemMetricsEnabled
        case .audio: $settings.audioEnabled
        case .quickActions: $settings.quickActionsEnabled
        case .music: $settings.musicEnabled
        case .calendar: $settings.calendarEnabled
        case .shelf: $settings.shelfEnabled
        case .clipboard: $settings.clipboardEnabled
        case .developerActivity: $settings.developerActivityEnabled
        }
    }
}

/// Calendar access, timing and which calendars to show.
private struct CalendarSettingsSection: View {
    @Bindable var settings: AppSettings
    let calendar: CalendarProvider

    var body: some View {
        Section {
            LabeledContent("Access") {
                accessControl
            }
            Picker("Show meetings in the notch", selection: $settings.calendarNotchLeadMinutes) {
                ForEach(AppSettings.calendarNotchLeadOptions, id: \.self) { minutes in
                    Text("\(minutes) minutes before").tag(minutes)
                }
            }
            Picker("Schedule looks ahead", selection: $settings.calendarLookAheadHours) {
                ForEach(AppSettings.calendarLookAheadOptions, id: \.self) { hours in
                    Text("\(hours) hours").tag(hours)
                }
            }
            if calendar.authorization.canReadEvents {
                ForEach(calendar.calendars) { info in
                    Toggle(isOn: includedBinding(info.id)) {
                        HStack(spacing: 6) {
                            Circle().fill(info.accent.settingsColor).frame(width: 8, height: 8)
                            Text(info.title)
                            if !info.sourceTitle.isEmpty {
                                Text(info.sourceTitle).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("Meetings are read on this Mac and never stored or sent anywhere. A meeting takes the notch as it approaches and peeks when it is about to start.")
                .foregroundStyle(.secondary)
        }
        .disabled(!settings.calendarEnabled)
    }

    @ViewBuilder
    private var accessControl: some View {
        switch calendar.authorization {
        case .fullAccess:
            Text("Allowed").foregroundStyle(.secondary)
        case .notDetermined:
            Button("Allow Access…", action: calendar.requestAccess)
        case .denied, .restricted, .writeOnly:
            HStack {
                Text(calendar.authorization == .restricted ? "Restricted" : "Not allowed")
                    .foregroundStyle(.secondary)
                Button("Open Privacy Settings…") {
                    NSWorkspace.shared.open(CalendarProvider.privacySettingsURL)
                }
            }
        }
    }

    private func includedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !settings.calendarExcludedIDs.contains(id) },
            set: { included in
                if included {
                    settings.calendarExcludedIDs.remove(id)
                } else {
                    settings.calendarExcludedIDs.insert(id)
                }
            }
        )
    }
}

/// Clipboard history: pause, limits, excluded apps and clearing.
private struct ClipboardSettingsSection: View {
    @Bindable var settings: AppSettings
    let clipboard: ClipboardProvider
    @State private var isConfirmingClear = false

    var body: some View {
        Section {
            if settings.clipboardEnabled, clipboard.access != .allowed {
                LabeledContent(clipboard.access == .denied ? "Clipboard access is off" : "macOS asks before each read") {
                    Button("Open Privacy Settings…") {
                        NSWorkspace.shared.open(ClipboardProvider.privacySettingsURL)
                    }
                }
            }
            Toggle("Pause keeping new copies", isOn: $settings.clipboardPaused)
                .disabled(!settings.clipboardEnabled)
            Picker("Keep up to", selection: $settings.clipboardMaxEntries) {
                ForEach(AppSettings.clipboardMaxEntriesOptions, id: \.self) { count in
                    Text("\(count) items").tag(count)
                }
            }
            .disabled(!settings.clipboardEnabled)
            Picker("Forget items after", selection: $settings.clipboardRetentionDays) {
                ForEach(AppSettings.clipboardRetentionDaysOptions, id: \.self) { days in
                    Text(Self.retentionTitle(days)).tag(days)
                }
            }
            .disabled(!settings.clipboardEnabled)
            LabeledContent("Never keep copies from") {
                Button("Add App…", action: addExcludedApp)
            }
            .disabled(!settings.clipboardEnabled)
            ForEach(settings.clipboardExcludedBundleIDs.sorted(), id: \.self) { bundleID in
                LabeledContent(Self.appName(bundleID)) {
                    Button("Remove") { settings.clipboardExcludedBundleIDs.remove(bundleID) }
                }
            }
            LabeledContent("History") {
                Button("Clear All…", role: .destructive) { isConfirmingClear = true }
            }
        } header: {
            Text("Clipboard History")
        } footer: {
            Text("Copies are kept only on this Mac and never sent anywhere. Passwords and content marked private are never kept, nor are copies from password managers. Pinned items aren't limited or forgotten.")
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Clear all clipboard history, including pinned items?", isPresented: $isConfirmingClear) {
            Button("Clear All", role: .destructive) { clipboard.clearHistory(includingPinned: true) }
        }
        .onAppear { if clipboard.isRunning { clipboard.updateAccess() } }
    }

    static func retentionTitle(_ days: Int) -> String {
        switch days {
        case 0: "Never"
        case 1: "1 day"
        default: "\(days) days"
        }
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                settings.clipboardExcludedBundleIDs.insert(bundleID)
            }
        }
    }
}

/// Where `notchctl` is and how to put it on the user's `PATH`.
enum NotchctlInstallation {
    /// The command-line tool inside the app bundle.
    static func bundledURL(in bundle: Bundle = .main) -> URL {
        bundle.bundleURL.appending(path: "Contents/MacOS/notchctl", directoryHint: .notDirectory)
    }

    /// `ln -sf "<path>" /usr/local/bin/notchctl`, with the path quoted for the shell.
    static func installCommand(for url: URL) -> String {
        var quoted = ""
        for character in url.path(percentEncoded: false) {
            // Characters that keep a special meaning inside double quotes.
            if "\\\"$`".contains(character) { quoted.append("\\") }
            quoted.append(character)
        }
        return "ln -sf \"\(quoted)\" /usr/local/bin/notchctl"
    }
}

/// Where to find `notchctl`, the command coding tools use to report to NotchDeck.
private struct DeveloperSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        let path = NotchctlInstallation.bundledURL().path(percentEncoded: false)
        let command = NotchctlInstallation.installCommand(for: NotchctlInstallation.bundledURL())
        Section {
            copyableRow("Command-line tool", value: path)
            copyableRow("Install with", value: command)
        } header: {
            Text("Developer Agents")
        } footer: {
            Text("Claude Code, Codex and other coding tools report their sessions with notchctl, over a local socket only you can reach. The README's Developer agents section shows how to set up their hooks.")
                .foregroundStyle(.secondary)
        }
        .disabled(!settings.developerActivityEnabled)
    }

    private func copyableRow(_ title: String, value: String) -> some View {
        LabeledContent {
            Button("Copy") { SystemPasteboardWriter().write(.text(value)) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }
}

private extension ActivityAccent {
    var settingsColor: Color {
        self == .neutral ? .gray : color
    }
}

private extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
