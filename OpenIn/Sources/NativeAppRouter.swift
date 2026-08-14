import AppKit

/// Routes links for services with a native macOS app straight to that app,
/// skipping the browser entirely. Only fires when the app is installed.
enum NativeAppRouter {
    struct Target {
        let name: String
        let bundleID: String
        let hostPatterns: [String]
    }

    static let targets: [Target] = [
        Target(name: "Spotify", bundleID: "com.spotify.client", hostPatterns: ["open.spotify.com"]),
        Target(name: "Zoom", bundleID: "us.zoom.xos", hostPatterns: ["*.zoom.us", "zoom.us"]),
        Target(name: "Microsoft Teams", bundleID: "com.microsoft.teams2", hostPatterns: ["teams.microsoft.com", "teams.live.com"]),
        Target(name: "Figma", bundleID: "com.figma.Desktop", hostPatterns: ["*.figma.com", "figma.com"]),
        Target(name: "Notion", bundleID: "notion.id", hostPatterns: ["*.notion.so", "notion.so"]),
        Target(name: "Discord", bundleID: "com.hnc.Discord", hostPatterns: ["discord.com", "discord.gg"]),
        Target(name: "Linear", bundleID: "com.linear", hostPatterns: ["linear.app"]),
        Target(name: "Telegram", bundleID: "ru.keepcoder.Telegram", hostPatterns: ["t.me"]),
    ]

    static func installedTargets() -> [Target] {
        targets.filter { appURL(for: $0) != nil }
    }

    static func target(for url: URL, config: AppConfig) -> Target? {
        guard config.nativeAppRouting else { return nil }
        let host = (url.host ?? "").lowercased()
        guard !host.isEmpty else { return nil }

        for target in targets where !config.disabledNativeApps.contains(target.bundleID) {
            guard matches(host: host, patterns: target.hostPatterns), appURL(for: target) != nil else { continue }
            return target
        }
        return nil
    }

    static func appURL(for target: Target) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID)
    }

    private static func matches(host: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst(2))
                if host == suffix || host.hasSuffix("." + suffix) { return true }
            } else if host == pattern {
                return true
            }
        }
        return false
    }
}
