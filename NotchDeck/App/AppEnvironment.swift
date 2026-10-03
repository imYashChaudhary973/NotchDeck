import Foundation

/// Creates and wires the app's long-lived objects.
///
/// This is the composition root: register activity providers in `start()`.
@MainActor
final class AppEnvironment {
    let settings: AppSettings
    let launchAtLogin: LaunchAtLoginService
    let engine: ActivityEngine
    let notchController: NotchController
    private let windows = AuxiliaryWindowPresenter()

    #if DEBUG
    let debugProvider = DebugActivityProvider()
    #endif

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        settings = AppSettings()
        launchAtLogin = LaunchAtLoginService()
        engine = ActivityEngine()
        notchController = NotchController(engine: engine, settings: settings)
        notchController.onOpenSettings = { [weak self] in self?.showSettings() }
    }

    func start() {
        #if DEBUG
        engine.register(debugProvider)
        #endif
        notchController.start()

        #if DEBUG
        // Launch with `-NotchDeckShowDebugPanel YES` to open the debug panel immediately.
        if UserDefaults.standard.bool(forKey: "NotchDeckShowDebugPanel") {
            showDebugPanel()
        }
        #endif
    }

    func stop() {
        for source in engine.registeredSources {
            engine.unregister(source)
        }
        notchController.stop()
    }

    func showSettings() {
        notchController.send(.dismiss)
        launchAtLogin.refresh()
        windows.show(id: "settings", title: "NotchDeck Settings") {
            SettingsView(settings: self.settings, launchAtLogin: self.launchAtLogin)
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
