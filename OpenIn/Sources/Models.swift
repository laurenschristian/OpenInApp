import AppKit

struct Browser: Identifiable, Codable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }

    var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func open(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
    }
}

struct Rule: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var pattern: String
    var isRegex: Bool = false
    var sourceAppBundleID: String?
    var targetBrowserID: String
    var enabled: Bool = true

    func matches(url: URL, sourceApp: String?) -> Bool {
        guard enabled else { return false }

        if let requiredSource = sourceAppBundleID, !requiredSource.isEmpty {
            guard sourceApp == requiredSource else { return false }
        }

        let host = url.host ?? ""
        let fullURL = url.absoluteString

        if isRegex {
            return (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))
                .map { $0.firstMatch(in: fullURL, range: NSRange(fullURL.startIndex..., in: fullURL)) != nil } ?? false
        }

        // Glob-style matching
        let p = pattern.lowercased()
        let h = host.lowercased()
        let u = fullURL.lowercased()

        if p.hasPrefix("*.") {
            let suffix = String(p.dropFirst(2))
            return h.hasSuffix(suffix) || h == suffix
        }
        if p.contains("*") {
            let parts = p.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
            var searchIn = u
            for part in parts {
                guard !part.isEmpty else { continue }
                guard let range = searchIn.range(of: part) else { return false }
                searchIn = String(searchIn[range.upperBound...])
            }
            return true
        }
        return h == p || u.contains(p)
    }
}

struct AppConfig: Codable {
    var rules: [Rule] = []
    var defaultBrowserID: String?
    var showPickerOnNoMatch: Bool = true
    var hideAfterPick: Bool = true

    static let configURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/openin")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }
}
