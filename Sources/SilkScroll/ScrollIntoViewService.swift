// ScrollIntoViewService.swift - Auto-scroll elements into view
// Phase 1: MVP implementation for silk click auto-scroll

import ApplicationServices
import CoreGraphics
import Foundation
import SilkAccessibility
import SilkCore

/// Result of a scroll-into-view attempt
public struct ScrollIntoViewResult: Sendable, Encodable {
  public let success: Bool
  public let attempts: Int
  public let finalPosition: CGPoint
  public let scrolledBy: CGPoint
  public let method: String  // "AXScrollToVisible", "synthetic", or "failed"

  enum CodingKeys: String, CodingKey {
    case success, attempts
    case finalPosition = "final_position"
    case scrolledBy = "scrolled_by"
    case method
  }

  public init(
    success: Bool,
    attempts: Int,
    finalPosition: CGPoint,
    scrolledBy: CGPoint,
    method: String
  ) {
    self.success = success
    self.attempts = attempts
    self.finalPosition = finalPosition
    self.scrolledBy = scrolledBy
    self.method = method
  }
}

/// Errors specific to scroll-into-view operations
public enum ScrollIntoViewError: Error, CustomStringConvertible {
  case maxAttemptsExceeded(attempts: Int, progress: CGPoint)
  case hardTimeout
  case noScrollContainer
  case noProgress

  public var description: String {
    switch self {
    case .maxAttemptsExceeded(let attempts, let progress):
      return
        "Element could not be scrolled into view after \(attempts) attempts (made \(Int(abs(progress.y)))px progress)"
    case .hardTimeout:
      return "Scroll operation exceeded 10 second hard timeout"
    case .noScrollContainer:
      return "Element found but not visible and no scrollable container detected"
    case .noProgress:
      return "Scroll made no progress - element may be inside collapsed section or hidden container"
    }
  }
}

/// Service for scrolling elements into view
public final class ScrollIntoViewService: Sendable {
  private let eventPoster: EventPoster
  private let maxAttempts: Int
  private let settleDelayMs: Int
  private let hardTimeoutSeconds: Double
  private let margin: CGFloat

  /// Check if debug tracing is enabled
  private var traceEnabled: Bool {
    ProcessInfo.processInfo.environment["SILK_TRACE_SCROLL"] == "1"
  }

  public init(
    eventPoster: EventPoster = CGEventPoster(),
    maxAttempts: Int = 8,
    settleDelayMs: Int = 100,
    hardTimeoutSeconds: Double = 10.0,
    margin: CGFloat = 20.0
  ) {
    self.eventPoster = eventPoster
    self.maxAttempts = maxAttempts
    self.settleDelayMs = settleDelayMs
    self.hardTimeoutSeconds = hardTimeoutSeconds
    self.margin = margin
  }

  /// Scroll an element into view if it's off-screen
  /// - Parameter element: The element to scroll into view
  /// - Returns: ScrollIntoViewResult with success status and details
  /// - Throws: ScrollIntoViewError if scrolling fails
  public func scrollIntoView(_ element: Element) async throws -> ScrollIntoViewResult {
    let initialPosition = element.position

    if traceEnabled {
      print("[SCROLL] Target: \(element.label) (\(element.role))")
      print(
        "[SCROLL] Initial position: (\(Int(element.position.x)), \(Int(element.position.y))), size: (\(Int(element.size.width)), \(Int(element.size.height)))"
      )
    }

    // Check if element is already visible
    if isElementVisible(element) {
      if traceEnabled {
        print("[SCROLL] Element already visible, no scroll needed")
      }
      return ScrollIntoViewResult(
        success: true,
        attempts: 0,
        finalPosition: element.position,
        scrolledBy: .zero,
        method: "none"
      )
    }

    if traceEnabled {
      print("[SCROLL] Element is OFF-SCREEN")
    }

    // Strategy A: Try AXScrollToVisible action first
    if traceEnabled {
      print("[SCROLL] Attempt 1: Trying AXScrollToVisible action")
    }

    if try await tryAXScrollToVisible(element) {
      // Wait for scroll to complete
      try await Task.sleep(for: .milliseconds(settleDelayMs))

      // Re-query element to get new position
      if let updated = requeryElement(element),
        isElementVisible(updated)
      {
        let scrolledBy = CGPoint(
          x: updated.position.x - initialPosition.x,
          y: updated.position.y - initialPosition.y
        )

        if traceEnabled {
          print("[SCROLL] ✓ AXScrollToVisible succeeded")
          print("[SCROLL] → New position: (\(Int(updated.position.x)), \(Int(updated.position.y)))")
        }

        return ScrollIntoViewResult(
          success: true,
          attempts: 1,
          finalPosition: updated.position,
          scrolledBy: scrolledBy,
          method: "AXScrollToVisible"
        )
      }
    }

    if traceEnabled {
      print("[SCROLL] AXScrollToVisible failed or not supported, trying synthetic scroll")
    }

    // Strategy B: Synthetic scroll events with iteration
    return try await syntheticScrollIntoView(element, initialPosition: initialPosition)
  }

  // MARK: - Private Methods

  /// Check if element is visible (has non-zero size and is in viewport)
  private func isElementVisible(_ element: Element) -> Bool {
    // Zero-size elements are never visible
    guard element.size.height > 0, element.size.width > 0 else {
      return false
    }

    // Use visibility info if available
    if let visibility = element.visibility {
      return visibility.inViewport && visibility.percentVisible >= 0.99
    }

    // Fallback: check if element is likely visible based on size
    return true
  }

  /// Try the native AXScrollToVisible action
  private func tryAXScrollToVisible(_ element: Element) async throws -> Bool {
    var actionsRef: CFArray?
    let result = AXUIElementCopyActionNames(element.axElement, &actionsRef)

    guard result == .success,
      let actions = actionsRef as? [String],
      actions.contains("AXScrollToVisible")
    else {
      return false
    }

    let actionResult = AXUIElementPerformAction(
      element.axElement,
      "AXScrollToVisible" as CFString
    )

    return actionResult == .success
  }

  /// Perform iterative synthetic scroll to bring element into view
  private func syntheticScrollIntoView(
    _ element: Element,
    initialPosition: CGPoint
  ) async throws -> ScrollIntoViewResult {
    // Find scroll container
    guard let (scrollContainer, scrollRole) = findScrollContainer(for: element.axElement) else {
      throw ScrollIntoViewError.noScrollContainer
    }

    // Get scroll container frame
    let containerFrame = axFrame(of: scrollContainer)

    // Special handling for Chrome/WebKit: if container is AXWebArea, use its parent
    var targetContainer = scrollContainer
    if scrollRole == "AXWebArea" {
      if let parent: AXUIElement = getAXAttribute(scrollContainer, kAXParentAttribute as String),
        let parentRole: String = getAXAttribute(parent, kAXRoleAttribute as String),
        parentRole == "AXScrollArea"
      {
        targetContainer = parent
        if traceEnabled {
          print(
            "[SCROLL] Chrome/WebKit detected: targeting parent AXScrollArea instead of AXWebArea")
        }
      }
    }

    // Get the target container's frame for scroll positioning
    let targetFrame = axFrame(of: targetContainer)

    // Calculate scroll target point (center of target container)
    let scrollTargetPoint = CGPoint(
      x: targetFrame.midX,
      y: targetFrame.midY
    )

    if traceEnabled {
      print("[SCROLL] Container: \(scrollRole)")
      print(
        "[SCROLL] Container frame: (\(Int(containerFrame.origin.x)), \(Int(containerFrame.origin.y))) [\(Int(containerFrame.width))×\(Int(containerFrame.height))]"
      )
      print(
        "[SCROLL] Scroll target point: (\(Int(scrollTargetPoint.x)), \(Int(scrollTargetPoint.y)))")
    }

    let deadline = Date().addingTimeInterval(hardTimeoutSeconds)
    var currentElement = element

    for attempt in 1...maxAttempts {
      if Date() > deadline {
        throw ScrollIntoViewError.hardTimeout
      }

      // Check if visible
      if isElementVisible(currentElement) {
        let scrolledBy = CGPoint(
          x: currentElement.position.x - initialPosition.x,
          y: currentElement.position.y - initialPosition.y
        )

        if traceEnabled {
          print("[SCROLL] ✓ Scrolled into view in \(attempt) attempts")
        }

        return ScrollIntoViewResult(
          success: true,
          attempts: attempt,
          finalPosition: currentElement.position,
          scrolledBy: scrolledBy,
          method: "synthetic"
        )
      }

      // Calculate scroll delta
      let elementFrame = currentElement.frame
      let delta = calculateScrollDelta(
        elementFrame: elementFrame,
        viewportFrame: containerFrame
      )

      // No meaningful scroll possible
      if abs(delta.y) < 5 && abs(delta.x) < 5 {
        break
      }

      if traceEnabled {
        print(
          "[SCROLL] Attempt \(attempt): Synthetic scroll deltaY=\(Int(delta.y)) deltaX=\(Int(delta.x)) at (\(Int(scrollTargetPoint.x)), \(Int(scrollTargetPoint.y)))"
        )
      }

      // Post scroll event at container center
      try eventPoster.postScroll(
        deltaY: Int32(delta.y),
        deltaX: Int32(delta.x)
      )

      // Settle delay
      try await Task.sleep(for: .milliseconds(settleDelayMs))

      // Re-query element position
      if let updated = requeryElement(currentElement) {
        if traceEnabled {
          print(
            "[SCROLL] → New position: (\(Int(updated.position.x)), \(Int(updated.position.y))), size: (\(Int(updated.size.width)), \(Int(updated.size.height)))"
          )
        }
        currentElement = updated
      } else {
        // Element disappeared from AX tree
        throw ScrollIntoViewError.noProgress
      }
    }

    // Max attempts reached
    let progress = CGPoint(
      x: currentElement.position.x - initialPosition.x,
      y: currentElement.position.y - initialPosition.y
    )

    throw ScrollIntoViewError.maxAttemptsExceeded(
      attempts: maxAttempts,
      progress: progress
    )
  }

  /// Calculate scroll delta to bring element into viewport
  private func calculateScrollDelta(
    elementFrame: CGRect,
    viewportFrame: CGRect
  ) -> CGPoint {
    var deltaY: CGFloat = 0
    var deltaX: CGFloat = 0

    // Vertical scroll
    if elementFrame.maxY > viewportFrame.maxY {
      // Element is below viewport — scroll down (negative delta)
      deltaY = -(elementFrame.maxY - viewportFrame.maxY + margin)
    } else if elementFrame.minY < viewportFrame.minY {
      // Element is above viewport — scroll up (positive delta)
      deltaY = viewportFrame.minY - elementFrame.minY + margin
    }

    // Horizontal scroll
    if elementFrame.maxX > viewportFrame.maxX {
      // Element is right of viewport — scroll right (negative delta)
      deltaX = -(elementFrame.maxX - viewportFrame.maxX + margin)
    } else if elementFrame.minX < viewportFrame.minX {
      // Element is left of viewport — scroll left (positive delta)
      deltaX = viewportFrame.minX - elementFrame.minX + margin
    }

    // Cap large deltas to viewport size to avoid overshooting
    let maxDeltaY = viewportFrame.height - 100
    let maxDeltaX = viewportFrame.width - 100

    if abs(deltaY) > maxDeltaY {
      deltaY = deltaY > 0 ? maxDeltaY : -maxDeltaY
    }

    if abs(deltaX) > maxDeltaX {
      deltaX = deltaX > 0 ? maxDeltaX : -maxDeltaX
    }

    return CGPoint(x: deltaX, y: deltaY)
  }

  /// Re-query element to get updated position after scroll
  private func requeryElement(_ element: Element) -> Element? {
    // Build a query that should match exactly this element
    let query = ElementQuery(
      text: element.title ?? element.value,
      role: element.role,
      application: nil,  // Keep same app
      fuzzyMatch: false,
      limit: 1,
      identifier: element.identifier,
      siblingIndex: element.siblingIndex,
      parentRole: element.parentRole,
      minWidth: element.size.width > 0 ? element.size.width - 5 : nil,
      maxWidth: element.size.width > 0 ? element.size.width + 5 : nil,
      minHeight: nil,
      maxHeight: nil
    )

    let result = AccessibilityQuery.find(query)
    return result.elements.first
  }

  /// Find scroll container for an element
  private func findScrollContainer(for element: AXUIElement) -> (AXUIElement, String)? {
    var current = element
    var steps = 0
    let maxSteps = 50

    while steps < maxSteps {
      guard let parent: AXUIElement = getAXAttribute(current, kAXParentAttribute as String) else {
        return nil
      }

      if let role: String = getAXAttribute(parent, kAXRoleAttribute as String) {
        if scrollableRoles.contains(role) {
          return (parent, role)
        }
        if role == "AXApplication" {
          return nil
        }
      }

      current = parent
      steps += 1
    }

    return nil
  }

  /// Get frame of an AXUIElement
  private func axFrame(of element: AXUIElement) -> CGRect {
    let position = getAXPoint(element) ?? .zero
    let size = getAXSize(element) ?? .zero
    return CGRect(origin: position, size: size)
  }

  // MARK: - AX Helpers

  /// Extract a typed attribute from an AXUIElement
  private func getAXAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else { return nil }
    return value as? T
  }

  /// Extract CGPoint from an AXValue attribute
  private func getAXPoint(
    _ element: AXUIElement, _ attribute: String = kAXPositionAttribute as String
  ) -> CGPoint? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let axVal = value else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(axVal as! AXValue, .cgPoint, &point) else { return nil }
    return point
  }

  /// Extract CGSize from an AXValue attribute
  private func getAXSize(_ element: AXUIElement, _ attribute: String = kAXSizeAttribute as String)
    -> CGSize?
  {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let axVal = value else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(axVal as! AXValue, .cgSize, &size) else { return nil }
    return size
  }
}

// MARK: - Constants

private let scrollableRoles: Set<String> = [
  "AXScrollArea",
  "AXWebArea",
  "AXTable",
  "AXList",
]
