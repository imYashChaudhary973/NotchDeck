import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLoginService
    let calendar: CalendarProvider

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
                Text("A feature that is off shows nothing and does no work. Turning off Timers cancels running timers; turning off Keep Awake lets the Mac sleep again. Turning on Calendar asks for calendar access.")
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
