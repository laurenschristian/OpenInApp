import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasLaunched = false
    private var hotKeyRef: EventHotKeyRef?
    private var lastRoutedURL: URL?
    private var lastSourceApp: String?
    private var configWatcher: DispatchSourceFileSystemObject?
    private var hudWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        BrowserManager.shared.reload()
        syncLoginItem()
        registerGlobalHotkey()
        startConfigWatcher()

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                OnboardingWindowController.shared.show()
            }
        }

        hasLaunched = true
    }

    // MARK: - Global Hotkey (Cmd+Shift+B)

    private func registerGlobalHotkey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let appDelegate = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                delegate.handleHotkey()
                return noErr
            },
            1,
            &eventType,
            appDelegate,
            nil
        )

        var gHotKeyID = EventHotKeyID(signature: OSType(0x4F49_4E00), id: 1)
        let keyCode: UInt32 = 11 // 'B' key
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(keyCode, modifiers, gHotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func handleHotkey() {
        guard let url = lastRoutedURL else { return }
        let browsers = BrowserManager.shared.browsers
        guard !browsers.isEmpty else { return }

        PickerWindowController.shared.show(url: url, browsers: browsers, sourceApp: lastSourceApp) { [weak self] chosen in
            if let browser = chosen {
                browser.open(url)
                RulesEngine.shared.recordURL(url, browserID: browser.bundleID, sourceApp: self?.lastSourceApp)
            }
        }
    }

    // MARK: - Config File Watcher

    private func startConfigWatcher() {
        let path = AppConfig.configURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            RulesEngine.shared.config = AppConfig.load()
            RulesEngine.shared.objectWillChange.send()

            // Re-watch if file was replaced (delete+rename from atomic writes)
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self?.configWatcher?.cancel()
                self?.configWatcher = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.startConfigWatcher()
                }
            }
        }

        source.setCancelHandler { close(fd) }
        source.resume()
        configWatcher = source
    }

    // MARK: - Floating HUD Notification

    private func showHUD(browserName: String, host: String) {
        let config = RulesEngine.shared.config
        guard config.showNotifications else { return }

        hudWindow?.orderOut(nil)

        let label = NSTextField(labelWithString: "Opened in \(browserName)  --  \(host)")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.sizeToFit()

        let padding: CGFloat = 20
        let size = NSSize(width: label.frame.width + padding * 2, height: label.frame.height + 12)

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 8

        label.frame.origin = NSPoint(x: padding, y: 6)
        bg.addSubview(label)

        let w = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.contentView = bg
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.hasShadow = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.ignoresMouseEvents = true

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let origin = NSPoint(
                x: screenFrame.maxX - size.width - 16,
                y: screenFrame.maxY - size.height - 16
            )
            w.setFrameOrigin(origin)
        }

        w.alphaValue = 0
        w.orderFront(nil)
        hudWindow = w

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            w.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard self?.hudWindow === w else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                w.animator().alphaValue = 0
            }, completionHandler: {
                w.orderOut(nil)
                if self?.hudWindow === w { self?.hudWindow = nil }
            })
        }
    }

    // MARK: - URL Handling

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        let sourceApp = extractSourceApp(from: event)
        routeURL(url, sourceApp: sourceApp)
    }

    private func extractSourceApp(from event: NSAppleEventDescriptor) -> String? {
        guard let senderDesc = event.attributeDescriptor(forKeyword: AEKeyword(keyAddressAttr)) else { return nil }

        if senderDesc.descriptorType == typeApplicationBundleID {
            return senderDesc.stringValue
        }

        if senderDesc.descriptorType == typeKernelProcessID {
            let pid = senderDesc.int32Value
            if let app = NSRunningApplication(processIdentifier: pid) {
                return app.bundleIdentifier
            }
        }

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

        let cleanURL = engine.config.rewriteURL(url)

        // Store for hotkey re-invocation
        lastRoutedURL = cleanURL
        lastSourceApp = sourceApp

        // Try rules
        if let browser = engine.resolve(url: cleanURL, sourceApp: sourceApp) {
            let rule = engine.config.rules.first { $0.matches(url: cleanURL, sourceApp: sourceApp) && $0.enabled }
            browser.open(cleanURL, profile: rule?.browserProfile, incognito: rule?.openIncognito ?? false)
            engine.recordURL(cleanURL, browserID: browser.bundleID, sourceApp: sourceApp)
            showHUD(browserName: browser.name, host: cleanURL.host ?? cleanURL.absoluteString)
            return
        }

        // If picker is disabled and no rule matched, use configured default
        if !engine.config.showPickerOnNoMatch {
            if let defaultID = engine.config.defaultBrowserID,
               let browser = bm.browser(for: defaultID) {
                browser.open(cleanURL, profile: engine.config.defaultBrowserProfile)
            } else {
                NSWorkspace.shared.open(cleanURL)
            }
            engine.recordURL(cleanURL, browserID: engine.config.defaultBrowserID ?? "", sourceApp: sourceApp)
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
private let keySenderPIDAttr = AEKeyword(0x736E6472)
