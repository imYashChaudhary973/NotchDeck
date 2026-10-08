import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLoginService

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
                Text("A feature that is off shows nothing and does no work. Turning off Timers cancels running timers; turning off Keep Awake lets the Mac sleep again.")
                    .foregroundStyle(.secondary)
            }

            Section("Feature Options") {
                Toggle("Play a sound when a timer finishes", isOn: $settings.timerPlaysSound)
                    .disabled(!settings.timersEnabled)
                Toggle("Scroll over the notch to change the volume", isOn: $settings.scrollAdjustsVolume)
                    .disabled(!settings.audioEnabled)
            }

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
        }
    }
}

private extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
