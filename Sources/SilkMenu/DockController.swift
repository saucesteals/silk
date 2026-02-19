import AppKit
import ApplicationServices
import Foundation

public final class DockController: Sendable {

  public init() {}

  /// Click a dock icon to launch/activate an app, or right-click for context menu
  public func click(_ options: DockClickOptions) throws -> DockResult {
    let start = DispatchTime.now()

    let dockList = try getDockItemList()
    let children = getChildren(dockList)

    guard let item = findDockItem(named: options.appName, in: children) else {
      let available = children.compactMap { getTitle($0) }.filter { !$0.isEmpty }
      throw MenuError.dockItemNotFound(options.appName, available: available)
    }

    if options.rightClick {
      // Show context menu via AXShowMenu action
      let err = AXUIElementPerformAction(item, kAXShowMenuAction as CFString)
      if err != .success {
        // Fallback: try AXPress
        AXUIElementPerformAction(item, kAXPressAction as CFString)
      }
    } else {
      // Regular click: launch/activate
      let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
      guard err == .success else {
        throw MenuError.clickFailed(options.appName)
      }
    }

    let durationMs = Int(
      (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)

    return DockResult(
      action: options.rightClick ? "right-click" : "click",
      appName: options.appName,
      success: true,
      durationMs: durationMs
    )
  }

  /// List all apps in the dock
  public func listApps() throws -> [DockApp] {
    let dockList = try getDockItemList()
    let children = getChildren(dockList)

    let runningApps = NSWorkspace.shared.runningApplications
    let runningBundleIds = Set(runningApps.compactMap { $0.bundleIdentifier })

    var apps: [DockApp] = []

    for child in children {
      guard let title = getTitle(child), !title.isEmpty else { continue }

      // Skip separator/spacer items
      var roleRef: CFTypeRef?
      AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &roleRef)
      if let subrole = roleRef as? String, subrole.contains("Separator") {
        continue
      }

      // Try to get the URL to determine bundle ID
      var urlRef: CFTypeRef?
      AXUIElementCopyAttributeValue(child, kAXURLAttribute as CFString, &urlRef)
      var bundleId = ""
      if let url = urlRef as? URL ?? (urlRef as? String).flatMap({ URL(string: $0) }) {
        bundleId = Bundle(url: url)?.bundleIdentifier ?? ""
      }

      // Fallback: look up bundle ID from running apps by name
      if bundleId.isEmpty {
        if let running = runningApps.first(where: { $0.localizedName == title }) {
          bundleId = running.bundleIdentifier ?? ""
        }
      }

      // Fallback: search /Applications
      if bundleId.isEmpty {
        bundleId = bundleIdFromApplications(title) ?? ""
      }

      let isRunning: Bool
      if !bundleId.isEmpty {
        isRunning = runningBundleIds.contains(bundleId)
      } else {
        // Check by name
        isRunning = runningApps.contains { $0.localizedName == title }
      }

      apps.append(
        DockApp(
          name: title,
          bundleId: bundleId,
          isRunning: isRunning
        ))
    }

    return apps
  }

  // MARK: - Private Helpers

  private func getDockItemList() throws -> AXUIElement {
    // Find the Dock process
    guard
      let dockApp = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.dock"
      ).first
    else {
      throw MenuError.dockNotFound
    }

    let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)

    // Get children of the Dock app element - the dock item list
    let children = getChildren(dockElement)

    // The dock typically has a single AXList child containing all items
    for child in children {
      var roleRef: CFTypeRef?
      AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
      if let role = roleRef as? String, role == "AXList" {
        return child
      }
    }

    // If no AXList found, try using the dock element directly
    guard !children.isEmpty else {
      throw MenuError.dockNotFound
    }

    return dockElement
  }

  private func getChildren(_ element: AXUIElement) -> [AXUIElement] {
    var childrenRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    guard err == .success, let children = childrenRef as? [AXUIElement] else {
      return []
    }
    return children
  }

  private func getTitle(_ element: AXUIElement) -> String? {
    var titleRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    guard err == .success, let title = titleRef as? String else { return nil }
    return title
  }

  private func findDockItem(named name: String, in children: [AXUIElement]) -> AXUIElement? {
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

  private func bundleIdFromApplications(_ appName: String) -> String? {
    let paths = [
      "/Applications/\(appName).app",
      "/System/Applications/\(appName).app",
      NSString(string: "~/Applications/\(appName).app").expandingTildeInPath,
    ]
    for path in paths {
      if let bundle = Bundle(path: path) {
        return bundle.bundleIdentifier
      }
    }
    return nil
  }
}

// kAXShowMenuAction is not always available as a constant
private let kAXShowMenuAction = "AXShowMenu"
