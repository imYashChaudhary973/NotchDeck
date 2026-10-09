#if DEBUG
import Foundation

/// Developer bridge messages for the debug panel. They are handed to the real
/// `DeveloperActivityProvider` (`receive(_:)`), exactly as messages from `notchctl` are, so
/// several agents can be tried at once without Claude Code or Codex.
enum DebugAgentMessages {
    private static let claude = "claude-code"
    private static let codex = "codex"
    private static let tool = "my-tool"
    /// A folder that exists, so Open Workspace and Open Terminal have somewhere to go.
    private static let workspace = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)

    static let claudeWorking = DeveloperBridgeMessage(
        provider: claude, session: "debug-claude", project: "Rove", workspace: workspace,
        task: "Implement tab management", status: .working, terminal: "com.apple.Terminal"
    )

    static let claudeNeedsPermission = DeveloperBridgeMessage(
        provider: claude, session: "debug-claude", project: "Rove", workspace: workspace,
        status: .needsPermission, message: "Claude needs your permission to use Bash", terminal: "com.apple.Terminal"
    )

    static let claudeFinished = DeveloperBridgeMessage(
        provider: claude, session: "debug-claude", project: "Rove", workspace: workspace, status: .completed
    )

    static let codexWorking = DeveloperBridgeMessage(
        provider: codex, session: "debug-codex", project: "ZenVoice", workspace: workspace,
        task: "Fix the audio pipeline", status: .runningCommand, message: "swift test", progress: 0.4
    )

    static let codexNeedsInput = DeveloperBridgeMessage(
        provider: codex, session: "debug-codex", project: "ZenVoice", workspace: workspace,
        status: .needsInput, message: "Which audio format should I use?"
    )

    static let agentFailed = DeveloperBridgeMessage(
        provider: tool, session: "debug-tool", project: "NotchApp", workspace: workspace,
        task: "Release build", status: .failed, message: "Build failed: 3 errors"
    )

    /// Ends every debug session at once.
    static let endAll = [(claude, "debug-claude"), (codex, "debug-codex"), (tool, "debug-tool")].map { provider, session in
        DeveloperBridgeMessage(type: .end, provider: provider, session: session)
    }
}
#endif
