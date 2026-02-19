---
name: silk
description: Accessibility-first macOS automation with DOM-level precision. Find and interact with UI elements by text, role, identifier, size, and hierarchy. Combines accessibility tree navigation with humanized mouse movements. Use when you need to click buttons, fill forms, control macOS applications, bypass bot detection, or automate UI workflows without coordinates.
---

# Silk — macOS UI Automation

Native macOS automation tool using Accessibility API + Vision. Find and interact with UI elements by describing them — no coordinates needed.

**Binary:** `silk` or `~/.local/bin/silk`

**Requirements:** Accessibility permissions (System Settings → Privacy & Security → Accessibility)

## Core Concepts

**Silk finds elements via Accessibility API** (like browser DevTools for native apps), then interacts using OS-level trusted input events that bypass bot detection.

**Element references work like CSS selectors:** Describe what you want, Silk finds it.

**Auto-scroll:** Off-screen elements automatically scroll into view before interaction.

**Humanization:** Optional Bezier curve mouse movement + Fitts's Law timing to mimic human behavior.

## Common Patterns

### Basic Interaction

```bash
# Click button by text
silk click "Submit"

# Type into field
silk type "username" "user@example.com"

# Press keyboard shortcuts (space-separated keys)
silk key cmd c                    # Copy
silk key cmd shift n              # Multi-modifier shortcut
silk key enter                    # Special key

# Paste text
silk paste "Hello world"
```

### Precision Targeting

When multiple elements match, use filters:

```bash
# Size filters
silk click "1" --min-width 150              # Large button, not small
silk click "Close" --max-width 50           # Small close button

# Position filters
silk click "Share" --sibling-index 2        # 3rd element (0-based)
silk click "OK" --parent-role Dialog        # OK in dialog, not toolbar

# Identifier filter (like DOM id)
silk click --identifier "submit-btn"

# Combined filters
silk click "Share" --parent-role Toolbar --sibling-index 2 --min-width 40
```

### App Targeting

```bash
# Target specific app
silk click "Submit" --app Chrome

# Switch to app first (recommended pattern)
silk app switch Chrome
silk click "Submit"
```

### Humanized Automation (Bot Detection)

Use `--humanize` when interacting with sites that detect bots:

```bash
silk click "Login" --humanize --trail
silk type "password" "secret" --humanize
```

**Humanization features:**
- Bezier curve mouse paths (not straight lines)
- Fitts's Law timing (distance-based speed)
- OS-level trusted events (`kCGHIDEventTap`)
- Visual trail overlay shows movement path

### Scrolling

```bash
# Scroll by pages (recommended)
silk scroll down --pages 1
silk scroll up --pages 2

# Scroll to element (makes it visible)
silk scroll to "Submit" --app Chrome

# Scroll in web browsers (point inside content area)
silk scroll down --at 500,300 --app Chrome

# Scroll within element's container
silk scroll down --from "Content" --app Chrome
```

**Auto-scroll:** `silk click` automatically scrolls off-screen elements. Disable with `--no-scroll` if speed-critical.

### Screen Inspection

```bash
# Screenshot with OCR + screen info
silk screenshot --info /tmp/screen.png

# OCR text extraction
silk ocr

# Find all elements (discover structure)
silk find --app Chrome --json | jq '.elements[] | {title, role, size}'

# Inspect element under cursor
silk find --at-cursor

# Highlight element before clicking
silk click "Submit" --highlight
```

### Element References (Advanced)

Store element references to reuse later without repeating queries:

```bash
# 1. Find and extract reference
REF=$(silk find "Button 1" --app Chrome --json | jq -r '.elements[0].ref')

# 2. Use reference for instant targeting
silk click "@$REF" --app Chrome --humanize
```

**Reference types:**
- `id:...` — By identifier (most stable)
- `ref:Button-3-WebArea` — Structural (role + position + parent)
- `pos:Button-200-400` — Spatial (role + coordinates)

## Self-Correcting Pattern

When automation fails, UI state likely changed. Check for blockers:

```bash
# 1. Inspect current state
silk find --app Chrome --json > /tmp/ui-state.json

# 2. Check for alert dialogs (common blocker)
cat /tmp/ui-state.json | jq '.[] | select(.role == "AXWindow" and (.title | contains("says")))'

# 3. Dismiss blocker
silk click "OK" --app Chrome

# 4. Retry intended action
silk click "Submit" --app Chrome
```

**Common blockers:**
- Alert dialogs: `role=="AXWindow"` with title containing "says" / "alert"
- Modal sheets: `subrole=="AXSheet"`
- Loading overlays: Text containing "loading" / "please wait"

**Recovery loop:** Inspect → Diagnose → Handle → Retry → Verify

## App & Window Management

```bash
# Launch app
silk app launch Chrome
silk app launch Safari --url https://google.com
silk app launch TextEdit --file ~/doc.txt --hidden

# Quit app
silk app quit Chrome
silk app quit Safari --force              # Force quit

# Switch/hide
silk app switch Chrome                    # Bring to front
silk app hide Chrome

# List apps
silk app list --json

# Window management
silk window list
silk window move Chrome 0 0
silk window resize Chrome 1200 800
silk window fullscreen Chrome

# Menu bar
silk menu list --app Chrome
silk menu click "File" "New Tab" --app Chrome

# Dock
silk dock list
silk dock click "Safari"
```

## Clipboard & Dialogs

```bash
# Clipboard
silk clipboard read
silk clipboard write "text"
silk clipboard clear

# System dialogs
silk dialog list
silk dialog click "OK"
silk dialog input "filename.txt"
silk dialog wait                          # Wait for dialog to appear
```

## Critical Gotchas

**Switch to target app first:** Silk clicks at screen coordinates. If another window is in front, the click lands there. Always use `silk app switch <app>` before automation.

**Keys are space-separated:** Use `silk key cmd c`, NOT `silk key "cmd+c"`.

**Web scroll needs `--at` coordinates:** When scrolling in browsers, point inside the web content area: `silk scroll down --at 500,300`.

**Password fields report empty values:** macOS security prevents reading password field contents. Use visual verification instead.

**Auto-scroll adds latency:** If element is known to be on-screen and speed is critical, use `--no-scroll`.

## Command Reference

For complete command syntax and options, see [COMMANDS.md](COMMANDS.md).

**Quick command list:**
- `silk click <text>` — Find and click element
- `silk type <selector> <text>` — Type into field
- `silk key <keys>...` — Press keyboard shortcuts
- `silk paste <text>` — Paste via clipboard
- `silk drag <x1> <y1> <x2> <y2>` — Drag operation
- `silk find <text>` — Find elements (no action)
- `silk scroll <direction>` — Scroll viewport
- `silk screenshot [path]` — Capture screen
- `silk ocr [path]` — Extract text via OCR
- `silk app <subcommand>` — Manage apps
- `silk window <subcommand>` — Manage windows
- `silk menu <subcommand>` — Menu bar interaction
- `silk dock <subcommand>` — Dock interaction
- `silk clipboard <subcommand>` — Clipboard operations
- `silk dialog <subcommand>` — Dialog handling

## Debugging Tips

**Can't find element?** Inspect app structure:
```bash
silk find --app Chrome --json | jq '.elements[] | {title, role, size, identifier}'
```

**Element not clickable?** Check if off-screen or blocked:
```bash
silk find "Submit" --app Chrome --highlight
```

**Automation failing?** Enable visual trail to see mouse path:
```bash
silk click "Submit" --humanize --trail --trail-duration 5
```

**Permission denied?** Grant Accessibility permissions and **restart terminal**.
