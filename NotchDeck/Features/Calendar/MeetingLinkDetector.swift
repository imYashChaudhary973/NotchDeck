import Foundation

/// Finds a video-call link in an event's URL, location or notes.
///
/// Only links to known meeting services are used (plus a location that is nothing but a web
/// link), so Join never opens an unrelated document or tracking link. Only `https` and `http`
/// links are accepted.
enum MeetingLinkDetector {
    private struct Service {
        let host: String
        /// Path prefixes that identify a meeting link; empty matches any path.
        var paths: [String] = []
    }

    private static let services = [
        Service(host: "zoom.us", paths: ["/j/", "/my/", "/w/", "/s/", "/wc/"]),
        Service(host: "zoomgov.com", paths: ["/j/", "/my/", "/w/", "/s/"]),
        Service(host: "meet.google.com"),
        Service(host: "teams.microsoft.com", paths: ["/l/meetup-join/", "/meet/"]),
        Service(host: "teams.live.com", paths: ["/meet/"]),
        Service(host: "webex.com"),
        Service(host: "facetime.apple.com", paths: ["/join"]),
        Service(host: "chime.aws"),
        Service(host: "meet.jit.si"),
        Service(host: "whereby.com"),
        Service(host: "gotomeeting.com", paths: ["/join/"]),
        Service(host: "meet.goto.com"),
        Service(host: "bluejeans.com"),
        Service(host: "app.slack.com", paths: ["/huddle/"]),
    ]

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The best meeting link in the event, checking its URL, then location, then notes.
    static func meetingURL(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isMeetingLink(url) { return url }
        for text in [location, notes].compactMap({ $0 }) {
            if let link = links(in: text).first(where: isMeetingLink) { return link }
        }
        // A location that is just a web link is very likely the call.
        if let location = location?.trimmingCharacters(in: .whitespacesAndNewlines),
           let link = links(in: location).first, isWebLink(link),
           link.absoluteString.count >= location.count - 2 {
            return link
        }
        return nil
    }

    static func isMeetingLink(_ url: URL) -> Bool {
        guard isWebLink(url), let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        return services.contains { service in
            (host == service.host || host.hasSuffix("." + service.host))
                && (service.paths.isEmpty || service.paths.contains { path.hasPrefix($0) })
        }
    }

    private static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private static func links(in text: String) -> [URL] {
        guard let detector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }
}
