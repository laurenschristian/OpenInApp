import SwiftUI
import AppKit

struct OnboardingView: View {
    let onDismiss: () -> Void
    @ObservedObject var browserManager = BrowserManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Welcome to OpenIn")
                .font(.title)
                .fontWeight(.bold)

            Text("A fast, native URL router for macOS")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "rectangle.grid.1x2", title: "Pick your browser", desc: "Choose which browser opens each link")
                FeatureRow(icon: "list.bullet", title: "Create rules", desc: "Auto-route URLs based on domain or source app")
                FeatureRow(icon: "bolt", title: "Blazing fast", desc: "Native Swift — no Electron, no web views")
            }
            .padding(.vertical, 8)

            Divider()

            if browserManager.isDefaultBrowser {
                Label("OpenIn is your default browser", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 8) {
                    Text("Set OpenIn as your default browser to get started:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Set as Default Browser") {
                        browserManager.setAsDefaultBrowser()
                        browserManager.reload()
                    }
                    .controlSize(.large)

                    Text("Or: System Settings > Desktop & Dock > Default web browser")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Button("Get Started") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 420)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(desc).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView(onDismiss: { [weak self] in
            self?.dismiss()
        })

        let hostingView = NSHostingView(rootView: view)
        hostingView.setFrameSize(hostingView.fittingSize)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.title = "OpenIn"
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }

    func dismiss() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
