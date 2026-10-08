import AppKit
import Foundation

/// Creates and wires the app's long-lived objects.
///
/// This is the composition root: activity providers are created here and registered with the
/// engine in `start()`. Each feature is registered only while it is enabled in Settings.
@MainActor
final class AppEnvironment {
    let settings: AppSettings
    let launchAtLogin: LaunchAtLoginService
    let engine: ActivityEngine
    let notchController: NotchController
    private let windows = AuxiliaryWindowPresenter()

    let timers: TimerProvider
    let keepAwake: KeepAwakeProvider
    let systemMetrics: SystemMetricsProvider
    let audio: AudioProvider
    let quickActions: QuickActionsProvider
    let music: MusicProvider
    let calendar: CalendarProvider

    #if DEBUG
    let debugProvider = DebugActivityProvider()
    #endif

    private var isStarted = false

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        let settings = AppSettings()
        self.settings = settings
        launchAtLogin = LaunchAtLoginService()
        engine = ActivityEngine()
        notchController = NotchController(engine: engine, settings: settings)

        timers = TimerProvider()
        keepAwake = KeepAwakeProvider()
        systemMetrics = SystemMetricsProvider()
        audio = AudioProvider(scrollAdjustsVolume: { settings.scrollAdjustsVolume })
        quickActions = QuickActionsProvider(actions: Self.makeQuickActions(settings: settings, timers: timers, keepAwake: keepAwake))
        music = MusicProvider(players: [
            ScriptableMediaProvider(app: AppleMusicApp()),
            ScriptableMediaProvider(app: SpotifyApp()),
        ])
        calendar = CalendarProvider(store: EventKitCalendarStore(), configuration: { settings.calendarConfiguration })

        notchController.onOpenSettings = { [weak self] in self?.showSettings() }
        timers.onRequestCustomDuration = { [weak self] in self?.showCustomTimer() }
        timers.onFinish = { _ in
            if settings.timerPlaysSound { NSSound(named: "Glass")?.play() }
        }
        keepAwake.onChange = { [weak self] in self?.quickActions.refresh() }
    }

    func start() {
        isStarted = true
        #if DEBUG
        engine.register(debugProvider)
        #endif
        applyFeatureSettings(userInitiated: false)
        observeFeatureSettings()
        observeCalendarSettings()
        notchController.start()

        #if DEBUG
        // Launch with `-NotchDeckShowDebugPanel YES` to open the debug panel immediately.
        if UserDefaults.standard.bool(forKey: "NotchDeckShowDebugPanel") {
            showDebugPanel()
        }
        #endif
    }

    func stop() {
        isStarted = false
        // Unregistering stops providers without discarding saved state: running timers and an
        // active Keep Awake session are restored on the next launch.
        for source in engine.registeredSources {
            engine.unregister(source)
        }
        notchController.stop()
    }

    // MARK: Features

    private func provider(for feature: Feature) -> any ActivityProvider {
        switch feature {
        case .timers: timers
        case .keepAwake: keepAwake
        case .systemMetrics: systemMetrics
        case .audio: audio
        case .quickActions: quickActions
        case .music: music
        case .calendar: calendar
        }
    }

    /// Registers enabled features and unregisters disabled ones.
    /// - Parameter userInitiated: The user just changed a toggle (rather than the app launching), so
    ///   it is the right moment to ask for a permission the feature needs.
    private func applyFeatureSettings(userInitiated: Bool) {
        for feature in Feature.allCases {
            let provider = provider(for: feature)
            let isRegistered = engine.isRegistered(provider.source)
            if settings.isEnabled(feature), !isRegistered {
                engine.register(provider)
                // Ask for calendar access when the user turns Calendar on, never at launch.
                if feature == .calendar, userInitiated {
                    calendar.requestAccess()
                }
            } else if !settings.isEnabled(feature), isRegistered {
                // Turning a feature off ends what it was doing, rather than resuming it next launch.
                switch feature {
                case .timers: timers.cancelAll()
                case .keepAwake: keepAwake.turnOff()
                case .systemMetrics, .audio, .quickActions, .music, .calendar: break
                }
                engine.unregister(provider.source)
            }
        }
        // Timer and Keep Awake tiles depend on their features being on.
        quickActions.refresh()
    }

    private func observeFeatureSettings() {
        withObservationTracking {
            for feature in Feature.allCases { _ = settings.isEnabled(feature) }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.applyFeatureSettings(userInitiated: true)
                self.observeFeatureSettings()
            }
        }
    }

    /// Reloads events when the look-ahead, notch timing or calendar selection changes.
    private func observeCalendarSettings() {
        withObservationTracking {
            _ = settings.calendarConfiguration
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                if self.engine.isRegistered(self.calendar.source) {
                    self.calendar.reload()
                }
                self.observeCalendarSettings()
            }
        }
    }

    private static func makeQuickActions(
        settings: AppSettings,
        timers: TimerProvider,
        keepAwake: KeepAwakeProvider
    ) -> [any QuickAction] {
        [
            ClosureQuickAction(
                id: "startTimer", title: "25m Timer", symbolName: "timer",
                isAvailable: { settings.timersEnabled },
                action: { timers.startTimer(duration: 25 * 60) }
            ),
            ClosureQuickAction(
                id: "keepAwake", title: "Keep Awake", symbolName: "cup.and.saucer.fill",
                isAvailable: { settings.keepAwakeEnabled },
                isActiveState: { keepAwake.isActive },
                action: { keepAwake.toggle() }
            ),
            OpenFolderQuickAction.downloads(),
            OpenFolderQuickAction.applications(),
            OpenApplicationQuickAction.activityMonitor(),
            OpenApplicationQuickAction.screenshot(),
            LockScreenQuickAction(),
            OpenApplicationQuickAction.screenSaver(),
        ]
    }

    // MARK: Windows

    func showSettings() {
        notchController.send(.dismiss)
        launchAtLogin.refresh()
        calendar.refreshAuthorization()
        windows.show(id: "settings", title: "NotchDeck Settings") {
            SettingsView(settings: self.settings, launchAtLogin: self.launchAtLogin, calendar: self.calendar)
        }
    }

    func showCustomTimer() {
        notchController.send(.dismiss)
        windows.show(id: "customTimer", title: "Custom Timer") {
            CustomTimerView { [weak self] duration, label in
                self?.timers.startTimer(duration: duration, label: label)
                self?.windows.close(id: "customTimer")
            } cancel: { [weak self] in
                self?.windows.close(id: "customTimer")
            }
        }
    }

    #if DEBUG
    func showDebugPanel() {
        windows.show(id: "debug", title: "Debug Activities") {
            DebugPanelView(provider: self.debugProvider, engine: self.engine, notch: self.notchController)
        }
    }
    #endif
}
