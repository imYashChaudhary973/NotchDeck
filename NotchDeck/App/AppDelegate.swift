import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When hosting unit tests, don't put UI on screen or start providers.
        guard !AppEnvironment.isRunningTests else { return }
        environment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }
}
