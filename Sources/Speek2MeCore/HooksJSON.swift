import Foundation

/// Adds and removes Speek2Me's handlers in the hooks JSON both Claude Code (`settings.json`) and
/// Codex (`hooks.json`) use: `hooks.<Event>[] -> {matcher?, hooks: [handler]}`.
public enum HooksJSON {
    public enum Error: Swift.Error, Equatable {
        case invalidJSON
    }

    public struct Handler: Equatable, Sendable {
        public var command: String
        public var timeout: Int
        public var async: Bool

        public init(command: String, timeout: Int = 5, async: Bool = true) {
            self.command = command
            self.timeout = timeout
            self.async = async
        }
    }

    public struct Group: Equatable, Sendable {
        public var event: String
        public var matcher: String?
        public var handler: Handler

        public init(event: String, matcher: String?, handler: Handler) {
            self.event = event
            self.matcher = matcher
            self.handler = handler
        }
    }

    /// Every handler Speek2Me installs has this in its command; that is how it finds them again.
    public static let commandMarker = "speek2me-hook"

    public static func isInstalled(_ data: Data?) throws -> Bool {
        let hooks = try object(data)["hooks"] as? [String: Any] ?? [:]
        return hooks.values.contains { event in
            (event as? [[String: Any]])?.contains(where: containsMarker) ?? false
        }
    }

    /// Appends one handler per group. A group whose event already has a Speek2Me handler is left
    /// alone, so running this twice changes nothing.
    public static func install(_ data: Data?, groups: [Group]) throws -> Data {
        var root = try object(data)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for group in groups {
            var eventGroups = hooks[group.event] as? [[String: Any]] ?? []
            guard !eventGroups.contains(where: containsMarker) else { continue }
            var handler: [String: Any] = ["type": "command", "command": group.handler.command, "timeout": group.handler.timeout]
            handler["async"] = group.handler.async
            if let index = eventGroups.firstIndex(where: { sameMatcher($0["matcher"] as? String, group.matcher) }) {
                var handlers = eventGroups[index]["hooks"] as? [[String: Any]] ?? []
                handlers.append(handler)
                eventGroups[index]["hooks"] = handlers
            } else {
                var newGroup: [String: Any] = ["hooks": [handler]]
                if let matcher = group.matcher { newGroup["matcher"] = matcher }
                eventGroups.append(newGroup)
            }
            hooks[group.event] = eventGroups
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    /// Drops Speek2Me's handlers, then any group or event left empty, and `hooks` itself if empty.
    public static func remove(_ data: Data?) throws -> Data {
        var root = try object(data)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            guard let eventGroups = value as? [[String: Any]] else { continue }
            let kept = eventGroups.compactMap { group -> [String: Any]? in
                var group = group
                let handlers = (group["hooks"] as? [[String: Any]] ?? []).filter { !isMarked($0) }
                guard !handlers.isEmpty else { return nil }
                group["hooks"] = handlers
                return group
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return try serialize(root)
    }

    public static func pretty(_ data: Data) throws -> String {
        String(decoding: try serialize(try object(data)), as: UTF8.self)
    }

    // MARK: - Helpers

    static func object(_ data: Data?) throws -> [String: Any] {
        guard let data, !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Error.invalidJSON }
        return root
    }

    static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private static func sameMatcher(_ a: String?, _ b: String?) -> Bool {
        (a ?? "") == (b ?? "")
    }

    private static func isMarked(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(commandMarker) ?? false
    }

    private static func containsMarker(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]])?.contains(where: isMarked) ?? false
    }
}
