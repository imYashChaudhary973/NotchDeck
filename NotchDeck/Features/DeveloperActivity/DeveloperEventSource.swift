import Foundation

/// Delivers developer activity messages to `DeveloperActivityProvider`.
///
/// `DeveloperBridgeServer` (the local socket `notchctl` talks to) is the real source; tests use a
/// fake. The provider starts the source when the feature is registered and stops it when it is
/// unregistered, so nothing listens while the feature is off.
@MainActor
protocol DeveloperEventSource: AnyObject {
    /// Starts listening. Messages of type `event` and `end` arrive validated, on the main actor;
    /// pings are answered by the source itself.
    func start(onMessage: @escaping @MainActor (DeveloperBridgeMessage) -> Void) throws
    /// Stops listening and releases every resource (socket, file).
    func stop()
}
