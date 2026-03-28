import AppKit

struct Browser: Identifiable, Codable, Hashable {
    let bundleID: String
    let name: String
    var profileDir: String?
    var profileName: String?

    var id: String {
        if let profileDir = profileDir {
            return "\(bundleID)::\(profileDir)"
        }
        return bundleID
    }

    var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func open(_ url: URL, profile: String? = nil, incognito: Bool = false) {
        let effectiveProfile = profile ?? profileDir

        if effectiveProfile != nil || incognito {
            openWithArgs(url, profile: effectiveProfile, incognito: incognito)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = AppConfig.load().activateBrowser
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
    }

    private func openWithArgs(_ url: URL, profile: String?, incognito: Bool) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let bid = bundleID.lowercased()

        guard let bundle = Bundle(url: appURL),
              let execName = bundle.executableURL?.lastPathComponent else {
            open(url)
            return
        }
        let execPath = appURL.appendingPathComponent("Contents/MacOS").path

        var args: [String] = []

        if bid.contains("chrome") || bid.contains("chromium") || bid.contains("brave") || bid.contains("edge") || bid.contains("vivaldi") || bid.contains("arc") {
            if incognito { args.append("--incognito") }
            if let profile = profile { args.append("--profile-directory=\(profile)") }
        } else if bid.contains("firefox") {
            if incognito { args.append("-private-window") }
            if let profile = profile { args.append(contentsOf: ["-P", profile]) }
        }

        args.append(url.absoluteString)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "\(execPath)/\(execName)")
        process.arguments = args
        try? process.run()

        // Activate the browser after launching via Process
        if AppConfig.load().activateBrowser {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleID).first {
                    app.activate()
                }
            }
        }
    }
}

struct Rule: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var pattern: String
    var isRegex: Bool = false
    var sourceAppBundleID: String?
    var targetBrowserID: String
    var browserProfile: String?
    var openIncognito: Bool = false
    var enabled: Bool = true

    func matches(url: URL, sourceApp: String?) -> Bool {
        guard enabled else { return false }

        if let requiredSource = sourceAppBundleID, !requiredSource.isEmpty {
            guard let source = sourceApp, source.lowercased() == requiredSource.lowercased() else { return false }
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

struct URLRewriteRule: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var enabled: Bool = true
    var type: RewriteType

    enum RewriteType: Codable {
        case stripQueryParams([String])
        case forceHTTPS
        case regexReplace(pattern: String, replacement: String)
    }
}

struct RecentURL: Codable, Identifiable {
    var id: String = UUID().uuidString
    let url: String
    let browserID: String
    let timestamp: Date
    let sourceApp: String?
}

struct AppConfig: Codable {
    struct Stats: Codable {
        var totalURLsRouted: Int = 0
        var domainCounts: [String: Int] = [:]
        var browserCounts: [String: Int] = [:]
    }

    var pinnedBrowserIDs: [String] = []
    var rules: [Rule] = []
    var rewriteRules: [URLRewriteRule] = []
    var defaultBrowserID: String?
    var defaultBrowserProfile: String?
    var showPickerOnNoMatch: Bool = true
    var hideAfterPick: Bool = true
    var activateBrowser: Bool = true
    var launchAtLogin: Bool = false
    var recentURLs: [RecentURL] = []
    var stripTrackingParams: Bool = true
    var forceHTTPS: Bool = false
    var showNotifications: Bool = true
    var stats: Stats = Stats()

    static let defaultTrackingParams = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "gclsrc", "dclid", "gb_budget_id",
        "msclkid", "mc_cid", "mc_eid",
        "ref", "referer", "referrer",
        "igshid", "twclid",
        "yclid", "ymclid",
        "_hsenc", "_hsmi", "hsCtaTracking",
        "vero_id", "mkt_tok",
        "s_cid", "sc_cmp", "sc_uid"
    ]

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

    mutating func recordStat(url: URL, browserName: String) {
        stats.totalURLsRouted += 1
        let host = url.host ?? "unknown"
        stats.domainCounts[host, default: 0] += 1
        stats.browserCounts[browserName, default: 0] += 1
    }

    mutating func addRecentURL(_ url: URL, browserID: String, sourceApp: String?) {
        let entry = RecentURL(url: url.absoluteString, browserID: browserID, timestamp: Date(), sourceApp: sourceApp)
        recentURLs.insert(entry, at: 0)
        if recentURLs.count > 20 { recentURLs = Array(recentURLs.prefix(20)) }
    }

    func rewriteURL(_ url: URL) -> URL {
        var urlString = url.absoluteString

        // Force HTTPS
        if forceHTTPS && urlString.hasPrefix("http://") {
            urlString = "https://" + urlString.dropFirst(7)
        }

        guard var components = URLComponents(string: urlString) else { return url }

        // Strip tracking params (case-insensitive comparison)
        if stripTrackingParams, let queryItems = components.queryItems {
            let trackingSet = Set(Self.defaultTrackingParams.map { $0.lowercased() })
            let filtered = queryItems.filter { item in
                !trackingSet.contains(item.name.lowercased())
            }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        // Custom rewrite rules
        for rule in rewriteRules where rule.enabled {
            switch rule.type {
            case .stripQueryParams(let params):
                if let queryItems = components.queryItems {
                    let filtered = queryItems.filter { !params.contains($0.name) }
                    components.queryItems = filtered.isEmpty ? nil : filtered
                }
            case .forceHTTPS:
                components.scheme = "https"
            case .regexReplace(let pattern, let replacement):
                if var str = components.string,
                   let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    str = regex.stringByReplacingMatches(in: str, range: NSRange(str.startIndex..., in: str), withTemplate: replacement)
                    if let newComponents = URLComponents(string: str) {
                        components = newComponents
                    }
                }
            }
        }

        return components.url ?? url
    }
}
