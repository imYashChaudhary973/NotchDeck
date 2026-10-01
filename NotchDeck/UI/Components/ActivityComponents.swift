import SwiftUI

extension ActivityAccent {
    var color: Color {
        switch self {
        case .neutral: .white
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        case .pink: .pink
        case .yellow: .yellow
        }
    }
}

extension View {
    /// Layered SF Symbols (e.g. `waveform`) lose their foreground color and render white when drawn
    /// inside a clip or mask, as the notch surface is. Flattening them first keeps the tint.
    func tintedSymbolInsideClip() -> some View {
        compositingGroup()
    }
}

/// An activity's SF Symbol in its accent color.
struct ActivityGlyph: View {
    let presentation: ActivityPresentation
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: presentation.symbolName)
            .font(.system(size: size, weight: .semibold))
            // Monochrome (the default): hierarchical rendering dims filled symbols to near-black.
            .foregroundStyle(presentation.accent.color)
            .tintedSymbolInsideClip()
            .accessibilityHidden(true)
    }
}

/// The trailing accessory of a compact activity (text, symbol, countdown or progress ring).
struct CompactAccessoryView: View {
    let activity: NotchActivity
    var fontSize: CGFloat = 12

    var body: some View {
        switch activity.presentation.compactAccessory {
        case .text(let text):
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(activity.presentation.accent.color)
                .tintedSymbolInsideClip()
        case .countdown(let target):
            CountdownText(target: target)
                .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .progress:
            ProgressRing(progress: activity.progress ?? 0, tint: activity.presentation.accent.color)
                .frame(width: fontSize + 2, height: fontSize + 2)
        case nil:
            EmptyView()
        }
    }
}

/// A countdown rendered by the system (no app-side timer needed to keep it ticking).
struct CountdownText: View {
    let target: Date

    var body: some View {
        // `Text(timerInterval:)` requires a non-empty range; clamp past targets to zero.
        let now = Date.now
        Text(timerInterval: now...max(target, now), countsDown: true)
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.linear(duration: 0.3), value: progress)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
