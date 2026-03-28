import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasLaunched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        BrowserManager.shared.reload()

        // Sync login item state
        syncLoginItem()

        // Show onboarding on first launch
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                OnboardingWindowController.shared.show()
            }
        }

        hasLaunched = true
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        // Extract source app from the Apple Event sender
        let sourceApp = extractSourceApp(from: event)

        routeURL(url, sourceApp: sourceApp)
    }

    private func extractSourceApp(from event: NSAppleEventDescriptor) -> String? {
        // Get the sender's address descriptor
        guard let senderDesc = event.attributeDescriptor(forKeyword: AEKeyword(keyAddressAttr)) else { return nil }

        // Try to get bundle ID from the process
        if senderDesc.descriptorType == typeApplicationBundleID {
            return senderDesc.stringValue
        }

        // Try ProcessSerialNumber approach
        if senderDesc.descriptorType == typeKernelProcessID {
            let pid = senderDesc.int32Value
            if let app = NSRunningApplication(processIdentifier: pid) {
                return app.bundleIdentifier
            }
        }

        // Try getting the PID from AppleEvent attributes
        if let pidDesc = event.attributeDescriptor(forKeyword: keySenderPIDAttr) {
            let pid = pidDesc.int32Value
            if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
                return app.bundleIdentifier
            }
        }

        return nil
    }

    func routeURL(_ url: URL, sourceApp: String?) {
        let engine = RulesEngine.shared
        let bm = BrowserManager.shared

        // Rewrite URL first (strip tracking, force HTTPS, etc.)
        let cleanURL = engine.config.rewriteURL(url)

        // Try rules
        if let browser = engine.resolve(url: cleanURL, sourceApp: sourceApp) {
            let rule = engine.config.rules.first { $0.matches(url: cleanURL, sourceApp: sourceApp) && $0.enabled }
            browser.open(cleanURL, profile: rule?.browserProfile, incognito: rule?.openIncognito ?? false)
            engine.recordURL(cleanURL, browserID: browser.bundleID, sourceApp: sourceApp)
            return
        }

        // If picker is disabled and no rule matched, open in system default
        if !engine.config.showPickerOnNoMatch {
            NSWorkspace.shared.open(cleanURL)
            return
        }

        // Show picker
        let browsers = bm.browsers
        guard !browsers.isEmpty else {
            NSWorkspace.shared.open(cleanURL)
            return
        }

        PickerWindowController.shared.show(url: cleanURL, browsers: browsers, sourceApp: sourceApp) { chosen in
            if let browser = chosen {
                browser.open(cleanURL)
                engine.recordURL(cleanURL, browserID: browser.bundleID, sourceApp: sourceApp)
            }
        }
    }

    func syncLoginItem() {
        let config = RulesEngine.shared.config
        if config.launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if hasLaunched {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        return false
    }
}

// Key constants not available in Swift
private let keySenderPIDAttr = AEKeyword(0x736E6472) // 'sndr' — not always available, but worth trying
