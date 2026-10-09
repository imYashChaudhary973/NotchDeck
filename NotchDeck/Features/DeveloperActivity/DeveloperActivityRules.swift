import Foundation

/// Where an agent session appears and how strongly it competes for the notch until `endsAt`.
struct DeveloperSessionPhase: Equatable, Sendable {
    var placement: ActivityPlacement
    var priority: ActivityPriority
    /// When this phase ends without a new message: the next phase begins, or the session leaves.
    var endsAt: Date
    /// The session leaves at `endsAt` (rather than moving to another phase).
    var removesAtEnd: Bool
}

/// How long and how prominently agent sessions are shown. Pure, so every boundary is unit tested.
///
/// - A busy agent (starting, working, running a command) is on the notch at 25: above playing
///   music (Passive 20), below a running timer or a meeting 15 minutes away (Active 30), so an
///   ordinary working agent never overrides an imminent calendar event.
/// - A waiting agent is Active (30).
/// - An agent that needs input or permission is Attention Required (50), so the notch peeks.
/// - Completed: "Rove finished" on the notch (30) for 10 s, then listed in the command center (15)
///   until dismissed or an hour after it finished.
/// - Failed: on the notch at 50 (peeks) for 30 s, then listed (18) for up to an hour.
/// - Cancelled: on the notch at 20 for 5 s, then gone.
/// - Stale: a busy or waiting session that hasn't reported for 30 minutes is removed (the tool
///   probably quit without saying so); one that needs attention after 8 hours.
enum DeveloperActivityRules {
    /// Between Passive (20) and Active (30).
    static let workingPriority = ActivityPriority(rawValue: 25)
    static let waitingPriority = ActivityPriority.active
    static let attentionPriority = ActivityPriority.attentionRequired
    static let completedPriority = ActivityPriority.active
    static let failedPriority = ActivityPriority.attentionRequired
    static let cancelledPriority = ActivityPriority.passive
    /// Finished sessions in the command center: a success below the calendar schedule (17), a
    /// failure above it.
    static let completedListPriority = ActivityPriority(rawValue: 15)
    static let failedListPriority = ActivityPriority(rawValue: 18)

    static let completedNotchDuration: TimeInterval = 10
    static let failedNotchDuration: TimeInterval = 30
    static let cancelledNotchDuration: TimeInterval = 5
    /// How long after finishing a completed or failed session stays in the command center.
    static let finishedListDuration: TimeInterval = 3600
    /// A busy or waiting session silent for this long is removed.
    static let activeStaleInterval: TimeInterval = 30 * 60
    /// A session that needs attention and is silent for this long is removed.
    static let attentionStaleInterval: TimeInterval = 8 * 3600

    /// The phase `session` is in at `date`; nil when it should no longer be shown.
    static func phase(for session: DeveloperActivity, at date: Date) -> DeveloperSessionPhase? {
        phases(for: session).first { date < $0.endsAt }
    }

    /// Dates at which `phase(for:at:)` changes for `session` without a new message.
    static func boundaries(for session: DeveloperActivity) -> [Date] {
        phases(for: session).map(\.endsAt)
    }

    static func nextBoundary(for session: DeveloperActivity, after date: Date) -> Date? {
        boundaries(for: session).filter { $0 > date }.min()
    }

    /// Every phase of `session`, in order; the last one removes it.
    private static func phases(for session: DeveloperActivity) -> [DeveloperSessionPhase] {
        let finished = session.finishedAt ?? session.updatedAt
        switch session.status {
        case .starting, .working, .runningCommand:
            return [DeveloperSessionPhase(placement: .notch, priority: workingPriority,
                                          endsAt: session.updatedAt.addingTimeInterval(activeStaleInterval), removesAtEnd: true)]
        case .waiting:
            return [DeveloperSessionPhase(placement: .notch, priority: waitingPriority,
                                          endsAt: session.updatedAt.addingTimeInterval(activeStaleInterval), removesAtEnd: true)]
        case .needsInput, .needsPermission:
            return [DeveloperSessionPhase(placement: .notch, priority: attentionPriority,
                                          endsAt: session.updatedAt.addingTimeInterval(attentionStaleInterval), removesAtEnd: true)]
        case .completed:
            return [
                DeveloperSessionPhase(placement: .notch, priority: completedPriority,
                                      endsAt: finished.addingTimeInterval(completedNotchDuration), removesAtEnd: false),
                DeveloperSessionPhase(placement: .commandCenter, priority: completedListPriority,
                                      endsAt: finished.addingTimeInterval(finishedListDuration), removesAtEnd: true),
            ]
        case .failed:
            return [
                DeveloperSessionPhase(placement: .notch, priority: failedPriority,
                                      endsAt: finished.addingTimeInterval(failedNotchDuration), removesAtEnd: false),
                DeveloperSessionPhase(placement: .commandCenter, priority: failedListPriority,
                                      endsAt: finished.addingTimeInterval(finishedListDuration), removesAtEnd: true),
            ]
        case .cancelled:
            return [DeveloperSessionPhase(placement: .notch, priority: cancelledPriority,
                                          endsAt: finished.addingTimeInterval(cancelledNotchDuration), removesAtEnd: true)]
        }
    }
}

extension DeveloperActivityStatus {
    /// Short status for Peek and the command center, e.g. "Needs permission".
    var statusText: String {
        switch self {
        case .starting: "Starting"
        case .working: "Working"
        case .runningCommand: "Running command"
        case .waiting: "Waiting"
        case .needsInput: "Needs input"
        case .needsPermission: "Needs permission"
        case .completed: "Finished"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var tone: AgentContent.Tone {
        switch self {
        case .starting, .working, .runningCommand: .working
        case .needsInput, .needsPermission: .attention
        case .completed: .success
        case .failed: .failure
        case .waiting, .cancelled: .neutral
        }
    }
}
