import AppKit
import Observation
import SwiftUI

/// Connects the Activity Engine, the state machine and the notch panel.
///
/// Responsibilities:
/// - feed engine output and user input into `NotchStateMachine` as events,
/// - apply the resulting state to the panel (frame, tracking, event monitors),
/// - keep the panel on the right display as screens change.
///
/// This is the only type that touches the notch window.
@MainActor
final class NotchController {
    /// How long an attention peek stays open without interaction.
    static let attentionPeekDuration: Duration = .seconds(5)
    /// Grace period before a pointer exit collapses the notch, to absorb edge jitter.
    static let pointerExitDelay: Duration = .milliseconds(120)
    /// Time for the surface to finish shrinking before the panel is resized down to it.
    static let shrinkDelay: Duration = .milliseconds(550)
    /// Full-screen transitions animate after the Space changes; check coverage again once they settle.
    static let fullScreenRecheckDelay: Duration = .seconds(1)

    let model: NotchViewModel
    var onOpenSettings: (() -> Void)? {
        get { model.onOpenSettings }
        set { model.onOpenSettings = newValue }
    }

    private let engine: ActivityEngine
    private let settings: AppSettings
    private var machine: NotchStateMachine
    private var geometry: NotchGeometry?

    private var panel: NotchPanel?
    private var hostingView: NotchHostingView<NotchRootView>?

    private var outsideClickMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Whether a full-screen window covers the notch's display. Only tracked for virtual notches.
    private var isFullScreenCovered = false
    private var shrinkTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var fullScreenRecheckTask: Task<Void, Never>?
    private var attentionPeekTask: Task<Void, Never>?
    private var pointerExitTask: Task<Void, Never>?
    private var isStarted = false

    init(engine: ActivityEngine, settings: AppSettings) {
        self.engine = engine
        self.settings = settings
        self.machine = NotchStateMachine(configuration: settings.stateMachineConfiguration)
        self.model = NotchViewModel(engine: engine)
        model.onClick = { [weak self] in self?.send(.clicked) }
        model.onLayoutChange = { [weak self] in self?.updatePanelFrame(animated: true) }
    }

    /// The current presentation state (read-only outside the controller).
    var state: NotchPresentationState {
        machine.state
    }

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let panel = NotchPanel()
        let hostingView = NotchHostingView(rootView: NotchRootView(model: model))
        hostingView.onPointerEntered = { [weak self] in self?.pointerEntered() }
        hostingView.onPointerExited = { [weak self] in self?.pointerExited() }
        hostingView.onClickOutside = { [weak self] in self?.send(.clickedOutside) }
        hostingView.onDragUpdated = { [weak self] location, description in
            guard let self else { return }
            self.send(.dragEntered)
            self.model.updateShelfDrag(ShelfDrag(location: location, itemDescription: description))
        }
        hostingView.onDragExited = { [weak self] in self?.send(.dragExited) }
        hostingView.onDrop = { [weak self] in self?.send(.dropCompleted) }
        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView

        engine.onResolutionChange = { [weak self] old, new in
            self?.resolutionChanged(from: old, to: new)
        }
        machine.handle(.activityAvailabilityChanged(hasActivity: engine.resolution.primary != nil))

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScreen() }
        }

        // Entering or leaving a full-screen app switches Spaces; borderless full-screen
        // windows (e.g. games) come and go with app activation.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
        ].map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.workspaceChanged() }
            }
        }

        observeSettings()
        updateScreen()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        engine.onResolutionChange = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        removeOutsideClickMonitors()
        [shrinkTask, hideTask, fullScreenRecheckTask, attentionPeekTask, pointerExitTask].forEach { $0?.cancel() }
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    // MARK: Events

    /// Feeds an event to the state machine and applies the result.
    func send(_ event: NotchEvent) {
        guard machine.handle(event) else { return }
        applyState()
    }

    private func resolutionChanged(from old: ActivityResolution, to new: ActivityResolution) {
        send(.activityAvailabilityChanged(hasActivity: new.primary != nil))

        if Self.shouldReveal(from: old, to: new) {
            send(.attentionRequested)
            // Repeated updates (e.g. volume changes) keep an open reveal alive.
            updateAttentionPeekTimeout()
        } else if machine.isAttentionPeek,
                  old.primary?.presentation.revealsOnUpdate == true,
                  old.primary?.key != new.primary?.key {
            // A HUD-style reveal ends as soon as its activity stops being primary.
            send(.peekTimedOut)
        }
    }

    /// Whether a resolution change should briefly reveal the notch.
    ///
    /// - A primary activity that requests attention reveals when it appears or escalates.
    /// - A primary activity with `revealsOnUpdate` reveals on every change.
    static func shouldReveal(from old: ActivityResolution, to new: ActivityResolution) -> Bool {
        guard let primary = new.primary else { return false }
        if primary.presentation.revealsOnUpdate {
            return old.primary != primary
        }
        guard primary.priority.requestsAttention else { return false }
        let alreadyAttended = old.primary?.key == primary.key && old.primary?.priority.requestsAttention == true
        return !alreadyAttended
    }

    private func pointerEntered() {
        pointerExitTask?.cancel()
        pointerExitTask = nil
        send(.pointerEntered)
    }

    private func pointerExited() {
        pointerExitTask?.cancel()
        pointerExitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pointerExitDelay)
            guard !Task.isCancelled else { return }
            self?.send(.pointerExited)
        }
    }

    // MARK: Applying state

    private func applyState() {
        model.update(state: machine.state, geometry: geometry)
        updatePanelFrame(animated: true)
        updatePanelVisibility()
        updateOutsideClickMonitoring()
        updateAttentionPeekTimeout()
    }

    private var targetSize: CGSize? {
        geometry.map {
            NotchLayout.metrics(
                for: machine.state,
                notchSize: $0.notchSize,
                expandedContentHeight: model.expandedContentHeight
            ).outerSize
        }
    }

    /// Grows the panel immediately so the surface can animate outward inside it, and shrinks it
    /// only after a collapse animation finishes. Transparent panel areas pass clicks through.
    private func updatePanelFrame(animated: Bool) {
        guard let panel, let hostingView, let geometry, let target = targetSize else { return }
        hostingView.interactiveSize = target

        let finalFrame = geometry.topCenteredFrame(size: target)
        shrinkTask?.cancel()
        shrinkTask = nil

        guard animated, panel.frame.size != .zero, panel.frame.minY < geometry.screenFrame.maxY else {
            panel.setFrame(finalFrame, display: true)
            return
        }

        let current = panel.frame.size
        let union = CGSize(width: max(current.width, target.width), height: max(current.height, target.height))
        if union != current {
            panel.setFrame(geometry.topCenteredFrame(size: union), display: true)
        }
        if union != target {
            shrinkTask = Task { [weak self] in
                try? await Task.sleep(for: Self.shrinkDelay)
                guard !Task.isCancelled, let self, let panel = self.panel else { return }
                panel.setFrame(finalFrame, display: true)
            }
        }
    }

    // MARK: Outside clicks

    /// Event monitors are installed only while a transient state is open, so the idle
    /// notch receives no global events at all.
    private func updateOutsideClickMonitoring() {
        if machine.state.isTransient {
            installOutsideClickMonitors()
        } else {
            removeOutsideClickMonitors()
        }
    }

    private func installOutsideClickMonitors() {
        guard outsideClickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Clicks delivered to other applications.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.clickedOutside) }
        }) {
            outsideClickMonitors.append(global)
        }

        // Clicks in NotchDeck's own windows (settings, debug panel).
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel {
                    self.send(.clickedOutside)
                }
            }
            return event
        }) {
            outsideClickMonitors.append(local)
        }
    }

    private func removeOutsideClickMonitors() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors.removeAll()
    }

    // MARK: Attention peek

    private func updateAttentionPeekTimeout() {
        attentionPeekTask?.cancel()
        attentionPeekTask = nil
        guard machine.state == .peek, machine.isAttentionPeek else { return }
        attentionPeekTask = Task { [weak self] in
            try? await Task.sleep(for: Self.attentionPeekDuration)
            guard !Task.isCancelled else { return }
            self?.send(.peekTimedOut)
        }
    }

    // MARK: Screens and settings

    private func updateScreen() {
        let screens = NSScreen.screens
        let candidates = screens.map { NotchScreenSelector.Candidate(hasPhysicalNotch: $0.safeAreaInsets.top > 0) }

        guard let index = NotchScreenSelector.select(from: candidates, preference: settings.displayPreference) else {
            geometry = nil
            updatePanelVisibility()
            return
        }

        let newGeometry = NotchGeometry(screen: screens[index])
        guard newGeometry != geometry else { return }
        geometry = newGeometry
        model.update(state: machine.state, geometry: newGeometry)
        updatePanelFrame(animated: false)
        updateFullScreenCoverage()
        updatePanelVisibility()
        if let panel, panel.isVisible {
            // Keep the panel frontmost after a display change.
            panel.orderFrontRegardless()
        }
        hostingView?.reconcilePointerLocation()
    }

    // MARK: Full screen and visibility

    private func workspaceChanged() {
        updateFullScreenCoverage()
        fullScreenRecheckTask?.cancel()
        fullScreenRecheckTask = Task { [weak self] in
            try? await Task.sleep(for: Self.fullScreenRecheckDelay)
            guard !Task.isCancelled else { return }
            self?.updateFullScreenCoverage()
        }
    }

    /// Reads the window list only when the notch is virtual; a physical notch never hides.
    private func updateFullScreenCoverage() {
        let covered = if let geometry, !geometry.hasPhysicalNotch {
            FullScreenCoverage.isCovered(appKitScreenFrame: geometry.screenFrame)
        } else {
            false
        }
        guard covered != isFullScreenCovered else { return }
        isFullScreenCovered = covered
        updatePanelVisibility()
    }

    /// Shows or hides the panel. Hiding waits for a collapse animation to finish.
    private func updatePanelVisibility() {
        guard isStarted, let panel else { return }
        let visible = geometry.map {
            NotchVisibility.isVisible(
                state: machine.state,
                hasPhysicalNotch: $0.hasPhysicalNotch,
                isFullScreenCovered: isFullScreenCovered
            )
        } ?? false

        hideTask?.cancel()
        hideTask = nil

        if visible {
            guard !panel.isVisible else { return }
            panel.orderFrontRegardless()
            hostingView?.reconcilePointerLocation()
        } else if panel.isVisible {
            guard geometry != nil else {
                panel.orderOut(nil)
                return
            }
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: Self.shrinkDelay)
                guard !Task.isCancelled else { return }
                self?.panel?.orderOut(nil)
            }
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.stateMachineConfiguration
            _ = settings.displayPreference
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.machine.configuration = self.settings.stateMachineConfiguration
                self.updateScreen()
                self.observeSettings()
            }
        }
    }
}

extension NotchGeometry {
    @MainActor
    init(screen: NSScreen) {
        let visibleTopInset = screen.frame.maxY - screen.visibleFrame.maxY
        self = NotchGeometry.make(
            screenFrame: screen.frame,
            safeAreaTopInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            menuBarHeight: visibleTopInset > 0 ? visibleTopInset : NSStatusBar.system.thickness
        )
    }
}
