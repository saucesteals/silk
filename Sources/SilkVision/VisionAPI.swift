import AppKit
import CoreGraphics
import Foundation
import SilkAccessibility

/// Unified vision API for screen capture and UI inspection
public final class Vision: Sendable {

  public init() {}

  // MARK: - Screenshot

  /// Capture a screenshot and save to file
  public func captureScreenshot(path: String, format: String = "png") async throws {
    let image = try await ScreenCapture.capture()
    try ScreenCapture.save(image, to: path)
  }

  // MARK: - Screen Bounds

  /// Get the main screen dimensions
  public func getScreenBounds() -> CGRect {
    guard let screen = NSScreen.main else {
      return CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }
    return screen.frame
  }

  // MARK: - UI Elements (Accessibility)

  private func elementToDict(_ el: Element) -> [String: Any] {
    var dict: [String: Any] = [:]
    dict["role"] = el.role
    dict["title"] = el.title ?? ""
    dict["value"] = el.value ?? ""
    let frame = el.frame
    dict["x"] = frame.origin.x
    dict["y"] = frame.origin.y
    dict["width"] = frame.size.width
    dict["height"] = frame.size.height
    return dict
  }

  /// Find UI elements matching criteria
  public func findElements(role: String? = nil, text: String? = nil) -> [[String: Any]] {
    if let text = text {
      let elements = AccessibilityQuery.findByText(text, role: role)
      return elements.map { elementToDict($0) }
    } else if let role = role {
      if let app = NSWorkspace.shared.frontmostApplication?.localizedName {
        let elements = AccessibilityQuery.findByRole(role, in: app)
        return elements.map { elementToDict($0) }
      }
    }
    return []
  }

  /// Get the UI element at specific screen coordinates
  public func getElementAt(x: CGFloat, y: CGFloat) -> [String: Any]? {
    guard let el = AccessibilityQuery.elementAt(x: x, y: y) else { return nil }
    return elementToDict(el)
  }

  /// Get info about the currently active/frontmost window
  public func getActiveWindow() -> [String: Any]? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var windowRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        == .success,
      let window = windowRef
    else { return nil }
    let axWindow = window as! AXUIElement
    var dict: [String: Any] = [:]
    dict["app"] = app.localizedName ?? ""
    dict["pid"] = app.processIdentifier

    var titleRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success
    {
      dict["title"] = titleRef as? String ?? ""
    }
    var posRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
      == .success
    {
      var point = CGPoint.zero
      AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
      dict["x"] = point.x
      dict["y"] = point.y
    }
    var sizeRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success {
      var size = CGSize.zero
      AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
      dict["width"] = size.width
      dict["height"] = size.height
    }
    return dict
  }
}
