import AppKit

final class RulesEngine: ObservableObject {
    static let shared = RulesEngine()
    @Published var config: AppConfig

    init() {
        self.config = AppConfig.load()
    }

    func save() {
        objectWillChange.send()
        config.save()
    }

    func resolve(url: URL, sourceApp: String?) -> Browser? {
        let bm = BrowserManager.shared

        for rule in config.rules where rule.enabled {
            if rule.matches(url: url, sourceApp: sourceApp) {
                return bm.browser(for: rule.targetBrowserID)
            }
        }

        return nil
    }

    func recordURL(_ url: URL, browserID: String, sourceApp: String?) {
        let browserName = BrowserManager.shared.browser(for: browserID)?.name ?? browserID
        config.addRecentURL(url, browserID: browserID, sourceApp: sourceApp)
        config.recordStat(url: url, browserName: browserName)
        save()
    }

    var recentURLs: [RecentURL] {
        config.recentURLs
    }

    func lastUsedBrowser(forHost host: String) -> String? {
        config.recentURLs.first { URL(string: $0.url)?.host == host }?.browserID
    }
}
