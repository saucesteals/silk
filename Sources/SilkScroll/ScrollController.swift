import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import SilkCore

/// High-level scroll controller for programmatic scrolling
public final class ScrollController: Sendable {
  private let eventPoster: EventPoster

  /// Pixels per unit of scroll amount
  private let pixelsPerUnit: Int32 = 10

  public init(eventPoster: EventPoster = CGEventPoster()) {
    self.eventPoster = eventPoster
  }

  /// Perform scroll operation
  /// - Parameter options: Scroll configuration
  /// - Returns: Result with timing info
  /// - Throws: SilkError if scroll fails or element not found
  public func scroll(_ options: ScrollOptions) async throws -> ScrollResult {
    let start = CFAbsoluteTimeGetCurrent()

    // Position cursor at target if needed
    switch options.target {
    case .global:
      break
    case .point(let point):
      try eventPoster.postMouseMove(to: point)
      try await Task.sleep(for: .milliseconds(10))
    case .element(let name, let app):
      let point = try resolveElementCenter(name: name, app: app)
      try eventPoster.postMouseMove(to: point)
      try await Task.sleep(for: .milliseconds(10))
    }

    // Calculate scroll delta in pixels
    let totalPixels = Int32(options.amount) * pixelsPerUnit
    let (deltaY, deltaX) = scrollDelta(
      direction: options.direction, pixels: totalPixels
    )

    // Execute scroll
    if options.smooth {
      let steps = max(options.amount * 2, 5)
      try await smoothScroll(deltaY: deltaY, deltaX: deltaX, steps: steps)
    } else {
      try eventPoster.postScroll(deltaY: deltaY, deltaX: deltaX)
    }

    let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

    return ScrollResult(
      direction: options.direction.rawValue,
      amount: options.amount,
      durationMs: elapsed,
      smooth: options.smooth
    )
  }

  /// Convenience: scroll in the active window
  public func scroll(
    direction: ScrollDirection,
    amount: Int = 3,
    smooth: Bool = false
  ) async throws -> ScrollResult {
    try await scroll(
      ScrollOptions(
        direction: direction,
        amount: amount,
        smooth: smooth,
        target: .global
      ))
  }

  /// Convenience: scroll at a specific point
  public func scroll(
    at point: CGPoint,
    direction: ScrollDirection,
    amount: Int = 3,
    smooth: Bool = false
  ) async throws -> ScrollResult {
    try await scroll(
      ScrollOptions(
        direction: direction,
        amount: amount,
        smooth: smooth,
        target: .point(point)
      ))
  }

  // MARK: - Private

  /// Convert scroll direction and pixel amount to CGEvent delta values
  private func scrollDelta(
    direction: ScrollDirection,
    pixels: Int32
  ) -> (Int32, Int32) {
    // CGEvent scroll wheel convention (pixel units):
    //   wheel1 > 0 → viewport scrolls UP (content moves down on screen)
    //   wheel1 < 0 → viewport scrolls DOWN (content moves up on screen)
    //   wheel2 > 0 → viewport scrolls LEFT
    //   wheel2 < 0 → viewport scrolls RIGHT
    switch direction {
    case .up: return (pixels, 0)
    case .down: return (-pixels, 0)
    case .left: return (0, pixels)
    case .right: return (0, -pixels)
    }
  }

  /// Perform smooth scrolling by sending multiple small scroll events
  private func smoothScroll(
    deltaY: Int32,
    deltaX: Int32,
    steps: Int
  ) async throws {
    // Use floating-point division and accumulator to avoid zero-delta steps
    let deltaYFloat = Double(deltaY)
    let deltaXFloat = Double(deltaX)
    let stepsFloat = Double(steps)

    var accumulatedY: Double = 0.0
    var accumulatedX: Double = 0.0
    var sentY: Int32 = 0
    var sentX: Int32 = 0

    for _ in 0..<steps {
      accumulatedY += deltaYFloat / stepsFloat
      accumulatedX += deltaXFloat / stepsFloat

      let targetY = Int32(accumulatedY.rounded())
      let targetX = Int32(accumulatedX.rounded())

      let dy = targetY - sentY
      let dx = targetX - sentX

      // Skip posting zero-delta events to avoid wasted time
      if dy == 0 && dx == 0 {
        continue
      }

      sentY = targetY
      sentX = targetX

      try eventPoster.postScroll(deltaY: dy, deltaX: dx)
      try await Task.sleep(for: .milliseconds(Int.random(in: 15...30)))
    }
  }

  // MARK: - Element Resolution

  /// Find a UI element by name and return its center point
  private func resolveElementCenter(
    name: String,
    app: String?
  ) throws -> CGPoint {
    let runningApps: [NSRunningApplication]

    if let appName = app {
      runningApps = NSWorkspace.shared.runningApplications.filter {
        $0.localizedName?.localizedCaseInsensitiveCompare(appName)
          == .orderedSame
      }
    } else {
      runningApps = NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular
      }
    }

    for runningApp in runningApps {
      let appElement = AXUIElementCreateApplication(
        runningApp.processIdentifier
      )
      if let center = findElementCenter(
        in: appElement, matching: name, maxDepth: 10
      ) {
        return center
      }
    }

    throw SilkError.systemAPIError("Element '\(name)' not found")
  }

  /// Recursively search for an element matching the given name
  private func findElementCenter(
    in element: AXUIElement,
    matching name: String,
    maxDepth: Int,
    depth: Int = 0
  ) -> CGPoint? {
    guard depth < maxDepth else { return nil }

    // Check if this element matches
    if elementMatchesName(element, name) {
      return centerPoint(of: element)
    }

    // Recurse into children
    var childrenRef: AnyObject?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXChildrenAttribute as CFString,
        &childrenRef
      ) == .success,
      let children = childrenRef as? [AXUIElement]
    else {
      return nil
    }

    for child in children {
      if let point = findElementCenter(
        in: child,
        matching: name,
        maxDepth: maxDepth,
        depth: depth + 1
      ) {
        return point
      }
    }

    return nil
  }

  /// Check if an element's title, description, or value contains the name
  private func elementMatchesName(
    _ element: AXUIElement,
    _ name: String
  ) -> Bool {
    var ref: AnyObject?

    if AXUIElementCopyAttributeValue(
      element, kAXTitleAttribute as CFString, &ref
    ) == .success,
      let title = ref as? String,
      title.localizedCaseInsensitiveContains(name)
    {
      return true
    }

    if AXUIElementCopyAttributeValue(
      element, kAXDescriptionAttribute as CFString, &ref
    ) == .success,
      let desc = ref as? String,
      desc.localizedCaseInsensitiveContains(name)
    {
      return true
    }

    if AXUIElementCopyAttributeValue(
      element, kAXValueAttribute as CFString, &ref
    ) == .success,
      let val = ref as? String,
      val.localizedCaseInsensitiveContains(name)
    {
      return true
    }

    return false
  }

  /// Get the center point of an AXUIElement
  private func centerPoint(of element: AXUIElement) -> CGPoint? {
    var posRef: AnyObject?
    var sizeRef: AnyObject?

    guard
      AXUIElementCopyAttributeValue(
        element, kAXPositionAttribute as CFString, &posRef
      ) == .success,
      AXUIElementCopyAttributeValue(
        element, kAXSizeAttribute as CFString, &sizeRef
      ) == .success
    else {
      return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero

    guard let posVal = posRef,
      CFGetTypeID(posVal) == AXValueGetTypeID(),
      AXValueGetValue(posVal as! AXValue, .cgPoint, &position),
      let sizeVal = sizeRef,
      CFGetTypeID(sizeVal) == AXValueGetTypeID(),
      AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
    else {
      return nil
    }

    return CGPoint(
      x: position.x + size.width / 2,
      y: position.y + size.height / 2
    )
  }
}
