import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Errors specific to window operations
public enum WindowError: LocalizedError {
  case appNotFound(String)
  case appNotRunning(String)
  case windowNotFound(String)
  case accessibilityError(String)
  case permissionDenied
  case operationFailed(String)

  public var errorDescription: String? {
    switch self {
    case .appNotFound(let name):
      return "Application not found: \(name)"
    case .appNotRunning(let name):
      return "Application not running: \(name)"
    case .windowNotFound(let detail):
      return "Window not found: \(detail)"
    case .accessibilityError(let msg):
      return "Accessibility API error: \(msg)"
    case .permissionDenied:
      return
        "Accessibility permission denied. Grant access in System Settings > Privacy & Security > Accessibility."
    case .operationFailed(let msg):
      return "Window operation failed: \(msg)"
    }
  }
}

public final class WindowController: Sendable {

  public init() {}

  // MARK: - Public API

  /// Move window to coordinates
  public func move(_ options: WindowMoveOptions) throws -> WindowResult {
    let start = DispatchTime.now()

    let (window, appName, windowTitle) = try findWindow(options.identifier)

    var point = CGPoint(x: CGFloat(options.x), y: CGFloat(options.y))
    let pointValue = AXValueCreate(.cgPoint, &point)!

    let setResult = AXUIElementSetAttributeValue(
      window, kAXPositionAttribute as CFString, pointValue)
    guard setResult == .success else {
      throw WindowError.operationFailed("Failed to set position (error: \(setResult.rawValue))")
    }

    // Read back actual position
    var actualPos = CGPoint.zero
    if let posValue = try? getAXValue(window, attribute: kAXPositionAttribute) {
      AXValueGetValue(posValue, .cgPoint, &actualPos)
    }

    let elapsed = elapsedMs(since: start)

    return WindowResult(
      action: "move",
      appName: appName,
      windowTitle: windowTitle,
      success: true,
      x: Int(actualPos.x),
      y: Int(actualPos.y),
      durationMs: elapsed
    )
  }

  /// Resize window
  public func resize(_ options: WindowResizeOptions) throws -> WindowResult {
    let start = DispatchTime.now()

    let (window, appName, windowTitle) = try findWindow(options.identifier)

    var size = CGSize(width: CGFloat(options.width), height: CGFloat(options.height))
    let sizeValue = AXValueCreate(.cgSize, &size)!

    let setResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    guard setResult == .success else {
      throw WindowError.operationFailed("Failed to set size (error: \(setResult.rawValue))")
    }

    // Read back actual size
    var actualSize = CGSize.zero
    if let sizeVal = try? getAXValue(window, attribute: kAXSizeAttribute) {
      AXValueGetValue(sizeVal, .cgSize, &actualSize)
    }

    let elapsed = elapsedMs(since: start)

    return WindowResult(
      action: "resize",
      appName: appName,
      windowTitle: windowTitle,
      success: true,
      width: Int(actualSize.width),
      height: Int(actualSize.height),
      durationMs: elapsed
    )
  }

  /// Close window
  public func close(_ options: WindowCloseOptions) throws -> WindowResult {
    let start = DispatchTime.now()

    let (window, appName, windowTitle) = try findWindow(options.identifier)

    // Try close button first
    var closeButton: AnyObject?
    let closeResult = AXUIElementCopyAttributeValue(
      window, kAXCloseButtonAttribute as CFString, &closeButton)

    if closeResult == .success, let button = closeButton {
      let pressResult = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
      guard pressResult == .success else {
        throw WindowError.operationFailed(
          "Failed to press close button (error: \(pressResult.rawValue))")
      }
    } else {
      throw WindowError.operationFailed("No close button available for this window")
    }

    let elapsed = elapsedMs(since: start)

    return WindowResult(
      action: "close",
      appName: appName,
      windowTitle: windowTitle,
      success: true,
      durationMs: elapsed
    )
  }

  /// Change window state (minimize/maximize/restore/fullscreen)
  public func setState(_ options: WindowStateOptions) throws -> WindowResult {
    let start = DispatchTime.now()

    let (window, appName, windowTitle) = try findWindow(options.identifier)

    switch options.state {
    case .minimize:
      let result = AXUIElementSetAttributeValue(
        window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
      guard result == .success else {
        throw WindowError.operationFailed("Failed to minimize (error: \(result.rawValue))")
      }

    case .maximize:
      // "Maximize" = zoom button (Option+Green button behavior)
      // First, get screen size for the current screen
      let screenFrame = screenFrameForWindow(window)

      // Set position to top-left of visible screen area
      var origin = CGPoint(x: screenFrame.origin.x, y: screenFrame.origin.y)
      let originValue = AXValueCreate(.cgPoint, &origin)!
      AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)

      // Set size to fill the screen
      var size = CGSize(width: screenFrame.width, height: screenFrame.height)
      let sizeValue = AXValueCreate(.cgSize, &size)!
      AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

    case .restore:
      // Un-minimize if minimized
      var minimizedValue: AnyObject?
      AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
      if let minimized = minimizedValue as? Bool, minimized {
        let result = AXUIElementSetAttributeValue(
          window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard result == .success else {
          throw WindowError.operationFailed("Failed to restore (error: \(result.rawValue))")
        }
      }

      // Un-fullscreen if fullscreen
      var fullscreenValue: AnyObject?
      AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenValue)
      if let fullscreen = fullscreenValue as? Bool, fullscreen {
        let result = AXUIElementSetAttributeValue(
          window, "AXFullScreen" as CFString, kCFBooleanFalse)
        guard result == .success else {
          throw WindowError.operationFailed("Failed to exit fullscreen (error: \(result.rawValue))")
        }
      }

    case .fullscreen:
      // Toggle fullscreen
      var fullscreenValue: AnyObject?
      AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenValue)
      let isFullscreen = (fullscreenValue as? Bool) ?? false
      let newValue: CFBoolean = isFullscreen ? kCFBooleanFalse : kCFBooleanTrue
      let result = AXUIElementSetAttributeValue(
        window, "AXFullScreen" as CFString, newValue as AnyObject)
      guard result == .success else {
        throw WindowError.operationFailed("Failed to toggle fullscreen (error: \(result.rawValue))")
      }
    }

    let elapsed = elapsedMs(since: start)

    return WindowResult(
      action: options.state.rawValue,
      appName: appName,
      windowTitle: windowTitle,
      success: true,
      durationMs: elapsed
    )
  }

  /// List all windows
  public func listWindows(app: String? = nil) throws -> [WindowInfo] {
    var results: [WindowInfo] = []

    let runningApps: [NSRunningApplication]
    if let appName = app {
      guard let found = findRunningApp(named: appName) else {
        throw WindowError.appNotRunning(appName)
      }
      runningApps = [found]
    } else {
      runningApps = NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular
      }
    }

    for runningApp in runningApps {
      guard let name = runningApp.localizedName else { continue }
      let pid = runningApp.processIdentifier
      let appElement = AXUIElementCreateApplication(pid)

      var windowsValue: AnyObject?
      let axResult = AXUIElementCopyAttributeValue(
        appElement, kAXWindowsAttribute as CFString, &windowsValue)
      guard axResult == .success, let windows = windowsValue as? [AXUIElement] else {
        continue
      }

      for window in windows {
        let title = getStringAttribute(window, attribute: kAXTitleAttribute) ?? ""

        var pos = CGPoint.zero
        if let posValue = try? getAXValue(window, attribute: kAXPositionAttribute) {
          AXValueGetValue(posValue, .cgPoint, &pos)
        }

        var size = CGSize.zero
        if let sizeValue = try? getAXValue(window, attribute: kAXSizeAttribute) {
          AXValueGetValue(sizeValue, .cgSize, &size)
        }

        var minimizedValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
        let isMinimized = (minimizedValue as? Bool) ?? false

        var fullscreenValue: AnyObject?
        AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenValue)
        let isFullscreen = (fullscreenValue as? Bool) ?? false

        results.append(
          WindowInfo(
            appName: name,
            title: title,
            x: Int(pos.x),
            y: Int(pos.y),
            width: Int(size.width),
            height: Int(size.height),
            isMinimized: isMinimized,
            isFullscreen: isFullscreen
          ))
      }
    }

    return results
  }

  // MARK: - Private Helpers

  /// Find a window matching the identifier
  private func findWindow(_ identifier: WindowIdentifier) throws -> (AXUIElement, String, String?) {
    guard let appName = identifier.app else {
      throw WindowError.appNotFound("No app name specified")
    }

    guard let runningApp = findRunningApp(named: appName) else {
      throw WindowError.appNotRunning(appName)
    }

    let pid = runningApp.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    // Get windows
    var windowsValue: AnyObject?
    let axResult = AXUIElementCopyAttributeValue(
      appElement, kAXWindowsAttribute as CFString, &windowsValue)
    guard axResult == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty
    else {
      throw WindowError.windowNotFound("No windows found for \(appName)")
    }

    // Filter by title if specified
    if let titleFilter = identifier.title {
      let lowered = titleFilter.lowercased()
      for window in windows {
        let title = getStringAttribute(window, attribute: kAXTitleAttribute) ?? ""
        if title.lowercased().contains(lowered) {
          return (window, runningApp.localizedName ?? appName, title)
        }
      }
      throw WindowError.windowNotFound("No window matching title '\(titleFilter)' in \(appName)")
    }

    // Filter by index if specified
    if let index = identifier.index {
      guard index >= 0, index < windows.count else {
        throw WindowError.windowNotFound(
          "Window index \(index) out of range (0-\(windows.count - 1)) for \(appName)")
      }
      let window = windows[index]
      let title = getStringAttribute(window, attribute: kAXTitleAttribute)
      return (window, runningApp.localizedName ?? appName, title)
    }

    // Default: first (frontmost) window
    let window = windows[0]
    let title = getStringAttribute(window, attribute: kAXTitleAttribute)
    return (window, runningApp.localizedName ?? appName, title)
  }

  /// Find a running application by name (case-insensitive)
  private func findRunningApp(named name: String) -> NSRunningApplication? {
    let lowered = name.lowercased()
    return NSWorkspace.shared.runningApplications.first { app in
      guard let appName = app.localizedName else { return false }
      return appName.lowercased() == lowered
    }
  }

  /// Get a string attribute from an AXUIElement
  private func getStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else { return nil }
    return value as? String
  }

  /// Get an AXValue attribute from an AXUIElement
  private func getAXValue(_ element: AXUIElement, attribute: String) throws -> AXValue {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
      throw WindowError.accessibilityError("Failed to get \(attribute)")
    }
    return (axValue as! AXValue)
  }

  /// Get the visible screen frame for the screen containing the window
  private func screenFrameForWindow(_ window: AXUIElement) -> CGRect {
    // Get window position to determine which screen it's on
    var pos = CGPoint.zero
    if let posValue = try? getAXValue(window, attribute: kAXPositionAttribute) {
      AXValueGetValue(posValue, .cgPoint, &pos)
    }

    // Find the screen containing this point
    // Convert CG coordinates to NSScreen coordinates for matching
    let screens = NSScreen.screens
    for screen in screens {
      let frame = screen.frame
      let visibleFrame = screen.visibleFrame
      // NSScreen uses bottom-left origin, CG uses top-left
      // Convert visible frame to CG coordinates
      let mainHeight = NSScreen.screens.first?.frame.height ?? frame.height
      let cgVisibleY = mainHeight - visibleFrame.origin.y - visibleFrame.height
      let cgVisible = CGRect(
        x: visibleFrame.origin.x, y: cgVisibleY, width: visibleFrame.width,
        height: visibleFrame.height)

      let cgFrame = CGRect(
        x: frame.origin.x, y: mainHeight - frame.origin.y - frame.height, width: frame.width,
        height: frame.height)
      if cgFrame.contains(pos) {
        return cgVisible
      }
    }

    // Fallback to main screen visible frame
    if let main = NSScreen.main {
      let visible = main.visibleFrame
      let mainHeight = main.frame.height
      let cgY = mainHeight - visible.origin.y - visible.height
      return CGRect(x: visible.origin.x, y: cgY, width: visible.width, height: visible.height)
    }

    return CGRect(x: 0, y: 0, width: 1920, height: 1080)
  }

  /// Calculate elapsed time in milliseconds
  private func elapsedMs(since start: DispatchTime) -> Int {
    let end = DispatchTime.now()
    let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
    return Int(nanos / 1_000_000)
  }
}
