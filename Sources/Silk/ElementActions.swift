// ElementActions.swift - High-level actions on discovered accessibility elements
// Bridges SilkAccessibility.Element with MouseController, TrailOverlay, and SilkCore.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import SilkAccessibility
import SilkCore
import SilkHumanization
import SilkKeyboard
import SilkVision

/// Errors specific to element actions.
public enum ElementActionError: Error, Sendable {
  /// The element has zero size or is off-screen.
  case elementNotVisible(String)
  /// AXPerformAction or AXSetValue failed.
  case actionFailed(action: String, axError: AXError)
  /// Could not read a value from the element.
  case readFailed(String)
  /// Screenshot capture failed.
  case captureFailed(String)
}

/// High-level action layer that operates on `SilkAccessibility.Element`.
///
/// All mouse movement is delegated to `MouseController` (which already has
/// humanised Bézier curves, Fitts's-law timing, and `TrailOverlay` support).
/// Keyboard and AX actions go through `SilkCore.EventPoster`.
public final class ElementActions {

  // MARK: - Dependencies

  private let mouse: MouseController
  private let eventPoster: EventPoster

  // MARK: - Init

  /// Create an action layer.
  /// - Parameters:
  ///   - mouse: Reuse an existing `MouseController` (shares its `EventPoster`).
  ///   - eventPoster: Poster for keyboard events. Defaults to `CGEventPoster()`.
  public init(
    mouse: MouseController = MouseController(),
    eventPoster: EventPoster = CGEventPoster()
  ) {
    self.mouse = mouse
    self.eventPoster = eventPoster
  }

  // MARK: - Click

  /// Move to an element's centre and click it.
  ///
  /// Uses `MouseController.moveTo` for movement (with optional humanisation
  /// and trail overlay), then `MouseController.click` for the press/release.
  ///
  /// - Parameters:
  ///   - element: The target element.
  ///   - button: Mouse button. Defaults to `.left`.
  ///   - humanize: Use natural Bézier movement.
  ///   - showTrail: Draw a cyan trail (requires `humanize`).
  ///   - trailDuration: Seconds the trail lingers after movement completes.
  public func click(
    _ element: Element,
    button: MouseButton = .left,
    humanize: Bool = false,
    showTrail: Bool = false,
    trailDuration: TimeInterval = 3.0
  ) async throws {
    SilkLogger.action.info(
      "Clicking element: \(element.role) '\(element.title ?? "(untitled)")' at (\(element.center.x), \(element.center.y))"
    )
    let point = try validCenter(element)

    // Activate the owning application so the click is routed correctly
    try activateOwningApp(of: element)
    try await Task.sleep(nanoseconds: 50_000_000)  // 50 ms for activation

    // Move (optionally humanised)
    try await mouse.moveTo(
      x: point.x,
      y: point.y,
      humanize: humanize,
      showTrail: showTrail,
      trailDuration: trailDuration
    )

    // Click
    try await mouse.click(x: point.x, y: point.y, button: button)
    SilkLogger.action.debug("Click completed")
  }

  // MARK: - Type

  /// Click an element to focus it, then type text via keyboard events.
  ///
  /// For text fields (including web form inputs), first attempts to set the
  /// value directly via the accessibility API (`kAXValueAttribute`). Falls
  /// back to clicking + keyboard event injection if AXSetValue fails.
  ///
  /// - Parameters:
  ///   - element: A text field or similar editable element.
  ///   - text: The string to type.
  ///   - humanize: Humanise the initial click movement.
  public func type(
    _ element: Element,
    text: String,
    humanize: Bool = false
  ) async throws {
    SilkLogger.action.info(
      "Typing into element: \(element.role) '\(element.title ?? "(untitled)")' - text length: \(text.count)"
    )

    // Activate the owning application so keyboard events are routed correctly.
    try activateOwningApp(of: element)
    try await Task.sleep(nanoseconds: 50_000_000)  // 50 ms for activation

    // Click to focus the element first
    try await click(element, humanize: humanize)

    // Explicitly request focus via AX API
    AXUIElementSetAttributeValue(
      element.axElement,
      kAXFocusedAttribute as CFString,
      true as CFTypeRef
    )

    // Wait for focus to settle
    try await Task.sleep(nanoseconds: 200_000_000)  // 200 ms

    // Strategy 1: Try AXSetValue directly (fast path for some text fields)
    let setResult = AXUIElementSetAttributeValue(
      element.axElement,
      kAXValueAttribute as CFString,
      text as CFTypeRef
    )
    if setResult == .success {
      // Verify the value actually stuck (Safari returns success but may not set it)
      try await Task.sleep(nanoseconds: 50_000_000)  // 50 ms for value to propagate
      let verifiedValue: String? = axLiveAttribute(element.axElement, kAXValueAttribute as String)
      if verifiedValue == text {
        SilkLogger.action.debug("Set value via AXSetValue successfully")
        return
      }
      SilkLogger.action.debug(
        "AXSetValue returned success but value didn't stick ('\(verifiedValue ?? "nil")' != '\(text)'), falling back to keyboard events"
      )
    } else {
      SilkLogger.action.debug("AXSetValue failed (\(setResult.rawValue)), using keyboard events")
    }

    // Strategy 2: Type via CGEvents (works for web forms and most native fields)
    for char in text {
      guard let (keyCode, shift) = KeyboardController.keyMapping(for: char) else {
        // For characters without a direct key mapping, use the
        // CGEvent keyboard method with Unicode string injection.
        try typeUnicode(char)
        continue
      }
      var flags: CGEventFlags = []
      if shift { flags.insert(.maskShift) }

      try eventPoster.postKeyPress(keyCode: keyCode, down: true, flags: flags)
      // Natural inter-key delay (30–80 ms)
      let delay = Double.random(in: 0.030...0.080)
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      try eventPoster.postKeyPress(keyCode: keyCode, down: false, flags: flags)
    }
    SilkLogger.action.debug("Typing completed")
  }

  // MARK: - Read

  /// Read the textual content of an element.
  ///
  /// Tries, in order: `kAXValueAttribute`, `kAXTitleAttribute`,
  /// `kAXDescriptionAttribute`. Falls back to `Element.label`.
  ///
  /// - Parameter element: The element to read.
  /// - Returns: A string representation of the element's content.
  public func read(_ element: Element) throws -> String {
    // Try live AX value first (most up-to-date)
    if let live: String = axLiveAttribute(element.axElement, kAXValueAttribute as String) {
      return live
    }
    if let live: String = axLiveAttribute(element.axElement, kAXTitleAttribute as String) {
      return live
    }
    if let live: String = axLiveAttribute(element.axElement, kAXDescriptionAttribute as String) {
      return live
    }
    // Fall back to the snapshot captured at discovery time
    return element.label
  }

  // MARK: - Capture

  /// Capture a screenshot of the element's bounding rectangle.
  ///
  /// Uses `SilkVision.ScreenCapture` (ScreenCaptureKit) with the element's frame.
  ///
  /// - Parameter element: The element to capture.
  /// - Returns: A `CGImage` of the element's screen region.
  public func capture(_ element: Element) async throws -> CGImage {
    let frame = element.frame
    guard frame.width > 0, frame.height > 0 else {
      throw ElementActionError.elementNotVisible("Element has zero size")
    }

    return try await ScreenCapture.capture(region: frame)
  }

  // MARK: - AX Actions

  /// Perform a named accessibility action on the element (e.g. "AXPress", "AXShowMenu").
  public func performAction(_ element: Element, action: String) throws {
    let result = AXUIElementPerformAction(element.axElement, action as CFString)
    guard result == .success else {
      throw ElementActionError.actionFailed(action: action, axError: result)
    }
  }

  // MARK: - Private Helpers

  /// Activate (bring to front) the application that owns the given element.
  private func activateOwningApp(of element: Element) throws {
    var pid: pid_t = 0
    let result = AXUIElementGetPid(element.axElement, &pid)
    guard result == .success, pid != 0 else {
      SilkLogger.action.debug("Could not determine PID for element, skipping activation")
      return
    }
    if let app = NSRunningApplication(processIdentifier: pid) {
      app.activate()
      SilkLogger.action.debug("Activated app PID \(pid)")
    }
  }

  /// Validate the element is visible and return its centre point.
  private func validCenter(_ element: Element) throws -> CGPoint {
    let center = element.center
    guard element.size.width > 0, element.size.height > 0 else {
      throw ElementActionError.elementNotVisible(
        "Element '\(element.label)' has zero size (\(element.size))"
      )
    }
    return center
  }

  /// Live-fetch a single string attribute from an AXUIElement.
  private func axLiveAttribute<T>(_ ax: AXUIElement, _ attribute: String) -> T? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(ax, attribute as CFString, &value)
    guard result == .success else { return nil }
    return value as? T
  }

  /// Type a single Unicode character via CGEvent string injection.
  private func typeUnicode(_ char: Character) throws {
    let str = String(char)
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
      throw ElementActionError.actionFailed(action: "typeUnicode", axError: .failure)
    }
    event.keyboardSetUnicodeString(
      stringLength: str.utf16.count,
      unicodeString: Array(str.utf16))
    event.post(tap: .cghidEventTap)

    // Key up
    guard let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
      return
    }
    upEvent.post(tap: .cghidEventTap)
  }

}
