import SwiftUI
import AppKit

struct PickerView: View {
    let url: URL
    let browsers: [Browser]
    let sourceApp: String?
    let lastUsedBrowserID: String?
    let onPick: (Browser) -> Void
    let onDismiss: () -> Void
    @State private var hoveredID: String?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 10) {
            // URL display with copy button
            HStack(spacing: 6) {
                Text(url.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button(action: copyURL) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy URL")
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            // Source app indicator
            if let sourceApp = sourceApp {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 9))
                    Text("from \(appName(for: sourceApp))")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.tertiary)
            }

            // Browser grid
            HStack(spacing: 14) {
                ForEach(Array(sortedBrowsers.enumerated()), id: \.element.id) { index, browser in
                    BrowserButton(
                        browser: browser,
                        index: index + 1,
                        isHovered: hoveredID == browser.id,
                        isLastUsed: browser.bundleID == lastUsedBrowserID,
                        action: { onPick(browser) }
                    )
                    .onHover { hoveredID = $0 ? browser.id : nil }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            // Hint
            Text("Esc to dismiss")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .padding(.bottom, 4)
        }
        .frame(minWidth: 200)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }

    private var sortedBrowsers: [Browser] {
        guard let lastUsed = lastUsedBrowserID else { return browsers }
        var sorted = browsers
        if let idx = sorted.firstIndex(where: { $0.bundleID == lastUsed }), idx > 0 {
            let browser = sorted.remove(at: idx)
            sorted.insert(browser, at: 0)
        }
        return sorted
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func appName(for bundleID: String) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }
}

struct BrowserButton: View {
    let browser: Browser
    let index: Int
    let isHovered: Bool
    let isLastUsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: browser.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .scaleEffect(isHovered ? 1.15 : 1.0)
                        .animation(.easeOut(duration: 0.15), value: isHovered)

                    if isLastUsed {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }

                Text(browser.name)
                    .font(.system(size: 10, weight: isLastUsed ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if index <= 9 {
                    Text("\u{2318}\(index)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
    }
}

// MARK: - Window Controller

final class PickerWindowController {
    static let shared = PickerWindowController()
    private var window: NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func show(url: URL, browsers: [Browser], sourceApp: String? = nil, completion: @escaping (Browser?) -> Void) {
        dismiss()

        let lastUsed = RulesEngine.shared.lastUsedBrowser(forHost: url.host ?? "")

        let pickerView = PickerView(
            url: url,
            browsers: browsers,
            sourceApp: sourceApp,
            lastUsedBrowserID: lastUsed,
            onPick: { [weak self] browser in
                completion(browser)
                self?.dismiss()
            },
            onDismiss: { [weak self] in
                completion(nil)
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: pickerView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let w = PickerPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.hasShadow = false
        w.isMovableByWindowBackground = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.becomesKeyOnlyIfNeeded = false

        // Position near mouse
        let mouseLocation = NSEvent.mouseLocation
        let wSize = hostingView.fittingSize

        // Find the screen containing the mouse
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main

        if let screen = screen {
            let screenFrame = screen.visibleFrame
            var origin = NSPoint(
                x: mouseLocation.x - wSize.width / 2,
                y: mouseLocation.y - wSize.height / 2
            )
            origin.x = max(screenFrame.minX + 10, min(origin.x, screenFrame.maxX - wSize.width - 10))
            origin.y = max(screenFrame.minY + 10, min(origin.y, screenFrame.maxY - wSize.height - 10))
            w.setFrameOrigin(origin)
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w

        // Escape key and click-outside handling
        w.onEscape = { [weak self] in
            completion(nil)
            self?.dismiss()
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            completion(nil)
            self?.dismiss()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                completion(nil)
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    func dismiss() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}

// Custom NSPanel subclass that can become key (for keyboard events)
final class PickerPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
