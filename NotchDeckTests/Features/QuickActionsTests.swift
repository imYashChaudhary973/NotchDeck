import Foundation
import Testing
@testable import NotchDeck

@MainActor
final class FakeWorkspace: WorkspaceOpening {
    var installed: [String: URL] = [:]
    private(set) var opened: [URL] = []

    func open(_ url: URL) { opened.append(url) }
    func applicationURL(bundleIdentifier: String) -> URL? { installed[bundleIdentifier] }
}

@MainActor
struct QuickActionsTests {
    let engine = ActivityEngine(schedulesExpiry: false)
    let key = ActivityKey(source: ActivitySource(rawValue: "quickActions"), id: QuickActionsProvider.activityID)

    private var items: [ActionItem] {
        guard case .actions(let content) = engine.activity(for: key)?.presentation.content else { return [] }
        return content.items
    }

    @Test func onlyAvailableActionsAreShown() {
        let workspace = FakeWorkspace()
        workspace.installed["com.apple.ActivityMonitor"] = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        engine.register(QuickActionsProvider(actions: [
            OpenApplicationQuickAction.activityMonitor(workspace: workspace),
            OpenApplicationQuickAction.screenshot(workspace: workspace),
            LockScreenQuickAction(),
        ]))

        #expect(items.map(\.actionID) == ["openActivityMonitor"])
        #expect(engine.activity(for: key)?.placement == .commandCenter)
        #expect(engine.resolution.primary == nil)
    }

    @Test func lockScreenIsUnavailableBecauseThereIsNoPublicAPI() {
        guard case .unavailable = LockScreenQuickAction().availability else {
            Issue.record("Lock Screen must not claim to be available")
            return
        }
    }

    @Test func performingAnActionRunsItAndRefreshesTheGrid() {
        var isOn = false
        let provider = QuickActionsProvider(actions: [
            ClosureQuickAction(id: "toggle", title: "Toggle", symbolName: "bolt", isActiveState: { isOn }, action: { isOn.toggle() }),
        ])
        engine.register(provider)
        #expect(items.first?.isActive == false)

        engine.perform(actionID: "toggle", on: key)

        #expect(isOn)
        #expect(items.first?.isActive == true)
    }

    @Test func unavailableActionsCannotBePerformed() {
        var ran = false
        let provider = QuickActionsProvider(actions: [
            ClosureQuickAction(id: "off", title: "Off", symbolName: "bolt", isAvailable: { false }, action: { ran = true }),
        ])
        engine.register(provider)

        engine.perform(actionID: "off", on: key)

        #expect(!ran)
        #expect(engine.activity(for: key) == nil)
    }

    @Test func refreshReflectsChangedAvailability() {
        var timersOn = true
        let provider = QuickActionsProvider(actions: [
            ClosureQuickAction(id: "timer", title: "Timer", symbolName: "timer", isAvailable: { timersOn }, action: {}),
        ])
        engine.register(provider)
        #expect(items.count == 1)

        timersOn = false
        provider.refresh()

        #expect(engine.activity(for: key) == nil)
    }

    @Test func folderAndAppActionsOpenThroughTheWorkspace() {
        let workspace = FakeWorkspace()
        let app = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        workspace.installed["com.apple.screenshot.launcher"] = app
        let downloads = OpenFolderQuickAction.downloads(workspace: workspace)

        downloads.perform()
        OpenApplicationQuickAction.screenshot(workspace: workspace).perform()

        #expect(workspace.opened.first?.lastPathComponent == "Downloads")
        #expect(workspace.opened.last == app)
    }
}
