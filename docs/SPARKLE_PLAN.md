# Sparkle 2 Auto-Updater Integration Plan

## Overview

Add Sparkle 2 auto-update support to OpenIn so users get updates without manually downloading from GitHub Releases.

Current state:
- SwiftUI app with `@NSApplicationDelegateAdaptor(AppDelegate.self)`
- Non-sandboxed (entitlements: `com.apple.security.app-sandbox = false`)
- Distributed as `.dmg` and `.zip` via GitHub Releases (`laurenschristian/OpenInApp`)
- Current version: v1.3.0
- Xcode project (no SPM)

---

## 1. Add Sparkle 2 to the Xcode Project (No SPM)

Since this is a plain Xcode project without Swift Package Manager, use the **XCFramework** approach:

1. Download the latest Sparkle 2.x release from https://github.com/sparkle-project/Sparkle/releases
2. Extract the archive -- it contains `Sparkle.xcframework`
3. In Xcode:
   - Drag `Sparkle.xcframework` into the project navigator (into the `OpenIn` group)
   - In the target's **General > Frameworks, Libraries, and Embedded Content**, ensure Sparkle.xcframework is set to **Embed & Sign**
4. Alternatively, add Sparkle as a git submodule and reference the xcframework from there

The XCFramework ships both arm64 and x86_64 slices so both Apple Silicon and Intel are covered.

### Alternative: SPM (if we change our minds)

If we ever adopt SPM for the project, just add `https://github.com/sparkle-project/Sparkle` as a package dependency with version rule "Up to Next Major" from 2.0.0.

---

## 2. Generate the EdDSA Key Pair

Sparkle 2 uses EdDSA (Ed25519) signatures. The signing key is used to sign `.zip` or `.dmg` artifacts before publishing.

```sh
# From the Sparkle release archive, run:
./bin/generate_keys
```

This outputs:
- A **private key** stored in your Keychain (under "Sparkle EdDSA" or similar)
- A **public key** string (base64-encoded) that goes into Info.plist

**Important:**
- Run `generate_keys` only once. The private key lives in your macOS Keychain.
- Back up the private key. If lost, users on old versions can never verify updates from the new key.
- To export/view the private key later: `./bin/generate_keys -x`
- Store a backup of the exported key somewhere secure (e.g., 1Password, encrypted USB).

### Add the public key to Info.plist

```xml
<key>SUPublicEDKey</key>
<string>YOUR_BASE64_PUBLIC_KEY_HERE</string>
```

Add this to `/OpenIn/Info.plist`.

---

## 3. Sign Release Artifacts

When building a release, sign the `.zip` with:

```sh
# From the Sparkle release archive:
./bin/sign_update OpenIn-v1.4.0.zip
```

This reads the private key from Keychain and outputs an `edSignature` and `length` -- both go into the appcast item (see below).

For `.dmg` files, the same command works:

```sh
./bin/sign_update OpenIn-v1.4.0.dmg
```

---

## 4. Appcast Hosting on GitHub

### Option A: Raw file in the repo (simplest)

Place `appcast.xml` at the repo root. Use the raw GitHub URL:

```
https://raw.githubusercontent.com/laurenschristian/OpenInApp/main/appcast.xml
```

Pros: Simple, no extra setup.
Cons: GitHub may cache raw files for up to 5 minutes. Not a real CDN.

### Option B: GitHub Pages (recommended)

1. Enable GitHub Pages on the repo (Settings > Pages), serving from `main` branch, `/docs` folder
2. Place `appcast.xml` in `/docs/appcast.xml`
3. The feed URL becomes: `https://laurenschristian.github.io/OpenInApp/appcast.xml`

Pros: Proper HTTP headers, faster CDN, custom domain possible.
Cons: Requires enabling Pages.

### Option C: GitHub Releases only (with generate_appcast)

Sparkle ships a `generate_appcast` tool that can build the appcast from a folder of archives. You could maintain a local folder of release zips and regenerate, but for GitHub-hosted releases this adds friction. Options A or B are better.

### Recommendation

**Option B (GitHub Pages from `/docs`)** -- it's clean, gives proper content-type headers, and the appcast lives in version control.

### Appcast format

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>OpenIn Updates</title>
    <link>https://laurenschristian.github.io/OpenInApp/appcast.xml</link>
    <description>OpenIn auto-update feed</description>
    <language>en</language>
    <item>
      <title>Version 1.4.0</title>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>1.4.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>Mon, 30 Mar 2026 12:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/laurenschristian/OpenInApp/releases/download/v1.4.0/OpenIn-v1.4.0.zip"
        sparkle:edSignature="BASE64_SIGNATURE_HERE"
        length="FILE_SIZE_IN_BYTES"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
```

Key points:
- `sparkle:version` = `CFBundleVersion` (build number)
- `sparkle:shortVersionString` = `CFBundleShortVersionString` (marketing version)
- `enclosure url` points to the GitHub Release asset directly
- The `edSignature` and `length` come from `sign_update`

---

## 5. Code Changes

### 5a. Info.plist additions

```xml
<!-- Appcast URL -->
<key>SUFeedURL</key>
<string>https://laurenschristian.github.io/OpenInApp/appcast.xml</string>

<!-- EdDSA public key (from generate_keys) -->
<key>SUPublicEDKey</key>
<string>YOUR_BASE64_PUBLIC_KEY_HERE</string>
```

### 5b. AppDelegate.swift changes

Add the Sparkle updater controller. Since the app uses `@NSApplicationDelegateAdaptor`, the `AppDelegate` is the right place.

```swift
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    // ... existing code ...
}
```

`startingUpdater: true` means Sparkle will automatically check for updates on launch (respecting the user's preferences). No other initialization code needed.

### 5c. Add "Check for Updates" menu item

In `OpenInApp.swift`, add a menu item to the `MenuBarExtra`. Sparkle 2 provides a `canCheckForUpdates` publisher on `SPUStandardUpdaterController`.

```swift
import Sparkle

// In MenuBarView, add a property:
let updater: SPUUpdater

// Add this button somewhere before "Quit OpenIn":
Button("Check for Updates...") {
    updater.checkForUpdates()
}
.disabled(!updater.canCheckForUpdates)
```

To wire this up, pass `appDelegate.updaterController.updater` from the `App` struct down to `MenuBarView`.

### 5d. Full wiring pattern

```swift
// OpenInApp.swift
@main
struct OpenInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                browserManager: BrowserManager.shared,
                rulesEngine: RulesEngine.shared,
                updater: appDelegate.updaterController.updater
            )
        } label: {
            Image(systemName: "arrow.up.right.square")
        }

        Settings {
            SettingsView()
        }
    }
}
```

### 5e. Optional: Add update check settings

In `SettingsView`, you can expose `updater.automaticallyChecksForUpdates` as a toggle:

```swift
Toggle("Check for updates automatically", isOn: Binding(
    get: { updater.automaticallyChecksForUpdates },
    set: { updater.automaticallyChecksForUpdates = $0 }
))
```

---

## 6. Entitlements

The app is not sandboxed (`com.apple.security.app-sandbox = false`), so no extra entitlements are needed for Sparkle. Sparkle 2 works out of the box with non-sandboxed apps.

If the app ever becomes sandboxed, you'd need:
- `com.apple.security.network.client = true` (for fetching the appcast)
- Use Sparkle's XPC-based updater (`SPUUpdater` with a separate XPC service target)

---

## 7. Release Workflow

For each new release:

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in Xcode
2. Archive and export the `.app`
3. Create a signed `.zip`:
   ```sh
   # Create the zip
   ditto -c -k --keepParent OpenIn.app OpenIn-v1.4.0.zip

   # Sign it
   ./bin/sign_update OpenIn-v1.4.0.zip
   # Outputs: edSignature="...", length=...
   ```
4. Update `docs/appcast.xml` with the new `<item>` (signature, length, version, URL)
5. Commit and push (so GitHub Pages serves the updated appcast)
6. Create GitHub Release with the `.zip` and `.dmg` attached

### Automation idea

A GitHub Actions workflow could:
1. Build and archive on tag push
2. Sign the zip (private key stored as a GitHub secret)
3. Update appcast.xml automatically
4. Create the GitHub Release

---

## 8. Checklist

- [ ] Download Sparkle 2.x XCFramework
- [ ] Add to Xcode project (Embed & Sign)
- [ ] Run `generate_keys`, save public key to Info.plist, back up private key
- [ ] Add `SUFeedURL` and `SUPublicEDKey` to Info.plist
- [ ] Add `SPUStandardUpdaterController` to AppDelegate
- [ ] Add "Check for Updates" to MenuBarView
- [ ] Enable GitHub Pages on `/docs`
- [ ] Create initial `docs/appcast.xml`
- [ ] Build, sign, release v1.4.0 as the first Sparkle-enabled version
- [ ] Test: install v1.3.0, verify it does NOT auto-update (no Sparkle). Install v1.4.0, verify "Check for Updates" works.

---

## References

- Sparkle 2 docs: https://sparkle-project.org/documentation/
- Sparkle GitHub: https://github.com/sparkle-project/Sparkle
- EdDSA key generation: https://sparkle-project.org/documentation/eddsa-setup/
- Appcast publishing: https://sparkle-project.org/documentation/publishing/
