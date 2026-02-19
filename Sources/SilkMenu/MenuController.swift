import AppKit
import ApplicationServices
import Foundation

public final class MenuController: Sendable {

  public init() {}

  /// Click menu item by navigating the menu hierarchy
  public func click(_ options: MenuClickOptions) throws -> MenuResult {
    let start = DispatchTime.now()

    guard !options.menuPath.isEmpty else {
      throw MenuError.invalidPath("Menu path must not be empty")
    }

    let app = try resolveApp(options.app)
    let appName = app.localizedName

    let appElement = AXUIElementCreateApplication(app.processIdentifier)

    guard let menuBar = getMenuBar(appElement) else {
      throw MenuError.menuBarNotFound(appName ?? "Unknown")
    }

    // Navigate to the final menu item and press it
    var currentElement = menuBar
    for (index, pathComponent) in options.menuPath.enumerated() {
      let children = getChildren(currentElement)

      guard let match = findChild(named: pathComponent, in: children) else {
        let available = children.compactMap { getTitle($0) }
        throw MenuError.menuItemNotFound(pathComponent, available: available)
      }

      if index < options.menuPath.count - 1 {
        // Intermediate item: open its submenu
        // For top-level menu bar items, press them to open the menu
        AXUIElementPerformAction(match, kAXPressAction as CFString)
        // Small delay for menu to render
        usleep(100_000)  // 100ms

        // Get the opened submenu
        if let submenu = getSubmenu(match) {
          currentElement = submenu
        } else {
          throw MenuError.menuItemNotFound(pathComponent, available: [])
        }
      } else {
        // Final item: click it
        let err = AXUIElementPerformAction(match, kAXPressAction as CFString)
        guard err == .success else {
          throw MenuError.clickFailed(pathComponent)
        }
      }
    }

    let durationMs = Int(
      (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)

    return MenuResult(
      action: "click",
      appName: appName,
      menuPath: options.menuPath,
      success: true,
      durationMs: durationMs
    )
  }

  /// List menu items at the given path.
  ///
  /// **⚠️ Intrusive Operation:** This method physically opens menus on screen via
  /// `AXUIElementPerformAction(kAXPressAction)` to traverse the menu hierarchy.
  /// macOS does not expose submenu children until the menu is actually opened.
  /// This means:
  /// - The user will see menus briefly flash open during listing
  /// - The target application is activated (brought to front)
  /// - An Escape key is posted afterward to close menus, but timing-sensitive
  ///   race conditions may occasionally leave a menu open
  ///
  /// There is no known non-intrusive alternative for reading submenu contents
  /// via the Accessibility API. Top-level menu bar items (path=[]) can be listed
  /// without opening, but any deeper path requires physical menu activation.
  public func listItems(app: String?, path: [String]) throws -> [MenuItem] {
    let resolvedApp = try resolveApp(app)
    let appElement = AXUIElementCreateApplication(resolvedApp.processIdentifier)

    guard let menuBar = getMenuBar(appElement) else {
      throw MenuError.menuBarNotFound(resolvedApp.localizedName ?? "Unknown")
    }

    if path.isEmpty {
      // List top-level menu bar items
      let children = getChildren(menuBar)
      return children.compactMap { menuItemInfo($0) }
    }

    // Navigate to path and list children
    var currentElement = menuBar
    for pathComponent in path {
      let children = getChildren(currentElement)

      guard let match = findChild(named: pathComponent, in: children) else {
        let available = children.compactMap { getTitle($0) }
        throw MenuError.menuItemNotFound(pathComponent, available: available)
      }

      // Press to open submenu, then get children
      AXUIElementPerformAction(match, kAXPressAction as CFString)
      usleep(100_000)  // 100ms for menu to render

      if let submenu = getSubmenu(match) {
        currentElement = submenu
      } else {
        throw MenuError.noSubmenu(pathComponent)
      }
    }

    let children = getChildren(currentElement)
    let items = children.compactMap { menuItemInfo($0) }

    // Press Escape to close any open menus
    cancelMenus()

    return items
  }

  // MARK: - Private Helpers

  private func resolveApp(_ appName: String?) throws -> NSRunningApplication {
    if let appName = appName {
      let apps = NSWorkspace.shared.runningApplications.filter {
        $0.localizedName?.lowercased() == appName.lowercased()
      }
      guard let app = apps.first else {
        throw MenuError.appNotFound(appName)
      }
      // Activate app so its menu bar is accessible
      app.activate()
      usleep(200_000)  // 200ms for activation
      return app
    } else {
      // Use frontmost app
      guard let app = NSWorkspace.shared.frontmostApplication else {
        throw MenuError.noFrontmostApp
      }
      return app
    }
  }

  private func getMenuBar(_ appElement: AXUIElement) -> AXUIElement? {
    var menuBarRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(
      appElement, kAXMenuBarAttribute as CFString, &menuBarRef)
    guard err == .success else { return nil }
    return (menuBarRef as! AXUIElement)
  }

  private func getChildren(_ element: AXUIElement) -> [AXUIElement] {
    var childrenRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    guard err == .success, let children = childrenRef as? [AXUIElement] else {
      return []
    }
    return children
  }

  private func getSubmenu(_ menuItem: AXUIElement) -> AXUIElement? {
    // Try to get submenu from the menu item directly
    var submenuRef: CFTypeRef?

    // First try AXMenu (for menu bar items, clicking opens a menu child)
    let children = getChildren(menuItem)
    for child in children {
      var roleRef: CFTypeRef?
      AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
      if let role = roleRef as? String, role == "AXMenu" {
        return child
      }
    }

    // Also try direct AXMenu attribute
    let err = AXUIElementCopyAttributeValue(menuItem, "AXMenu" as CFString, &submenuRef)
    if err == .success {
      return (submenuRef as! AXUIElement)
    }

    return nil
  }

  private func getTitle(_ element: AXUIElement) -> String? {
    var titleRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    guard err == .success, let title = titleRef as? String else { return nil }
    return title
  }

  private func findChild(named name: String, in children: [AXUIElement]) -> AXUIElement? {
    // Exact match first
    for child in children {
      if let title = getTitle(child), title == name {
        return child
      }
    }
    // Case-insensitive match
    for child in children {
      if let title = getTitle(child), title.lowercased() == name.lowercased() {
        return child
      }
    }
    // Partial match
    for child in children {
      if let title = getTitle(child), title.lowercased().contains(name.lowercased()) {
        return child
      }
    }
    return nil
  }

  private func menuItemInfo(_ element: AXUIElement) -> MenuItem? {
    let title = getTitle(element) ?? ""

    // Skip separator items (empty title)
    if title.isEmpty {
      // Check if it's a separator
      var roleRef: CFTypeRef?
      AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
      if let role = roleRef as? String, role == "AXMenuItem" {
        // It's a separator with empty title, include it
        return MenuItem(title: "---", enabled: false, hasSubmenu: false, shortcut: nil)
      }
      return nil
    }

    // Check if enabled
    var enabledRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef)
    let enabled = (enabledRef as? Bool) ?? true

    // Check for submenu
    let hasSubmenu = !getChildren(element).isEmpty || getSubmenu(element) != nil

    // Get keyboard shortcut
    var shortcutRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &shortcutRef)
    var shortcut: String? = nil
    if let cmdChar = shortcutRef as? String, !cmdChar.isEmpty {
      // Get modifier keys
      var modifiersRef: CFTypeRef?
      AXUIElementCopyAttributeValue(
        element, kAXMenuItemCmdModifiersAttribute as CFString, &modifiersRef)
      let modifiers = (modifiersRef as? Int) ?? 0

      var modStr = ""
      // kAXMenuItemModifierControl = 2, kAXMenuItemModifierOption = 1, kAXMenuItemModifierShift = 4
      // Default (0) = Cmd only
      if modifiers & 4 != 0 { modStr += "⇧" }
      if modifiers & 2 != 0 { modStr += "⌃" }
      if modifiers & 1 != 0 { modStr += "⌥" }
      modStr += "⌘"
      shortcut = modStr + cmdChar
    }

    return MenuItem(title: title, enabled: enabled, hasSubmenu: hasSubmenu, shortcut: shortcut)
  }

  private func cancelMenus() {
    // Post Escape key to close open menus
    if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: true) {
      event.post(tap: .cghidEventTap)
    }
    if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: false) {
      event.post(tap: .cghidEventTap)
    }
  }
}

// MARK: - Menu Errors

public enum MenuError: LocalizedError {
  case appNotFound(String)
  case noFrontmostApp
  case menuBarNotFound(String)
  case menuItemNotFound(String, available: [String])
  case noSubmenu(String)
  case clickFailed(String)
  case invalidPath(String)
  case dockNotFound
  case dockItemNotFound(String, available: [String])

  public var errorDescription: String? {
    switch self {
    case .appNotFound(let name):
      return "Application not found or not running: \(name)"
    case .noFrontmostApp:
      return "No frontmost application"
    case .menuBarNotFound(let name):
      return "Menu bar not accessible for: \(name)"
    case .menuItemNotFound(let item, let available):
      let availStr = available.isEmpty ? "" : " Available: \(available.joined(separator: ", "))"
      return "Menu item not found: \(item).\(availStr)"
    case .noSubmenu(let item):
      return "Menu item has no submenu: \(item)"
    case .clickFailed(let item):
      return "Failed to click menu item: \(item)"
    case .invalidPath(let msg):
      return "Invalid menu path: \(msg)"
    case .dockNotFound:
      return "Dock not found. Is the Dock running?"
    case .dockItemNotFound(let name, let available):
      let availStr = available.isEmpty ? "" : " Available: \(available.joined(separator: ", "))"
      return "Dock item not found: \(name).\(availStr)"
    }
  }
}
