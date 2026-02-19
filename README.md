<p align="center">
  <img src="assets/hero.png" alt="silk" width="100%">
</p>

<p align="center">
  <strong>Accessibility-first macOS automation for AI agents</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15.0+-black.svg?style=flat-square" alt="macOS 15.0+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/license-MIT-purple.svg?style=flat-square" alt="MIT">
</p>

---

Silk is a native macOS CLI that gives AI agents **DOM-level control** over the entire OS — using the same Accessibility API that screen readers rely on, with human-like input.

No coordinates. No screenshots required. Just describe what you want.

```bash
silk click "Sign In" --app Safari --humanize
silk key cmd shift n
silk scroll down --pages 1 --at 500,300
silk app launch "Xcode" --url ~/project/MyApp.xcodeproj
```

---

## Why silk?

| | Silk | Playwright |
|---|---|---|
| **Event trust** | ✅ `isTrusted=true` | ❌ synthetic |
| **Humanization** | ✅ Bezier + Fitts | ❌ linear |
| **UI discovery** | ✅ Accessibility API | ✅ DOM only |
| **Any macOS app** | ✅ | ❌ browsers only |

---

## Installation

```bash
git clone https://github.com/saucesteals/silk
cd silk
swift build -c release
cp .build/release/silk /usr/local/bin/
```

**Permissions required:** Accessibility + Screen Recording — grant both in System Settings → Privacy & Security.

---

## Quick start

### Click, type, find

```bash
# Click by text
silk click "Submit"

# Precision filters when multiple elements match
silk click "OK" --parent-role Dialog --min-width 80

# Type into a field
silk type "Search" "hello world" --app Safari

# Find elements without clicking
silk find --app Chrome --json | jq '.elements[] | {title, role}'
```

### Keyboard

```bash
silk key cmd c                  # Copy
silk key cmd shift n            # New window
silk key escape
silk key down --count 5
silk paste "Hello world"
```

### Scroll

```bash
silk scroll down --pages 1
silk scroll down --at 500,300   # Required for browser content
silk scroll to "Footer" --app Safari
```

### Vision

```bash
silk screenshot /tmp/screen.png
silk screenshot --info          # + OCR text extraction
silk ocr --region 0,0,1440,30  # Read menu bar text
```

### Apps & windows

```bash
silk app launch Safari --url https://example.com
silk app quit Chrome --force
silk app switch Finder

silk window move Safari 0 0
silk window resize Chrome 1440 900
silk window fullscreen Safari
```

### Menus, dock, clipboard

```bash
silk menu click "File" "New Tab" --app Chrome
silk dock click "Safari"

silk clipboard read
silk clipboard write "text"
silk clipboard write --image ~/screenshot.png
```

### Dialogs

```bash
silk dialog wait
silk dialog click "OK"
silk dialog input "filename.txt" --enter
```

---

## Humanization

Add `--humanize` for natural mouse movement:

```bash
silk click "Login" --humanize --trail
```

- **Bezier curve** mouse paths (not straight lines)
- **Fitts's Law** timing (fast in open space, slow near target)
- **OS-level events** via `kCGHIDEventTap` → `isTrusted = true`
- **Visual trail** overlay to debug movement in real-time

---

## How it works

```
silk click "Submit" --app Chrome
        │
        ▼
  Accessibility API        ← finds element by text/role/filters
  (AXUIElement tree)
        │
        ▼
  Humanization layer       ← Bezier path + Fitts's Law timing (optional)
        │
        ▼
  CGEvent → kCGHIDEventTap ← posted at WindowServer level (isTrusted=true)
        │
        ▼
     Chrome
```

---

## Command reference

See [COMMANDS.md](COMMANDS.md) for full syntax and options.

**Commands at a glance:**
- `click` `type` `drag` `scroll` `key` `paste` — input
- `find` — element discovery
- `screenshot` `ocr` — vision
- `app` — launch, quit, hide, switch, list
- `window` — move, resize, close, minimize, maximize, fullscreen, list
- `menu` `dock` — system UI
- `clipboard` — read, write, types, clear
- `dialog` — click, input, list, wait

---

## Requirements

- macOS 15.0+ (Sequoia)
- Swift 6.0+
- Accessibility + Screen Recording permissions

---

## License

MIT — see [LICENSE](LICENSE).

---

<p align="center">Built by <a href="https://github.com/builderjarvis">Jarvis</a> ⚡</p>
