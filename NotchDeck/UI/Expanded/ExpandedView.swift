import SwiftUI

/// The expanded notch: the primary activity in detail, followed by what is queued behind it.
struct ExpandedView: View {
    let model: NotchViewModel
    let notchSize: CGSize

    /// Queued activities shown before collapsing the rest into a count.
    private let visibleQueueLimit = 2

    var body: some View {
        let resolution = model.resolution

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: notchSize.width)
                Button(action: model.openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 12)
            .frame(height: notchSize.height)

            VStack(alignment: .leading, spacing: 12) {
                if let primary = resolution.primary {
                    PrimaryActivityView(activity: primary) { action in
                        model.perform(action, on: primary)
                    }
                } else {
                    EmptyActivityView()
                }

                if !resolution.queued.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(resolution.queued.prefix(visibleQueueLimit), id: \.key) { activity in
                            QueuedActivityRow(activity: activity)
                        }
                        if resolution.queued.count > visibleQueueLimit {
                            Text("+\(resolution.queued.count - visibleQueueLimit) more")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 10)
                    .overlay(alignment: .top) {
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Measure the content's natural height (even while the surface is still animating
            // open) so the expanded notch fits it instead of using a fixed height.
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

private struct PrimaryActivityView: View {
    let activity: NotchActivity
    let perform: (ActivityAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ActivityGlyph(presentation: activity.presentation, size: 20)
                    .frame(width: 36, height: 36)
                    .background(activity.presentation.accent.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.system(size: 14, weight: .semibold))
                    if let subtitle = activity.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)

                Spacer(minLength: 8)

                if case .countdown = activity.presentation.compactAccessory {
                    CompactAccessoryView(activity: activity, fontSize: 20)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
            }

            if let progress = activity.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(activity.presentation.accent.color)
                    .animation(.linear(duration: 0.3), value: progress)
            }

            if !activity.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(activity.actions) { action in
                        Button(role: action.isDestructive ? .destructive : nil) {
                            perform(action)
                        } label: {
                            if let systemImage = action.systemImage {
                                Label(action.title, systemImage: systemImage)
                            } else {
                                Text(action.title)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

private struct QueuedActivityRow: View {
    let activity: NotchActivity

    var body: some View {
        HStack(spacing: 8) {
            ActivityGlyph(presentation: activity.presentation, size: 11)
                .frame(width: 16)
            Text(activity.title)
                .font(.system(size: 12, weight: .medium))
            if let subtitle = activity.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            CompactAccessoryView(activity: activity, fontSize: 11)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyActivityView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                .font(.system(size: 14, weight: .semibold))
            Text("Nothing happening right now.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
