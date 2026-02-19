# Silk Command Reference

Complete syntax reference for all Silk commands.

## Table of Contents

- [Element Interaction](#element-interaction)
- [Element Discovery](#element-discovery)
- [Keyboard Input](#keyboard-input)
- [Scrolling](#scrolling)
- [Screen Capture](#screen-capture)
- [App Management](#app-management)
- [Window Management](#window-management)
- [Menu Bar](#menu-bar)
- [Dock](#dock)
- [Clipboard](#clipboard)
- [System Dialogs](#system-dialogs)

---

## Element Interaction

### silk click — Find and click a UI element

**Auto-scroll:** Automatically scrolls off-screen elements into view (up to 8 attempts by default).

```bash
silk click "Submit"                              # Click by text (auto-scrolls if needed)
silk click "Submit" --humanize --trail           # Humanized with visual trail
silk click --role button --app Chrome            # By role
silk click "Submit" --identifier "submit-btn"    # By identifier
silk click "1" --min-width 150                   # With size filter
silk click "OK" --parent-role toolbar            # With parent filter
silk click "OK" --highlight                      # Highlight before clicking
silk click "Submit" --no-scroll                  # Disable auto-scroll
silk click "Submit" --max-scroll-attempts 3      # Limit scroll attempts
```

**Options:**
- `--role <role>` — Filter by accessibility role
- `--app <app>` — Target application name
- `--exact` — Require exact text match (no fuzzy)
- `--humanize` — Use humanized mouse movement
- `--trail` — Show visual trail during movement
- `--trail-duration <s>` — Trail visibility duration (default: 3.0)
- `--json` — Output as JSON
- `--highlight` — Draw bounding box before clicking
- `--highlight-duration <s>` — Highlight duration (default: 1.5)
- `--identifier <id>` — Filter by accessibility identifier
- `--sibling-index <n>` — Filter by sibling index (0-based)
- `--parent-role <role>` — Filter by parent element role
- `--min-width <px>`, `--max-width <px>` — Width filters
- `--min-height <px>`, `--max-height <px>` — Height filters
- `--no-scroll` — Disable auto-scroll for off-screen elements
- `--max-scroll-attempts <n>` — Max scroll attempts (default: 8)

### silk type — Find and type into a UI element

```bash
silk type "username" "user@example.com"        # Find field, type text
silk type --role textField "Search" "hello"      # By role
silk type "password" "secret" --app Chrome       # Target app
```

**Args:** `[selector] <text>` — selector finds the field, text is what to type.

**Options:** `--role`, `--app`, `--exact`, `--humanize`, `--json`

### silk drag — Drag from one location to another

```bash
silk drag 100 200 500 600                        # Coordinate drag
silk drag 100 200 500 600 --humanize             # Humanized
silk drag "File.pdf" "Trash" --app Finder        # Element-based drag
silk drag 100 200 500 600 --button right         # Right-button drag
silk drag 100 200 500 600 --duration 2.0         # 2 second drag
```

**Args:** `<x1> <y1> <x2> <y2>` or `<element1> <element2>`

**Options:**
- `--app <app>` — Target application
- `--button <left|right|middle>` — Mouse button (default: left)
- `--duration <s>` — Drag duration in seconds
- `--humanize` — Use humanized movement
- `--json` — Output as JSON

---

## Element Discovery

### silk find — Find UI elements (no action)

```bash
silk find "Button 1"                             # Find by text
silk find --role button --app Chrome --json      # By role, JSON output
silk find "Submit" --all                         # All matches
silk find "1" --min-width 150                    # With size filter
silk find "OK" --parent-role toolbar --sibling-index 2
silk find --at-cursor                            # Inspect element under cursor
```

**Options:**
- `--role <role>` — Filter by accessibility role
- `--app <app>` — Target application name
- `--exact` — Require exact text match
- `--all` — Return all matches (not just first)
- `--at-cursor` — Inspect element under cursor
- `--json` — Output as JSON
- `--highlight` — Highlight found elements
- `--highlight-duration <s>` — Highlight duration (default: 1.5)
- `--identifier <id>` — Filter by accessibility identifier
- `--sibling-index <n>` — Filter by sibling index (0-based)
- `--parent-role <role>` — Filter by parent element role
- `--min-width <px>`, `--max-width <px>` — Width filters
- `--min-height <px>`, `--max-height <px>` — Height filters

**Replaces:** `silk inspect --at-cursor` → `silk find --at-cursor`

---

## Keyboard Input

### silk key — Press keyboard shortcuts and special keys

**Unified keyboard input** — Space-separated keys (NOT `+`-joined).

```bash
# Shortcuts (modifiers + key)
silk key cmd c                                   # Copy
silk key cmd v                                   # Paste
silk key cmd shift n                             # New window
silk key cmd opt esc                             # Force quit dialog
silk key shift tab                               # Shift+Tab

# Special keys
silk key enter                                   # Enter
silk key escape                                  # Escape
silk key down --count 5                          # Down arrow 5 times
silk key f11                                     # F11

# Repeat
silk key cmd f --count 3                         # Press 3 times
```

**Modifiers:**
- `cmd`, `command`, `⌘` — Command key
- `shift`, `⇧` — Shift key
- `opt`, `option`, `alt`, `⌥` — Option key
- `ctrl`, `control`, `^` — Control key
- `fn` — Function key

**Special keys:**
- `enter`, `return` — Enter/Return
- `tab` — Tab
- `space` — Space
- `delete`, `backspace` — Delete/Backspace
- `escape` — Escape
- `up`, `down`, `left`, `right` — Arrow keys
- `home`, `end` — Home/End
- `pageup`, `pagedown` — Page Up/Down
- `f1`-`f12` — Function keys
- `volumeup`, `volumedown`, `mute` — Volume controls

**Options:**
- `--count <n>` — Repeat key press n times
- `--json` — Output as JSON

### silk paste — Paste text via clipboard

```bash
silk paste "Hello world"                         # Paste text
silk paste "secret" --clear                      # Paste and clear clipboard
echo "text" | silk paste                         # Paste from stdin
cat file.txt | silk paste                        # Paste file contents
```

**Args:** `<text>` — Text to paste (or from stdin)

**Options:**
- `--clear` — Clear clipboard after pasting
- `--json` — Output as JSON

**Note:** No `--app` flag. Pastes into whatever has focus. Click the right field first.

---

## Scrolling

### silk scroll — Scroll in a direction or to an element

```bash
silk scroll down                                 # Default (3 units)
silk scroll down --pages 1                       # One full page (recommended!)
silk scroll up --pages 2                         # Two pages up
silk scroll down --amount 10                     # 10 units (100 pixels)
silk scroll down --smooth                        # Smooth scrolling
silk scroll down --at 500,300                    # At specific point
silk scroll to "Submit" --app Chrome             # Scroll element into view
silk scroll down --from "Content" --app Chrome   # Scroll from element's container
silk scroll right --amount 5                     # Horizontal scroll
```

**Args:** `<direction>` — up, down, left, right, or `to <element>`

**Options:**
- `--amount <n>` — Amount in scroll units (default: 3, each unit ≈ 10px)
- `--pages <n>` — Scroll by viewport pages (1.0 = full page, 0.5 = half)
- `--at <X,Y>` — Scroll at specific point (important for web content)
- `--from <element>` — Scroll from named element (uses its scroll container)
- `--app <app>` — App name for element-based scroll
- `--smooth` — Smooth scrolling animation
- `--json` — JSON output

**Key changes:**
- `silk scroll-to "element"` → `silk scroll to "element"`
- `silk scroll --element "Content"` → `silk scroll --from "Content"`

**Web content tip:** When scrolling in Chrome/browsers, use `--at X,Y` pointing inside the web content area. Without it, scroll events may not reach the page content.

---

## Screen Capture

### silk screenshot — Capture screenshot

```bash
silk screenshot /tmp/screen.png                  # Full screen
silk screenshot --region 0,0,800,600 /tmp/r.png  # Region capture
silk screenshot --info /tmp/screen.png           # Include screen info + OCR
silk screenshot --json                           # JSON output (default path)
```

**Args:** `[path]` — Output path (default: `/tmp/silk_screenshot.png`)

**Options:**
- `--region <X,Y,W,H>` — Capture specific region
- `--window <name>` — Capture specific window (not yet implemented)
- `--info` — Include screen info (dimensions, scale) + OCR text
- `--json` — Output as JSON

**Replaces:** `silk see` → `silk screenshot --info`

### silk ocr — Extract text from screen via OCR

```bash
silk ocr                                         # OCR full screen
silk ocr --region 0,0,800,600                    # OCR region
silk ocr /tmp/image.png                          # OCR an image file
silk ocr --json                                  # JSON output
```

**Args:** `[path]` — Image file path (optional, defaults to screen capture)

**Options:**
- `--region <X,Y,W,H>` — OCR specific region
- `--window <name>` — OCR specific window (not yet implemented)
- `--json` — Output as JSON

---

## App Management

### silk app — Manage applications

**Subcommands:** `launch`, `quit`, `hide`, `switch`, `list`

**Replaces:** Standalone `silk launch`, `silk quit`, `silk hide`, `silk switch`, `silk apps`

#### silk app launch — Launch an application

```bash
silk app launch Chrome
silk app launch Safari --url https://google.com
silk app launch TextEdit --file ~/document.txt
silk app launch Terminal --hidden                # Launch hidden
silk app launch Finder --background              # Don't activate
```

**Args:** `<app-name>` — Application name

**Options:**
- `--url <url>` — Open URL (browsers)
- `--file <path>` — Open file path
- `--hidden` — Launch hidden
- `--background` — Launch without activating
- `--json` — Output as JSON

#### silk app quit — Quit an application

```bash
silk app quit Chrome
silk app quit Safari --force                     # Force quit (SIGKILL)
```

**Args:** `<app-name>` — Application name

**Options:**
- `--force` — Force quit (SIGKILL instead of graceful quit)
- `--json` — Output as JSON

#### silk app hide — Hide an application

```bash
silk app hide Chrome
```

**Args:** `<app-name>` — Application name

**Options:**
- `--json` — Output as JSON

#### silk app switch — Switch to application (bring to front)

```bash
silk app switch Chrome
```

**Args:** `<app-name>` — Application name

**Options:**
- `--json` — Output as JSON

#### silk app list — List running applications

```bash
silk app list
silk app list --json
```

**Options:**
- `--json` — Output as JSON

---

## Window Management

### silk window — Manage windows

**Subcommands:** `move`, `resize`, `close`, `minimize`, `maximize`, `fullscreen`, `list`

#### silk window list — List all windows

```bash
silk window list
silk window list --app Chrome
silk window list --json
```

**Options:**
- `--app <app>` — Filter by application
- `--json` — Output as JSON

#### silk window move — Move window

```bash
silk window move Chrome 0 0
silk window move Chrome 100 200 --title "Google"
silk window move Chrome 0 0 --index 1
```

**Args:** `<app> <x> <y>`

**Options:**
- `--title <text>` — Target window by title (partial match)
- `--index <n>` — Target window by index (0 = frontmost)
- `--json` — Output as JSON

#### silk window resize — Resize window

```bash
silk window resize Chrome 1200 800
silk window resize Safari 1440 900 --title "Apple"
```

**Args:** `<app> <width> <height>`

**Options:**
- `--title <text>` — Target window by title (partial match)
- `--index <n>` — Target window by index (0 = frontmost)
- `--json` — Output as JSON

#### silk window close — Close front window

```bash
silk window close Chrome
silk window close Chrome --title "Settings"
```

**Args:** `<app>`

**Options:**
- `--title <text>` — Target window by title (partial match)
- `--index <n>` — Target window by index (0 = frontmost)
- `--json` — Output as JSON

#### silk window minimize — Minimize window to dock

```bash
silk window minimize Chrome
```

**Args:** `<app>`

**Options:**
- `--title <text>` — Target window by title (partial match)
- `--index <n>` — Target window by index (0 = frontmost)
- `--json` — Output as JSON

#### silk window maximize — Maximize window (zoom)

```bash
silk window maximize Chrome
```

**Args:** `<app>`

**Options:**
- `--title <text>` — Target window by title (partial match)
- `--index <n>` — Target window by index (0 = frontmost)
- `--json` — Output as JSON

#### silk window fullscreen — Toggle fullscreen

```bash
silk window fullscreen Chrome
```

**Args:** `<app>`

**Options:**
- `--title <text>` — Target window by title (partial match)
- `--index <n>` — Target window by index (0 = frontmost)
- `--json` — Output as JSON

---

## Menu Bar

### silk menu — Menu bar interaction

**Subcommands:** `click`, `list`

#### silk menu list — List menu items

```bash
silk menu list                       # List top-level menus (frontmost app)
silk menu list File                  # List File menu items
silk menu list --app Chrome
silk menu list File --app Chrome --json
```

**Args:** `[menu-path...]` — Optional menu path (e.g. `File`)

**Options:**
- `--app <app>` — Target application (default: frontmost app)
- `--json` — Output as JSON

#### silk menu click — Click menu item

```bash
silk menu click "File" "New Tab" --app Chrome
silk menu click "Edit" "Copy" --app Safari
silk menu click "View" "Enter Full Screen"
```

**Args:** `<menu> <item> [submenu-item...]` — Menu path (2+ items required)

**Options:**
- `--app <app>` — Target application (default: frontmost app)
- `--json` — Output as JSON

---

## Dock

### silk dock — Dock interaction

**Subcommands:** `click`, `list`

#### silk dock list — List dock applications

```bash
silk dock list
silk dock list --json
```

**Options:**
- `--json` — Output as JSON

#### silk dock click — Click dock icon

```bash
silk dock click "Safari"
silk dock click "Finder" --right-click     # Show context menu
```

**Args:** `<app-name>` — Application name

**Options:**
- `--right-click` — Right-click to show context menu
- `--json` — Output as JSON

---

## Clipboard

### silk clipboard — Clipboard operations

**Subcommands:** `read`, `write`, `types`, `clear`

#### silk clipboard read — Read clipboard contents

```bash
silk clipboard read
silk clipboard read --type image     # Read image as base64
silk clipboard read --type url       # Read URL
silk clipboard read --json
```

**Options:**
- `--type <type>` — Content type: `text` (default), `image`, `url`, `fileURL`, `rtf`, `html`
- `--json` — Output as JSON

#### silk clipboard write — Write to clipboard

```bash
silk clipboard write "Hello world"
echo "text" | silk clipboard write          # Write from stdin
silk clipboard write --file ~/note.txt      # Write file contents
silk clipboard write --image ~/photo.png    # Write image
silk clipboard write --url https://example.com  # Write URL
```

**Args:** `[text]` — Text to write (or use a flag below, or pipe via stdin)

**Options:**
- `--file <path>` — Read text content from file
- `--image <path>` — Write image from file
- `--url <url>` — Write a URL
- `--append` — Don't clear existing clipboard before writing
- `--json` — Output as JSON

#### silk clipboard types — List clipboard content types

```bash
silk clipboard types
silk clipboard types --json
```

**Options:**
- `--json` — Output as JSON

#### silk clipboard clear — Clear clipboard

```bash
silk clipboard clear
```

**Options:**
- `--json` — Output as JSON

---

## System Dialogs

### silk dialog — System dialog handling

**Subcommands:** `click`, `input`, `list`, `wait`

#### silk dialog list — List visible dialogs

```bash
silk dialog list
silk dialog list --json
```

**Options:**
- `--json` — Output as JSON

#### silk dialog click — Click dialog button

```bash
silk dialog click "OK"
silk dialog click "Cancel"
```

**Args:** `<button-text>` — Button text to click

**Options:**
- `--json` — Output as JSON

#### silk dialog input — Type into dialog field

```bash
silk dialog input "filename.txt"
silk dialog input "text" --field "Name"    # Target field by label
silk dialog input "text" --index 1         # Target field by index (0-based)
silk dialog input "text" --enter           # Press Enter after typing
```

**Args:** `<text>` — Text to type into dialog field

**Options:**
- `--field <label>` — Target field by label/placeholder
- `--index <n>` — Target field by index (0-based)
- `--enter` — Press Enter/Return after typing
- `--json` — Output as JSON

#### silk dialog wait — Wait for dialog to appear

```bash
silk dialog wait
silk dialog wait --timeout 5
```

**Options:**
- `--timeout <seconds>` — Maximum wait time (default: 10)
- `--json` — Output as JSON

---

## Common Role Names

Use these with `--role` and `--parent-role` flags:

**Interactive:**
- `Button` — Buttons
- `MenuItem` — Menu items
- `TextField` — Text input fields
- `Checkbox` — Checkboxes
- `RadioButton` — Radio buttons
- `Link` — Hyperlinks

**Containers:**
- `Toolbar` — Toolbars
- `Dialog` — Dialogs
- `Window` — Windows
- `Menu` — Menus
- `Group` — Generic containers
- `TabGroup` — Tab containers

**Display:**
- `StaticText` — Text labels
- `Image` — Images
- `Table` — Tables
- `List` — Lists

**Discover roles:** Use `silk find --app <app> --json | jq '.elements[] .role'` to see all roles in an app.
