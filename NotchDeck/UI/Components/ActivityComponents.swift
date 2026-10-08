import AppKit
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

extension ActivityAccent {
    /// Neutral reads as white on the black surface; other accents use their color.
    var tileTint: Color {
        self == .neutral ? .white : color
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
                .foregroundStyle(activity.presentation.accent == .neutral ? .white : activity.presentation.accent.color)
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

/// An activity's symbol on a rounded tile.
///
/// - `filled`: solid accent tile with a white symbol (app-icon look, used in Peek).
/// - otherwise: a subtle tinted tile with the symbol in the accent color (used in lists).
struct IconTile: View {
    let presentation: ActivityPresentation
    var size: CGFloat = 22
    var filled = false

    var body: some View {
        let accent = presentation.accent
        let tint = accent == .neutral ? Color.white : accent.color
        Image(systemName: presentation.symbolName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(filled ? .white : tint)
            .tintedSymbolInsideClip()
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(filled ? tint.opacity(accent == .neutral ? 0.25 : 1) : tint.opacity(0.16))
            )
            .accessibilityHidden(true)
    }
}

/// A thin capsule bar for a 0…1 value.
struct MetricBar: View {
    let value: Double
    var tint: Color = .white
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(tint).frame(width: max(proxy.size.width * value, value > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: value)
        .accessibilityElement()
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

/// A segmented bar for a 0…1 level, fading from white to the accent color (volume HUD style).
struct SegmentedLevelBar: View {
    let value: Double
    var tint: Color = .orange
    var segments = 40
    var height: CGFloat = 18

    var body: some View {
        let filled = Int((value * Double(segments)).rounded())
        HStack(spacing: 0) {
            ForEach(0..<segments, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? color(at: index) : Color.white.opacity(0.14))
                    .frame(width: 3, height: height)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: filled)
        .accessibilityElement()
        .accessibilityLabel("Level")
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }

    private func color(at index: Int) -> Color {
        let fraction = Double(index) / Double(max(segments - 1, 1))
        // Blend from white to the tint across the bar (Color.mix needs macOS 15).
        let blended = NSColor.white.blended(withFraction: fraction, of: NSColor(tint)) ?? NSColor(tint)
        return Color(nsColor: blended)
    }
}
