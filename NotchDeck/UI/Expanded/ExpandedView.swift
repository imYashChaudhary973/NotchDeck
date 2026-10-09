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
                LevelControl(activity: activity, level: level, model: model)
                OptionsList(activity: activity, model: model)
            }
        case .actions(let actions):
            VStack(alignment: .leading, spacing: 10) {
                FeaturedHeader(activity: activity)
                ActionGrid(activity: activity, items: actions.items, model: model)
            }
        case .schedule(let schedule):
            VStack(alignment: .leading, spacing: 8) {
                FeaturedHeader(activity: activity)
                ScheduleList(activity: activity, schedule: schedule, model: model)
            }
        case .collection(let collection):
            CollectionFeatured(activity: activity, collection: collection, model: model)
        default:
            StandardFeatured(activity: activity, model: model)
        }
    }
}

/// A level bar with an optional mute button. Draggable when the provider accepts adjustments.
private struct LevelControl: View {
    let activity: NotchActivity
    let level: LevelContent
    let model: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            if let muteActionID = level.muteActionID {
                Button { model.perform(actionID: muteActionID, on: activity) } label: {
                    Image(systemName: level.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(level.isMuted ? .red : .white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(level.isMuted ? "Unmute" : "Mute")
            }
            SegmentedLevelBar(
                value: level.isMuted ? 0 : level.value,
                tint: activity.presentation.accent.color
            )
            .overlay {
                if let adjustActionID = level.adjustActionID {
                    GeometryReader { proxy in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                let value = drag.location.x / max(proxy.size.width, 1)
                                model.adjust(actionID: adjustActionID, to: value, on: activity)
                            })
                    }
                    .accessibilityElement()
                    .accessibilityLabel(activity.title)
                    .accessibilityValue(Text(level.value, format: .percent.precision(.fractionLength(0))))
                    .accessibilityAdjustableAction { direction in
                        let step = direction == .increment ? 0.0625 : -0.0625
                        model.adjust(actionID: adjustActionID, to: level.value + step, on: activity)
                    }
                }
            }
        }
    }
}

/// The activity's options (e.g. output devices) as a selectable list.
private struct OptionsList: View {
    let activity: NotchActivity
    let model: NotchViewModel

    /// Keeps the card within the expanded height limit.
    private let maxOptions = 4

    var body: some View {
        if let options = activity.presentation.options, options.options.count > 1 {
            VStack(alignment: .leading, spacing: 2) {
                Text(options.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                ForEach(options.options.prefix(maxOptions)) { option in
                    Button { model.perform(actionID: option.actionID, on: activity) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: option.symbolName)
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 16)
                            Text(option.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if option.isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .foregroundStyle(option.isSelected ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(option.isSelected ? .white.opacity(0.1) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option.isSelected ? .isSelected : [])
                }
            }
        }
    }
}

/// Quick actions or presets as a grid of tiles.
private struct ActionGrid: View {
    let activity: NotchActivity
    let items: [ActionItem]
    let model: NotchViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(items) { item in
                Button { model.perform(actionID: item.actionID, on: activity) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(item.isActive ? activity.presentation.accent.tileTint : .white.opacity(0.85))
                            .tintedSymbolInsideClip()
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(item.isActive ? 0.16 : 0.07))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item.isActive ? .isSelected : [])
            }
        }
    }
}

struct FeaturedHeader: View {
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MediaArtwork(media: media, accent: activity.presentation.accent)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 8) {
                    // A new track slides in; play/pause and position changes don't animate it.
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
                    .id(media.trackID)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                    HStack(spacing: 14) {
                        transportButton("backward.fill", media.previousActionID, label: "Previous")
                        if let playPause = media.playPauseActionID {
                            Button { model.perform(actionID: playPause, on: activity) } label: {
                                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.black)
                                    .contentTransition(.symbolEffect(.replace))
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(.white))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
                        }
                        transportButton("forward.fill", media.nextActionID, label: "Next")
                        ForEach(activity.actions) { action in
                            CapsuleActionButton(action: action) { model.perform(action, on: activity) }
                        }
                    }
                }
                .clipped()
                Spacer(minLength: 0)
            }

            if let duration = media.duration, duration > 0 {
                PlaybackProgress(media: media, duration: duration, tint: .white)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.85), value: media.trackID)
        .animation(.easeInOut(duration: 0.2), value: media.isPlaying)
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

// MARK: - Schedule

/// Timed entries (meetings) as rows: time, a calendar-colored bar, the title and a Join button.
private struct ScheduleList: View {
    let activity: NotchActivity
    let schedule: ScheduleContent
    let model: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(schedule.entries) { entry in
                HStack(spacing: 8) {
                    Text(entry.isAllDay ? "All day" : entry.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(entry.isNow ? .white : .secondary)
                        .frame(width: 58, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Capsule()
                        .fill(entry.accent.tileTint)
                        .frame(width: 3, height: 14)
                    Text(entry.title)
                        .font(.system(size: 12, weight: entry.isNow ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if entry.isNow {
                        Text("Now")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(entry.accent.tileTint)
                    }
                    if let join = entry.joinActionID {
                        CapsuleActionButton(action: ActivityAction(id: join, title: "Join"), compact: true) {
                            model.perform(actionID: join, on: activity)
                        }
                        .accessibilityLabel("Join \(entry.title)")
                    }
                }
                .frame(height: 22)
                .accessibilityElement(children: .combine)
            }
        }
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

    /// Button counts to try for an `actions` row, most first.
    static func compactActionCounts(for total: Int) -> [Int] {
        Array(Set([total, 6, 5, 4, 3].map { min($0, total) })).sorted(by: >)
    }

    var body: some View {
        HStack(spacing: 10) {
            IconTile(presentation: activity.presentation, size: 22)
            if !isActionRow {
                Text(activity.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 6)
            trailing
        }
        .accessibilityElement(children: .combine)
    }

    /// Button rows need the room; the icon still identifies them.
    private var isActionRow: Bool {
        if case .actions = activity.presentation.content { true } else { false }
    }

    private var hasCountdown: Bool {
        if case .countdown = activity.presentation.compactAccessory { true } else { false }
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
        case .actions(let actions):
            // Show as many buttons as fit beside the icon, so the row never widens its column.
            ViewThatFits(in: .horizontal) {
                ForEach(Self.compactActionCounts(for: actions.items.count), id: \.self) { count in
                    CompactActionButtons(activity: activity, items: Array(actions.items.prefix(count)), model: model)
                }
            }
        case .collection(let collection):
            CollectionWidgetTrailing(activity: activity, collection: collection)
        case .schedule:
            // The next entry ("11:00 Design Review").
            if let subtitle = activity.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .standard:
            // A ticking countdown says more than a static subtitle (e.g. a running timer).
            if hasCountdown {
                CompactAccessoryView(activity: activity, fontSize: 11)
                    .fixedSize()
            } else if let subtitle = activity.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let action = activity.actions.first {
                CapsuleActionButton(action: action, compact: true) { model.perform(action, on: activity) }
            } else if !hasCountdown {
                CompactAccessoryView(activity: activity, fontSize: 11)
            }
        }
    }
}

/// A row of small buttons for `actions` content in the widget column.
private struct CompactActionButtons: View {
    let activity: NotchActivity
    let items: [ActionItem]
    let model: NotchViewModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button { model.perform(actionID: item.actionID, on: activity) } label: {
                    Group {
                        if let compactTitle = item.compactTitle {
                            Text(compactTitle)
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .lineLimit(1)
                        } else {
                            Image(systemName: item.symbolName)
                                .font(.system(size: 10, weight: .semibold))
                                .tintedSymbolInsideClip()
                        }
                    }
                    .foregroundStyle(item.isActive ? .white : .white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22)
                    .frame(height: 20)
                    .background(Capsule().fill(.white.opacity(item.isActive ? 0.2 : 0.1)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .fixedSize()
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
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(action.isDestructive ? .red : .white)
            .padding(.horizontal, compact ? 10 : 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.14)))
            .contentShape(Capsule())
            // Never wraps; the row's other text truncates instead.
            .fixedSize()
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
