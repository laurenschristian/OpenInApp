# OpenIn

A fast, native macOS URL router. Sets itself as the default browser, intercepts every link click, and lets you pick which browser to open it in -- or routes it automatically with rules.

Built with SwiftUI and AppKit. No Electron, no web views, ~10MB memory footprint.

Requires macOS 14+.

## Features

- Menu bar app that registers as a system browser
- Popup picker appears near the mouse with all installed browsers
- Keyboard shortcuts (Cmd+1 through Cmd+9) for instant selection
- Rules engine: route URLs to specific browsers based on domain patterns and source app
- Glob and regex pattern matching
- JSON config file for easy backup and sync
- Settings UI with General, Rules, and About tabs
- Auto-detects all installed browsers

## Screenshots

_Coming soon._

## Installation

### Build from source

1. Clone the repo
2. Open `OpenIn.xcodeproj` in Xcode 15+
3. Build and run (Cmd+R)
4. Optionally copy `OpenIn.app` from the build output to `/Applications`

### Manual

Copy `OpenIn.app` to `/Applications`.

## Usage

### Set as default browser

Open the app, go to Settings (General tab), and click "Set as Default". macOS will ask you to confirm.

Once set, every link clicked in any app will be intercepted by OpenIn.

### How it works

1. A link is clicked anywhere on your Mac
2. OpenIn checks your rules top-to-bottom for a match
3. If a rule matches, the URL opens in that rule's target browser
4. If no rule matches, the picker popup appears near your mouse
5. Click a browser or press Cmd+1-9 to open the URL

You can also set a default browser for unmatched URLs instead of showing the picker.

## Configuration

Config lives at `~/.config/openin/config.json`.

```json
{
  "defaultBrowserID": "com.apple.Safari",
  "hideAfterPick": true,
  "rules": [
    {
      "enabled": true,
      "isRegex": false,
      "name": "GitHub",
      "pattern": "*.github.com",
      "targetBrowserID": "com.google.Chrome"
    },
    {
      "enabled": true,
      "isRegex": true,
      "name": "Google Docs",
      "pattern": "https://docs\\.google\\.com/.*",
      "sourceAppBundleID": "com.tinyspeck.slackmacgap",
      "targetBrowserID": "com.google.Chrome"
    }
  ],
  "showPickerOnNoMatch": true
}
```

### Pattern examples

| Pattern | Type | Matches |
|---|---|---|
| `*.github.com` | glob | `github.com`, `gist.github.com`, `docs.github.com` |
| `*.google.com` | glob | `mail.google.com`, `docs.google.com` |
| `notion.so` | glob | Any URL containing `notion.so` |
| `*jira*` | glob | Any URL containing `jira` |
| `https://docs\\.google\\.com/.*` | regex | Google Docs URLs only |
| `https://(dev\|staging)\\.example\\.com` | regex | Dev and staging environments |

### Rule fields

| Field | Required | Description |
|---|---|---|
| `name` | yes | Display name for the rule |
| `pattern` | yes | Glob or regex pattern to match against |
| `isRegex` | no | `true` to use regex instead of glob (default: `false`) |
| `targetBrowserID` | yes | Bundle ID of the target browser |
| `sourceAppBundleID` | no | Only match when the link was clicked from this app |
| `enabled` | no | `true` or `false` (default: `true`) |

### Common browser bundle IDs

| Browser | Bundle ID |
|---|---|
| Safari | `com.apple.Safari` |
| Chrome | `com.google.Chrome` |
| Firefox | `org.mozilla.firefox` |
| Arc | `company.thebrowser.Browser` |
| Brave | `com.brave.Browser` |
| Edge | `com.microsoft.edgemac` |
| Orion | `com.kagi.kagimacOS` |

## Building from source

```sh
git clone https://github.com/laurenschristian/OpenInApp.git
cd OpenInApp
open OpenIn.xcodeproj
```

Build with Xcode 15+ targeting macOS 14+.

## License

MIT License. See [LICENSE](LICENSE).
