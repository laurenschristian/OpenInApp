import AppKit

final class BrowserManager: ObservableObject {
    static let shared = BrowserManager()
    @Published var browsers: [Browser] = []
    private let selfBundleID = Bundle.main.bundleIdentifier ?? "com.lgn.openin"

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

        // Sort: Safari first, then Chrome, then alphabetical
        result.sort { a, b in
            let order = ["com.apple.safari": 0, "com.google.chrome": 1, "org.mozilla.firefox": 2]
            let oa = order[a.bundleID.lowercased()] ?? 99
            let ob = order[b.bundleID.lowercased()] ?? 99
            if oa != ob { return oa < ob }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        DispatchQueue.main.async {
            self.browsers = result
        }
    }

    func browser(for id: String) -> Browser? {
        browsers.first { $0.bundleID.lowercased() == id.lowercased() }
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
}
