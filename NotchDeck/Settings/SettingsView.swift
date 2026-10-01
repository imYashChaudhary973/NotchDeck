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

            Section("About") {
                LabeledContent("Version", value: Bundle.main.versionDescription)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
