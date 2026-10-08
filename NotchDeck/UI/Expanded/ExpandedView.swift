import SwiftUI

/// The expanded notch: a command center with section tabs beside the notch, the featured
/// activity on a large card and the next few activities in a widget column.
///
/// Which activities appear where is decided by `CommandCenterLayout` from the engine's
/// resolution, so priority still determines prominence.
struct ExpandedView: View {
    let model: NotchViewModel
    let notchSize: CGSize

    var body: some View {
        let layout = CommandCenterLayout.make(resolution: model.resolution, selected: model.selectedSection)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack {
                    if layout.showsTabs {
                        SectionTabs(layout: layout) { model.selectedSection = $0 }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                Color.clear.frame(width: notchSize.width)

                HStack {
                    Spacer(minLength: 0)
                    Button(action: model.openSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .frame(height: notchSize.height)

            Group {
                if let featured = layout.featured {
                    HStack(alignment: .top, spacing: 10) {
                        FeaturedCard(activity: featured, model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .cardBackground()
                        if !layout.widgets.isEmpty {
                            WidgetColumn(activities: layout.widgets, hiddenCount: layout.hiddenWidgetCount, model: model)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .cardBackground()
                        }
                    }
                } else {
                    EmptyCommandCenter()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardBackground()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)
            // Measure the natural height (even mid-animation) so the notch fits its content.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                model.updateExpandedContentHeight(height)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private extension View {
    func cardBackground() -> some View {
        padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.07)))
    }
}

// MARK: - Tabs

private struct SectionTabs: View {
    let layout: CommandCenterLayout
    let select: (CommandCenterSection) -> Void

    /// Beyond this many tabs, the ear beside the notch runs out of room.
    private let maxTabs = 6

    var body: some View {
        HStack(spacing: 2) {
            ForEach(layout.sections.prefix(maxTabs), id: \.self) { section in
                let isSelected = section == layout.selectedSection
                Button { select(section) } label: {
                    Image(systemName: section.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                        .frame(width: 26, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? .white.opacity(0.18) : .clear)
                        )
                        .overlay(alignment: .topTrailing) {
                            if layout.attentionSections.contains(section) {
                                Circle().fill(.purple).frame(width: 5, height: 5).offset(x: -3, y: 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}

// MARK: - Featured card

private struct FeaturedCard: View {
    let activity: NotchActivity
    let model: NotchViewModel

    var body: some View {
        switch activity.presentation.content {
        case .media(let media):
            MediaCard(activity: activity, media: media, model: model)
        case .level(let level):
            VStack(alignment: .leading, spacing: 10) {
                FeaturedHeader(activity: activity, trailingText: level.valueText)
                SegmentedLevelBar(value: level.value, tint: activity.presentation.accent.color)
            }
        default:
            StandardFeatured(activity: activity, model: model)
        }
    }
}

private struct FeaturedHeader: View {
    let activity: NotchActivity
    var trailingText: String?

    var body: some View {
        HStack(spacing: 10) {
            IconTile(presentation: activity.presentation, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
        }
    }
}

private struct StandardFeatured: View {
    let activity: NotchActivity
    let model: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                FeaturedHeader(activity: activity)
                if case .countdown = activity.presentation.compactAccessory {
                    CompactAccessoryView(activity: activity, fontSize: 20)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
            }

            switch activity.presentation.content {
            case .metric(let metric):
                HStack(spacing: 8) {
                    MetricBar(value: metric.value, tint: activity.presentation.accent.color, height: 6)
                    Text(metric.valueText).font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
            case .toggle(let toggle):
                ToggleRow(activity: activity, toggle: toggle, model: model)
            default:
                EmptyView()
            }

            if let progress = activity.progress {
                MetricBar(value: progress, tint: activity.presentation.accent.color, height: 6)
            }

            if !activity.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(activity.actions) { action in
                        CapsuleActionButton(action: action) { model.perform(action, on: activity) }
                    }
                }
            }
        }
    }
}

// MARK: - Media

private struct MediaCard: View {
    let activity: NotchActivity
    let media: MediaContent
    let model: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Artwork(media: media, accent: activity.presentation.accent)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(activity.title)
                            .font(.system(size: 14, weight: .semibold))
                        if let subtitle = activity.subtitle {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)

                    HStack(spacing: 14) {
                        transportButton("backward.fill", media.previousActionID, label: "Previous")
                        if let playPause = media.playPauseActionID {
                            Button { model.perform(actionID: playPause, on: activity) } label: {
                                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(.white))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
                        }
                        transportButton("forward.fill", media.nextActionID, label: "Next")
                    }
                }
                Spacer(minLength: 0)
            }

            if let duration = media.duration, duration > 0 {
                PlaybackProgress(media: media, duration: duration, tint: .white)
            }
        }
    }

    @ViewBuilder
    private func transportButton(_ symbol: String, _ actionID: ActivityAction.ID?, label: String) -> some View {
        if let actionID {
            Button { model.perform(actionID: actionID, on: activity) } label: {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }
}

private struct Artwork: View {
    let media: MediaContent
    let accent: ActivityAccent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let data = media.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(
                    colors: [accent.color.opacity(0.95), .purple.opacity(0.8), .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: media.artworkSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// Elapsed / remaining playback time. Ticks once per second only while visible and playing.
private struct PlaybackProgress: View {
    let media: MediaContent
    let duration: TimeInterval
    let tint: Color

    var body: some View {
        if media.isPlaying {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                row(position: media.position(at: context.date))
            }
        } else {
            row(position: media.position(at: .now))
        }
    }

    private func row(position: TimeInterval) -> some View {
        HStack(spacing: 8) {
            Text(Self.format(position))
            MetricBar(value: position / duration, tint: tint, height: 4)
            Text(Self.format(duration))
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Widget column

private struct WidgetColumn: View {
    let activities: [NotchActivity]
    let hiddenCount: Int
    let model: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(activities.enumerated()), id: \.element.key) { index, activity in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                }
                WidgetRow(activity: activity, model: model)
                    .frame(minHeight: 30)
                    .padding(.vertical, 2)
            }
            if hiddenCount > 0 {
                Text("+\(hiddenCount) more")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }
}

private struct WidgetRow: View {
    let activity: NotchActivity
    let model: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            IconTile(presentation: activity.presentation, size: 22)
            Text(activity.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 6)
            trailing
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        let tint = activity.presentation.accent == .neutral ? Color.white : activity.presentation.accent.color
        switch activity.presentation.content {
        case .metric(let metric):
            MetricBar(value: metric.value, tint: tint)
                .frame(width: 80)
            Text(metric.valueText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        case .level(let level):
            MetricBar(value: level.value, tint: tint)
                .frame(width: 80)
            if let text = level.valueText {
                Text(text)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }
        case .toggle(let toggle):
            ToggleRow(activity: activity, toggle: toggle, model: model)
        case .media(let media):
            if let playPause = media.playPauseActionID {
                Button { model.perform(actionID: playPause, on: activity) } label: {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
            }
        case .standard:
            if let subtitle = activity.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let action = activity.actions.first {
                CapsuleActionButton(action: action, compact: true) { model.perform(action, on: activity) }
            } else {
                CompactAccessoryView(activity: activity, fontSize: 11)
            }
        }
    }
}

// MARK: - Controls

private struct ToggleRow: View {
    let activity: NotchActivity
    let toggle: ToggleContent
    let model: NotchViewModel

    var body: some View {
        HStack(spacing: 8) {
            if let stateText = toggle.stateText {
                Text(stateText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Toggle(activity.title, isOn: Binding(
                get: { toggle.isOn },
                set: { _ in model.perform(actionID: toggle.actionID, on: activity) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
    }
}

private struct CapsuleActionButton: View {
    let action: ActivityAction
    var compact = false
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 4) {
                if let systemImage = action.systemImage, !compact {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                }
                Text(action.title)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(action.isDestructive ? .red : .white)
            .padding(.horizontal, compact ? 10 : 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty

private struct EmptyCommandCenter: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 14, weight: .semibold))
                Text("Nothing happening right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
