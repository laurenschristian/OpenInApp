import AppKit

final class RulesEngine: ObservableObject {
    static let shared = RulesEngine()
    @Published var config: AppConfig

    init() {
        self.config = AppConfig.load()
    }

    func save() {
        config.save()
    }

    func resolve(url: URL, sourceApp: String?) -> Browser? {
        let bm = BrowserManager.shared

        // Check rules in order
        for rule in config.rules where rule.enabled {
            if rule.matches(url: url, sourceApp: sourceApp) {
                return bm.browser(for: rule.targetBrowserID)
            }
        }

        // If no rule matched, use default browser (if set and picker disabled)
        if !config.showPickerOnNoMatch, let defaultID = config.defaultBrowserID {
            return bm.browser(for: defaultID)
        }

        return nil // Show picker
    }
}
