import SwiftUI

/// Application entry point.
///
/// NotchDeck is an accessory (menu-bar) app: no Dock icon and no main window
/// (`LSUIElement`). The notch panel is managed by `NotchController`; the menu bar
/// item is the entry point for Settings and Quit.
@main
struct NotchDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(environment: appDelegate.environment)
        } label: {
            Image(systemName: "menubar.rectangle")
                .accessibilityLabel("NotchDeck")
        }
    }
}

private struct MenuBarContent: View {
    let environment: AppEnvironment

    var body: some View {
        if environment.settings.timersEnabled {
            Menu("Start Timer") {
                ForEach(TimerRules.presets, id: \.self) { duration in
                    Button(TimerRules.durationLabel(duration)) {
                        environment.timers.startTimer(duration: duration)
                    }
                }
                Divider()
                Button("Custom…") {
                    environment.showCustomTimer()
                }
            }
        }

        if environment.settings.keepAwakeEnabled {
            Menu("Keep Awake") {
                ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                    Button(duration.title) {
                        environment.keepAwake.turnOn(for: duration)
                    }
                }
                Divider()
                Button("Turn Off") {
                    environment.keepAwake.turnOff()
                }
            }
        }

        Divider()

        Button("Settings…") {
            environment.showSettings()
        }
        .keyboardShortcut(",")

        #if DEBUG
        Button("Debug Activities…") {
            environment.showDebugPanel()
        }
        .keyboardShortcut("d", modifiers: [.command, .option])
        #endif

        Divider()

        Button("Quit NotchDeck") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
