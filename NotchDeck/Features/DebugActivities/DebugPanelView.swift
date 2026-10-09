#if DEBUG
import SwiftUI

/// Developer-only panel for generating fake activities and driving notch states.
struct DebugPanelView: View {
    let provider: DebugActivityProvider
    let developer: DeveloperActivityProvider
    let engine: ActivityEngine
    let notch: NotchController

    var body: some View {
        Form {
            Section("Simulate") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        simulate("Music", "music.note") { provider.simulateMusic() }
                        simulate("Meeting in 1 min", "calendar") { provider.simulateMeeting() }
                        simulate("Timer 30 s", "timer") { provider.simulateTimer() }
                    }
                    GridRow {
                        simulate("File Transfer", "arrow.down.circle") { provider.simulateFileTransfer() }
                        simulate("Critical (8 s)", "exclamationmark.triangle", provider.simulateCritical)
                        simulate("Clipboard", "doc.on.clipboard", provider.simulateClipboard)
                    }
                    GridRow {
                        simulate("Meeting in 5 s", "calendar.badge.clock") { provider.simulateMeeting(startsIn: 5) }
                        Button("Clear All", role: .destructive, action: provider.clearAll)
                    }
                    GridRow {
                        simulate("Volume (repeat)", "speaker.wave.3") { provider.simulateVolume() }
                        simulate("Keep Awake", "cup.and.saucer") { provider.simulateKeepAwake() }
                        simulate("System Stats", "cpu") { provider.simulateSystemStats() }
                    }
                    GridRow {
                        simulate("Command Center Demo", "square.grid.2x2") { provider.simulateCommandCenterDemo() }
                            .gridCellColumns(2)
                    }
                }
            }

            Section {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        agent("Claude Working", "asterisk", DebugAgentMessages.claudeWorking)
                        agent("Claude Permission", "hand.raised", DebugAgentMessages.claudeNeedsPermission)
                        agent("Claude Finished", "checkmark.circle", DebugAgentMessages.claudeFinished)
                    }
                    GridRow {
                        agent("Codex Working", "chevron.left.forwardslash.chevron.right", DebugAgentMessages.codexWorking)
                        agent("Codex Needs Input", "questionmark.bubble", DebugAgentMessages.codexNeedsInput)
                        agent("Agent Failed", "exclamationmark.triangle", DebugAgentMessages.agentFailed)
                    }
                    GridRow {
                        Button("End Agents", role: .destructive) { DebugAgentMessages.endAll.forEach(developer.receive) }
                    }
                }
            } header: {
                Text("Developer Agents")
            } footer: {
                Text("Sent through the real Developer agents feature, as notchctl would. Turn the feature on in Settings first.")
                    .foregroundStyle(.secondary)
            }

            Section("Notch") {
                LabeledContent("State", value: notch.model.state.rawValue)
                HStack {
                    Button("Attention Peek") { notch.send(.attentionRequested) }
                    Button("Expand") { notch.send(.clicked) }
                    Button("Shelf") { notch.send(.dragEntered) }
                    Button("Collapse") { notch.send(.dismiss) }
                }
            }

            Section("Live Activities (\(engine.resolution.all.count))") {
                if engine.resolution.all.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
                ForEach(engine.resolution.all, id: \.key) { activity in
                    HStack {
                        Image(systemName: activity.presentation.symbolName)
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text(activity.title)
                            Text("\(activity.priority.rawValue) · \(activity.priority.levelName)\(activity.key == engine.resolution.primary?.key ? " · shown" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            if activity.source == provider.source {
                                provider.withdraw(activity.id)
                            } else {
                                engine.withdraw(activity.key)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Remove \(activity.title)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 480)
    }

    private func agent(_ title: String, _ systemImage: String, _ message: DeveloperBridgeMessage) -> some View {
        simulate(title, systemImage) { developer.receive(message) }
    }

    private func simulate(_ title: String, _ systemImage: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
