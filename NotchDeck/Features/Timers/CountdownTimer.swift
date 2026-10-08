import Foundation

/// One countdown timer. Running timers store their end date, so they stay wall-clock accurate
/// across sleep and relaunch without any ticking.
struct CountdownTimer: Codable, Equatable, Identifiable, Sendable {
    enum State: Codable, Equatable, Sendable {
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        case finished(at: Date)
    }

    let id: UUID
    var label: String
    /// The duration the timer was started with (used by Restart).
    var duration: TimeInterval
    var state: State

    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running(let endsAt): max(endsAt.timeIntervalSince(now), 0)
        case .paused(let remaining): remaining
        case .finished: 0
        }
    }

    func phase(at now: Date) -> TimerPhase {
        switch state {
        case .paused: return .paused
        case .finished: return .finished
        case .running:
            let remaining = remaining(at: now)
            if remaining <= TimerRules.finalSecondsThreshold { return .finalSeconds }
            if remaining <= TimerRules.finalMinuteThreshold { return .finalMinute }
            return .running
        }
    }
}

/// How urgent a timer is, which sets its priority.
enum TimerPhase: Equatable, Sendable {
    case running
    case finalMinute
    case finalSeconds
    case paused
    case finished

    var priority: ActivityPriority {
        switch self {
        case .paused: .passive
        case .running: .active
        case .finalMinute: ActivityPriority(rawValue: 35)
        case .finalSeconds: .timeSensitive
        case .finished: .attentionRequired
        }
    }
}

enum TimerRules {
    static let finalMinuteThreshold: TimeInterval = 60
    static let finalSecondsThreshold: TimeInterval = 10
    /// How long a finished timer stays on the notch (at Attention Required) before it is removed.
    static let finishedAlertDuration: TimeInterval = 10
    static let presets: [TimeInterval] = [5, 10, 15, 25, 30, 60].map { $0 * 60 }
    static let durationRange: ClosedRange<TimeInterval> = 1...(24 * 60 * 60)
    /// More than this many timers is almost certainly a mistake; the oldest finished/paused go first.
    static let maximumTimers = 10
    static let addedTime: TimeInterval = 60

    /// "25 min", "1 hr", "1 hr 30 min", "45 sec".
    static func durationLabel(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if seconds > 0 && hours == 0 { parts.append("\(seconds) sec") }
        return parts.isEmpty ? "0 sec" : parts.joined(separator: " ")
    }

    /// "5m", "1h", "1h30".
    static func shortDurationLabel(_ duration: TimeInterval) -> String {
        let minutes = Int(duration.rounded()) / 60
        if minutes >= 60 {
            return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)"
        }
        return "\(minutes)m"
    }

    /// A clock-style remaining time: "4:05" or "1:02:03".
    static func clockText(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// All timers and every rule that changes them. A value type with no clocks or side effects,
/// so the timer feature's behavior is unit tested directly.
struct TimerCollection: Codable, Equatable, Sendable {
    private(set) var timers: [CountdownTimer] = []

    var isEmpty: Bool { timers.isEmpty }

    func timer(_ id: UUID) -> CountdownTimer? {
        timers.first { $0.id == id }
    }

    @discardableResult
    mutating func start(duration: TimeInterval, label: String? = nil, now: Date, id: UUID = UUID()) -> UUID {
        let duration = min(max(duration, TimerRules.durationRange.lowerBound), TimerRules.durationRange.upperBound)
        let label = label.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(TimerRules.durationLabel(duration)) timer"
        timers.append(CountdownTimer(id: id, label: label, duration: duration, state: .running(endsAt: now.addingTimeInterval(duration))))
        trimToLimit()
        return id
    }

    mutating func pause(_ id: UUID, now: Date) {
        update(id) { timer in
            guard case .running = timer.state else { return }
            timer.state = .paused(remaining: timer.remaining(at: now))
        }
    }

    mutating func resume(_ id: UUID, now: Date) {
        update(id) { timer in
            guard case .paused(let remaining) = timer.state else { return }
            timer.state = .running(endsAt: now.addingTimeInterval(remaining))
        }
    }

    mutating func addTime(_ seconds: TimeInterval, to id: UUID, now: Date) {
        update(id) { timer in
            switch timer.state {
            case .running(let endsAt):
                timer.state = .running(endsAt: max(endsAt, now).addingTimeInterval(seconds))
            case .paused(let remaining):
                timer.state = .paused(remaining: remaining + seconds)
            case .finished:
                timer.state = .running(endsAt: now.addingTimeInterval(seconds))
            }
        }
    }

    mutating func restart(_ id: UUID, now: Date) {
        update(id) { timer in
            timer.state = .running(endsAt: now.addingTimeInterval(timer.duration))
        }
    }

    /// Cancels a running or paused timer, or dismisses a finished one.
    mutating func remove(_ id: UUID) {
        timers.removeAll { $0.id == id }
    }

    mutating func removeAll() {
        timers.removeAll()
    }

    /// Finishes timers that reached zero and removes finished timers whose alert is over.
    /// - Returns: The timers that finished during this call.
    @discardableResult
    mutating func advance(to now: Date) -> [CountdownTimer] {
        var finished: [CountdownTimer] = []
        for index in timers.indices {
            if case .running(let endsAt) = timers[index].state, endsAt <= now {
                timers[index].state = .finished(at: endsAt)
                finished.append(timers[index])
            }
        }
        timers.removeAll { timer in
            guard case .finished(let at) = timer.state else { return false }
            return at.addingTimeInterval(TimerRules.finishedAlertDuration) <= now
        }
        // A timer that finished long ago (e.g. while the app wasn't running) is not announced.
        return finished.filter { timer in timers.contains { $0.id == timer.id } }
    }

    /// The single timer that should compete for the notch: a finished one, else the running timer
    /// closest to zero, else the paused timer with the least time left.
    func mostRelevant(at now: Date) -> UUID? {
        func rank(_ timer: CountdownTimer) -> (Int, TimeInterval) {
            switch timer.state {
            case .finished(let at): (0, -at.timeIntervalSinceReferenceDate)
            case .running: (1, timer.remaining(at: now))
            case .paused(let remaining): (2, remaining)
            }
        }
        return timers.min { rank($0) < rank($1) }?.id
    }

    /// The next moment any timer changes phase, finishes or stops alerting. Nil when nothing will.
    func nextTransition(after now: Date) -> Date? {
        timers.flatMap { timer -> [Date] in
            switch timer.state {
            case .running(let endsAt):
                [endsAt.addingTimeInterval(-TimerRules.finalMinuteThreshold),
                 endsAt.addingTimeInterval(-TimerRules.finalSecondsThreshold),
                 endsAt]
            case .finished(let at):
                [at.addingTimeInterval(TimerRules.finishedAlertDuration)]
            case .paused:
                []
            }
        }
        .filter { $0 > now }
        .min()
    }

    private mutating func update(_ id: UUID, _ change: (inout CountdownTimer) -> Void) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        change(&timers[index])
    }

    private mutating func trimToLimit() {
        while timers.count > TimerRules.maximumTimers {
            // Drop the oldest timer that isn't running, else the oldest one.
            let index = timers.firstIndex { if case .running = $0.state { false } else { true } } ?? 0
            timers.remove(at: index)
        }
    }
}
