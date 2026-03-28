import AppKit

final class BrowserManager: ObservableObject {
    static let shared = BrowserManager()
    @Published var browsers: [Browser] = []
    @Published var browserOptions: [Browser] = []
    private let selfBundleID = Bundle.main.bundleIdentifier ?? "com.lgn.openin"

    private static let chromiumProfilePaths: [String: String] = [
        "com.brave.browser": "BraveSoftware/Brave-Browser",
        "com.google.chrome": "Google/Chrome",
        "org.chromium.chromium": "Chromium",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.vivaldi": "Vivaldi",
    ]

    init() {
        reload()
    }

    func reload() {
        var seen = Set<String>()
        var result: [Browser] = []

        let handlers = LSCopyAllHandlersForURLScheme("https" as CFString)?.takeRetainedValue() as? [String] ?? []
        for bundleID in handlers {
            let bid = bundleID.lowercased()
            guard bid != selfBundleID.lowercased(), !seen.contains(bid) else { continue }
            seen.insert(bid)

            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            let name = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
            result.append(Browser(bundleID: bundleID, name: name))
        }

        result.sort { a, b in
            let order = ["com.apple.safari": 0, "com.google.chrome": 1, "org.mozilla.firefox": 2]
            let oa = order[a.bundleID.lowercased()] ?? 99
            let ob = order[b.bundleID.lowercased()] ?? 99
            if oa != ob { return oa < ob }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        var options: [Browser] = []
        for browser in result {
            let profiles = detectProfiles(for: browser)
            if profiles.isEmpty {
                options.append(browser)
            } else {
                for (dir, displayName) in profiles {
                    options.append(Browser(
                        bundleID: browser.bundleID,
                        name: "\(browser.name) (\(displayName))",
                        profileDir: dir,
                        profileName: displayName
                    ))
                }
            }
        }

        if Thread.isMainThread {
            self.browsers = result
            self.browserOptions = options
        } else {
            DispatchQueue.main.async {
                self.browsers = result
                self.browserOptions = options
            }
        }
    }

    func browser(for id: String) -> Browser? {
        browsers.first { $0.bundleID.lowercased() == id.lowercased() }
    }

    func browserOption(for id: String) -> Browser? {
        browserOptions.first { $0.id.lowercased() == id.lowercased() }
    }

    func setAsDefaultBrowser() {
        LSSetDefaultHandlerForURLScheme("http" as CFString, selfBundleID as CFString)
        LSSetDefaultHandlerForURLScheme("https" as CFString, selfBundleID as CFString)
    }

    var isDefaultBrowser: Bool {
        guard let current = LSCopyDefaultHandlerForURLScheme("https" as CFString)?.takeRetainedValue() as String? else {
            return false
        }
        return current.lowercased() == selfBundleID.lowercased()
    }

    // MARK: - Profile Detection

    private func detectProfiles(for browser: Browser) -> [(dir: String, name: String)] {
        let bid = browser.bundleID.lowercased()

        if let chromiumDir = Self.chromiumProfilePaths[bid] {
            return detectChromiumProfiles(appSupportSubdir: chromiumDir)
        }

        if bid == "org.mozilla.firefox" {
            return detectFirefoxProfiles()
        }

        return []
    }

    private func detectChromiumProfiles(appSupportSubdir: String) -> [(dir: String, name: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localStateURL = home
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(appSupportSubdir)
            .appendingPathComponent("Local State")

        guard let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return []
        }

        var profiles: [(String, String)] = []
        for (dirName, value) in infoCache {
            guard let info = value as? [String: Any] else { continue }
            let displayName = info["name"] as? String ?? dirName
            profiles.append((dirName, displayName))
        }

        profiles.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
        return profiles
    }

    private func detectFirefoxProfiles() -> [(dir: String, name: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let iniURL = home.appendingPathComponent("Library/Application Support/Firefox/profiles.ini")

        guard let contents = try? String(contentsOf: iniURL, encoding: .utf8) else { return [] }

        var profiles: [(String, String)] = []
        var currentName: String?
        var currentPath: String?
        var currentIsRelative: Bool?

        func flush() {
            if let name = currentName, let path = currentPath {
                let dir = (currentIsRelative == true) ? path : path
                profiles.append((dir, name))
            }
            currentName = nil
            currentPath = nil
            currentIsRelative = nil
        }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[Profile") {
                flush()
                continue
            }
            if trimmed.hasPrefix("[") {
                flush()
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "Name": currentName = val
            case "Path": currentPath = val
            case "IsRelative": currentIsRelative = (val == "1")
            default: break
            }
        }
        flush()

        return profiles
    }
}
