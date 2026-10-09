import SwiftUI

extension AgentContent.Tone {
    var color: Color {
        switch self {
        case .working: .blue
        // Matches the attention badge on the command center tabs.
        case .attention: .purple
        case .success: .green
        case .failure: .red
        case .neutral: .white.opacity(0.6)
        }
    }
}

/// The featured card for `agent` content: the tool, project and task, a colored status with the
/// elapsed time, the latest status message, progress and the session's actions.
struct AgentCard: View {
    let activity: NotchActivity
    let agent: AgentContent
    let model: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                IconTile(presentation: activity.presentation, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    if agent.project != nil {
                        Text(agent.providerName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .lineLimit(1)
                    }
                    Text(agent.project ?? agent.providerName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if let task = agent.task {
                        Text(task)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(agent.tone.color)
                        .frame(width: 6, height: 6)
                    Text(agent.statusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(agent.tone.color)
                        .lineLimit(1)
                    AgentElapsedText(agent: agent)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if let message = agent.message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let progress = activity.progress {
                MetricBar(value: progress, tint: agent.tone.color, height: 6)
            }

            AgentActionButtons(activity: activity, model: model)
        }
    }
}

/// How long the session has been at its task: live while it runs, the final duration once it ended.
struct AgentElapsedText: View {
    let agent: AgentContent

    var body: some View {
        if let end = agent.endedAt {
            Text(Self.durationText(end.timeIntervalSince(agent.startedAt)))
        } else {
            ElapsedText(start: agent.startedAt)
        }
    }

    /// "12m 48s", "1h 5m", "8s".
    static func durationText(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 0).rounded())
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
    }
}

/// The session's actions as capsules; when they don't fit, all but the first become icon buttons,
/// then all of them do.
private struct AgentActionButtons: View {
    let activity: NotchActivity
    let model: NotchViewModel

    var body: some View {
        if !activity.actions.isEmpty {
            ViewThatFits(in: .horizontal) {
                row(titled: activity.actions.count)
                row(titled: 1)
                row(titled: 0)
            }
        }
    }

    private func row(titled count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(activity.actions.enumerated()), id: \.element.id) { index, action in
                if index < count {
                    CapsuleActionButton(action: action) { model.perform(action, on: activity) }
                } else {
                    IconActionButton(action: action) { model.perform(action, on: activity) }
                }
            }
        }
    }
}

/// The trailing side of an `agent` row in the widget column: a status dot and text (plus the live
/// elapsed time while the agent is busy) and the first action as an icon button.
struct AgentWidgetTrailing: View {
    let activity: NotchActivity
    let agent: AgentContent
    let model: NotchViewModel

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(agent.tone.color)
                .frame(width: 6, height: 6)
            Text(agent.statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if agent.tone == .working, agent.endedAt == nil {
                ElapsedText(start: agent.startedAt)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        if let action = activity.actions.first {
            IconActionButton(action: action) { model.perform(action, on: activity) }
        }
    }
}
