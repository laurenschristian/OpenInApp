import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for URL events immediately
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Ensure browsers are loaded
        BrowserManager.shared.reload()
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        routeURL(url)
    }

    func routeURL(_ url: URL) {
        let engine = RulesEngine.shared
        let bm = BrowserManager.shared

        // Try rules first
        if let browser = engine.resolve(url: url, sourceApp: nil) {
            browser.open(url)
            return
        }

        // Show picker
        let browsers = bm.browsers
        guard !browsers.isEmpty else {
            // Fallback: open with system default
            NSWorkspace.shared.open(url)
            return
        }

        PickerWindowController.shared.show(url: url, browsers: browsers) { chosen in
            if let browser = chosen {
                browser.open(url)
            }
            // If dismissed without picking, do nothing
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking dock icon opens settings
        NSApp.sendAction(#selector(AppCommands.openSettings), to: nil, from: nil)
        return false
    }
}

// Selector namespace for menu actions
@objc final class AppCommands: NSObject {
    @objc static func openSettings() {
        // Handled by SwiftUI Settings scene
    }
}
