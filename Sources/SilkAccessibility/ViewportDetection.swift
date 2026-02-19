// ViewportDetection.swift - Compute element visibility relative to scroll containers
// Phase 3, Layer 1: Enhanced Primitives
//
// Given an Element (with its AXUIElement handle), walks up the parent chain
// to find scroll containers and determines if the element is visible in the viewport.

import AppKit
import ApplicationServices
import CoreGraphics

/// Compute visibility information for an element.
///
/// Algorithm:
/// 1. Check element has non-zero size
/// 2. Walk up parent chain to find nearest AXScrollArea/AXWebArea
/// 3. Compare element frame to scroll container's visible frame
/// 4. If no scroll container, compare to window frame
/// 5. Calculate scroll delta needed (if any)
public func computeVisibility(for element: Element) -> (ElementVisibility, ScrollContainerInfo?) {
  let elementFrame = element.frame

  // Zero-size elements are never visible
  guard elementFrame.width > 0, elementFrame.height > 0 else {
    return (
      ElementVisibility(
        inViewport: false,
        percentVisible: 0,
        reason: .zeroSize,
        requiresScroll: nil
      ),
      nil
    )
  }

  // Walk up parent chain to find scroll container
  if let (scrollAX, scrollRole) = findScrollContainer(for: element.axElement) {
    let containerFrame = axFrame(of: scrollAX)

    guard containerFrame.width > 0, containerFrame.height > 0 else {
      // Scroll container has no size — fall through to window check
      return computeWindowVisibility(elementFrame: elementFrame, element: element)
    }

    let containerInfo = buildScrollContainerInfo(
      scrollAX: scrollAX,
      role: scrollRole,
      frame: containerFrame
    )

    let visibility = computeFrameVisibility(
      elementFrame: elementFrame,
      viewportFrame: containerFrame
    )

    return (visibility, containerInfo)
  }

  // No scroll container found — check against window frame
  return computeWindowVisibility(elementFrame: elementFrame, element: element)
}

/// Batch-compute visibility for an array of elements.
/// Used by AccessibilityQuery.find() to enrich results.
///
/// Optimization: builds a cache of scroll container lookups keyed by element pointer
/// identity, so that elements sharing the same scroll ancestor don't repeat the
/// O(depth) parent walk. This reduces batch cost from O(n × depth) to closer to O(n + unique_containers × depth).
public func computeVisibilityBatch(for elements: [Element]) -> [(
  ElementVisibility, ScrollContainerInfo?
)] {
  // Cache: map from AXUIElement pointer identity to resolved scroll container (or nil)
  // We use Unmanaged pointer as cache key since we want identity-based caching for
  // the *wrapper* instances we've already resolved — this is distinct from CFHash-based
  // cycle detection (see AccessibilityTree).
  var scrollContainerCache: [UnsafeMutableRawPointer: (AXUIElement, String)?] = [:]
  var frameCache: [UnsafeMutableRawPointer: CGRect] = [:]
  var infoCache: [UnsafeMutableRawPointer: ScrollContainerInfo] = [:]

  return elements.map { element in
    let elementFrame = element.frame

    guard elementFrame.width > 0, elementFrame.height > 0 else {
      return (
        ElementVisibility(
          inViewport: false,
          percentVisible: 0,
          reason: .zeroSize,
          requiresScroll: nil
        ),
        nil
      )
    }

    // Find scroll container with caching
    if let (scrollAX, scrollRole) = findScrollContainerCached(
      for: element.axElement, cache: &scrollContainerCache)
    {
      let ptr = Unmanaged.passUnretained(scrollAX).toOpaque()

      let containerFrame: CGRect
      if let cached = frameCache[ptr] {
        containerFrame = cached
      } else {
        containerFrame = axFrame(of: scrollAX)
        frameCache[ptr] = containerFrame
      }

      guard containerFrame.width > 0, containerFrame.height > 0 else {
        return computeWindowVisibility(elementFrame: elementFrame, element: element)
      }

      let containerInfo: ScrollContainerInfo
      if let cached = infoCache[ptr] {
        containerInfo = cached
      } else {
        containerInfo = buildScrollContainerInfo(
          scrollAX: scrollAX, role: scrollRole, frame: containerFrame)
        infoCache[ptr] = containerInfo
      }

      let visibility = computeFrameVisibility(
        elementFrame: elementFrame, viewportFrame: containerFrame)
      return (visibility, containerInfo)
    }

    return computeWindowVisibility(elementFrame: elementFrame, element: element)
  }
}

/// Cached version of findScrollContainer that memoizes results for parent elements
/// encountered during the walk, so sibling elements don't repeat the same traversal.
private func findScrollContainerCached(
  for element: AXUIElement,
  cache: inout [UnsafeMutableRawPointer: (AXUIElement, String)?]
) -> (AXUIElement, String)? {
  let ptr = Unmanaged.passUnretained(element).toOpaque()
  if let cached = cache[ptr] {
    return cached
  }

  var current = element
  var visited: [UnsafeMutableRawPointer] = [ptr]
  var steps = 0
  let maxSteps = 50

  while steps < maxSteps {
    guard let parent: AXUIElement = axAttribute(current, kAXParentAttribute as String) else {
      // No scroll container found — cache nil for all visited
      for v in visited { cache[v] = .some(nil) }
      return nil
    }

    let parentPtr = Unmanaged.passUnretained(parent).toOpaque()

    // Check if we already know the answer for this parent
    if let cached = cache[parentPtr] {
      // Propagate to all visited nodes
      for v in visited { cache[v] = cached }
      return cached
    }

    if let role: String = axAttribute(parent, kAXRoleAttribute as String) {
      if scrollableRoles.contains(role) {
        let result: (AXUIElement, String)? = (parent, role)
        for v in visited { cache[v] = result }
        return result
      }
      if role == "AXApplication" {
        for v in visited { cache[v] = .some(nil) }
        return nil
      }
    }

    visited.append(parentPtr)
    current = parent
    steps += 1
  }

  for v in visited { cache[v] = .some(nil) }
  return nil
}

// MARK: - Scroll Container Discovery

/// Scrollable role names to look for when walking the parent chain.
private let scrollableRoles: Set<String> = [
  "AXScrollArea",
  "AXWebArea",
]

/// Walk up the parent chain to find the nearest scrollable ancestor.
/// Returns the AXUIElement and its role, or nil if no scroll container found.
private func findScrollContainer(for element: AXUIElement) -> (AXUIElement, String)? {
  var current = element
  // Safety limit to prevent infinite loops (shouldn't happen with visited tracking,
  // but parent chain walking is separate from tree traversal)
  var steps = 0
  let maxSteps = 50

  while steps < maxSteps {
    guard let parent: AXUIElement = axAttribute(current, kAXParentAttribute as String) else {
      return nil
    }

    if let role: String = axAttribute(parent, kAXRoleAttribute as String) {
      if scrollableRoles.contains(role) {
        return (parent, role)
      }
      // Stop at application level — no point going higher
      if role == "AXApplication" {
        return nil
      }
    }

    current = parent
    steps += 1
  }

  return nil
}

// MARK: - Frame Visibility Computation

/// Compute visibility by comparing element frame to a viewport frame.
/// Pure geometry — no AX API calls.
private func computeFrameVisibility(
  elementFrame: CGRect,
  viewportFrame: CGRect
) -> ElementVisibility {
  let intersection = elementFrame.intersection(viewportFrame)

  if intersection.isNull || intersection.width <= 0 || intersection.height <= 0 {
    // Completely off-screen — determine direction
    let reason = determineOffscreenReason(elementFrame: elementFrame, viewportFrame: viewportFrame)
    let delta = calculateScrollDelta(elementFrame: elementFrame, viewportFrame: viewportFrame)
    return ElementVisibility(
      inViewport: false,
      percentVisible: 0,
      reason: reason,
      requiresScroll: delta
    )
  }

  let elementArea = elementFrame.width * elementFrame.height
  let visibleArea = intersection.width * intersection.height
  let percentVisible = elementArea > 0 ? Double(visibleArea / elementArea) : 0

  if percentVisible >= 0.99 {
    // Fully visible (with small tolerance for floating point)
    return ElementVisibility(
      inViewport: true,
      percentVisible: 1.0,
      reason: .fullyVisible,
      requiresScroll: nil
    )
  } else {
    // Partially visible
    let delta = calculateScrollDelta(elementFrame: elementFrame, viewportFrame: viewportFrame)
    return ElementVisibility(
      inViewport: false,
      percentVisible: percentVisible,
      reason: .partiallyVisible,
      requiresScroll: delta
    )
  }
}

/// Determine why an element is off-screen.
private func determineOffscreenReason(
  elementFrame: CGRect,
  viewportFrame: CGRect
) -> VisibilityReason {
  let elementMidY = elementFrame.midY
  let elementMidX = elementFrame.midX

  // Check vertical first (most common for scroll)
  if elementMidY > viewportFrame.maxY {
    return .belowViewport
  }
  if elementMidY < viewportFrame.minY {
    return .aboveViewport
  }
  if elementMidX > viewportFrame.maxX {
    return .rightOfViewport
  }
  if elementMidX < viewportFrame.minX {
    return .leftOfViewport
  }

  return .unknown
}

/// Calculate the scroll delta needed to bring an element into the center of the viewport.
private func calculateScrollDelta(
  elementFrame: CGRect,
  viewportFrame: CGRect
) -> ScrollDelta {
  let elementMidY = elementFrame.midY
  let elementMidX = elementFrame.midX
  let viewportMidY = viewportFrame.midY
  let viewportMidX = viewportFrame.midX

  let deltaY = elementMidY - viewportMidY
  let deltaX = elementMidX - viewportMidX

  // Choose primary direction based on largest delta
  if abs(deltaY) >= abs(deltaX) {
    let direction = deltaY > 0 ? "down" : "up"
    return ScrollDelta(direction: direction, estimatedPixels: Int(abs(deltaY)))
  } else {
    let direction = deltaX > 0 ? "right" : "left"
    return ScrollDelta(direction: direction, estimatedPixels: Int(abs(deltaX)))
  }
}

// MARK: - Window Visibility Fallback

/// When no scroll container is found, check against the window frame.
private func computeWindowVisibility(
  elementFrame: CGRect,
  element: Element
) -> (ElementVisibility, ScrollContainerInfo?) {
  // Try to find the window frame by walking up to AXWindow
  if let windowFrame = findWindowFrame(for: element.axElement) {
    let visibility = computeFrameVisibility(
      elementFrame: elementFrame,
      viewportFrame: windowFrame
    )
    // If the element is outside the window, adjust reason
    if !visibility.inViewport && visibility.reason == .unknown {
      return (
        ElementVisibility(
          inViewport: false,
          percentVisible: visibility.percentVisible,
          reason: .outsideWindow,
          requiresScroll: visibility.requiresScroll
        ),
        nil
      )
    }
    return (visibility, nil)
  }

  // Last resort: check against main screen bounds
  if let screenFrame = NSScreen.main?.frame {
    let visibility = computeFrameVisibility(
      elementFrame: elementFrame,
      viewportFrame: screenFrame
    )
    return (visibility, nil)
  }

  // Can't determine visibility
  return (
    ElementVisibility(
      inViewport: true,  // Assume visible if we can't determine
      percentVisible: 1.0,
      reason: .unknown,
      requiresScroll: nil
    ),
    nil
  )
}

/// Walk up to find the containing window frame.
private func findWindowFrame(for element: AXUIElement) -> CGRect? {
  var current = element
  var steps = 0
  let maxSteps = 50

  while steps < maxSteps {
    if let role: String = axAttribute(current, kAXRoleAttribute as String),
      role == "AXWindow"
    {
      return axFrame(of: current)
    }

    guard let parent: AXUIElement = axAttribute(current, kAXParentAttribute as String) else {
      return nil
    }
    current = parent
    steps += 1
  }

  return nil
}

// MARK: - Scroll Container Info Builder

/// Build ScrollContainerInfo from an AXScrollArea element.
private func buildScrollContainerInfo(
  scrollAX: AXUIElement,
  role: String,
  frame: CGRect
) -> ScrollContainerInfo {
  // Try to get content size from scroll bars or children
  let contentSize = inferContentSize(from: scrollAX)
  let scrollPosition = inferScrollPosition(from: scrollAX)
  let (canUp, canDown, canLeft, canRight) = inferScrollDirections(
    from: scrollAX,
    containerFrame: frame,
    contentSize: contentSize,
    scrollPosition: scrollPosition
  )

  return ScrollContainerInfo(
    role: role,
    visibleFrame: frame,
    contentSize: contentSize,
    scrollPosition: scrollPosition,
    canScrollUp: canUp,
    canScrollDown: canDown,
    canScrollLeft: canLeft,
    canScrollRight: canRight
  )
}

/// Try to determine total content size from scroll bar properties.
private func inferContentSize(from scrollAX: AXUIElement) -> CGSize? {
  // Some elements expose AXSize directly for content
  // Try children for scroll bars
  guard let children: [AXUIElement] = axAttribute(scrollAX, kAXChildrenAttribute as String) else {
    return nil
  }

  var hasVerticalBar = false
  var hasHorizontalBar = false

  for child in children {
    if let role: String = axAttribute(child, kAXRoleAttribute as String) {
      if role == "AXScrollBar" {
        if let orientation: String = axAttribute(child, kAXOrientationAttribute as String) {
          if orientation == "AXVerticalOrientation" {
            hasVerticalBar = true
          } else if orientation == "AXHorizontalOrientation" {
            hasHorizontalBar = true
          }
        }
      }
    }
  }

  // If scroll bars exist, content is larger than viewport
  // We can't easily get exact content size from AX API alone,
  // but we know scrolling is possible
  if hasVerticalBar || hasHorizontalBar {
    // Return nil for now — exact content size requires more work
    // The canScroll* booleans are more useful for agents
    return nil
  }

  return nil
}

/// Try to get current scroll position.
private func inferScrollPosition(from scrollAX: AXUIElement) -> CGPoint? {
  // Some scroll areas expose position through scroll bar values
  guard let children: [AXUIElement] = axAttribute(scrollAX, kAXChildrenAttribute as String) else {
    return nil
  }

  var verticalValue: CGFloat?
  var horizontalValue: CGFloat?

  for child in children {
    guard let role: String = axAttribute(child, kAXRoleAttribute as String),
      role == "AXScrollBar"
    else { continue }

    if let orientation: String = axAttribute(child, kAXOrientationAttribute as String) {
      // Scroll bar value is a Float between 0.0 and 1.0
      if let value: AnyObject = axAttribute(child, kAXValueAttribute as String) {
        let floatValue = (value as? NSNumber)?.doubleValue
        if orientation == "AXVerticalOrientation" {
          verticalValue = floatValue.map { CGFloat($0) }
        } else if orientation == "AXHorizontalOrientation" {
          horizontalValue = floatValue.map { CGFloat($0) }
        }
      }
    }
  }

  if verticalValue != nil || horizontalValue != nil {
    return CGPoint(x: horizontalValue ?? 0, y: verticalValue ?? 0)
  }

  return nil
}

/// Determine which directions can be scrolled.
private func inferScrollDirections(
  from scrollAX: AXUIElement,
  containerFrame: CGRect,
  contentSize: CGSize?,
  scrollPosition: CGPoint?
) -> (Bool, Bool, Bool, Bool) {
  guard let children: [AXUIElement] = axAttribute(scrollAX, kAXChildrenAttribute as String) else {
    return (false, false, false, false)
  }

  var canUp = false
  var canDown = false
  var canLeft = false
  var canRight = false

  for child in children {
    guard let role: String = axAttribute(child, kAXRoleAttribute as String),
      role == "AXScrollBar"
    else { continue }

    guard let orientation: String = axAttribute(child, kAXOrientationAttribute as String) else {
      continue
    }

    // Get scroll bar value (0.0 to 1.0)
    let value: CGFloat
    if let v: AnyObject = axAttribute(child, kAXValueAttribute as String),
      let num = (v as? NSNumber)?.doubleValue
    {
      value = CGFloat(num)
    } else {
      // Scroll bar exists but no value — assume both directions possible
      if orientation == "AXVerticalOrientation" {
        canUp = true
        canDown = true
      } else {
        canLeft = true
        canRight = true
      }
      continue
    }

    if orientation == "AXVerticalOrientation" {
      canUp = value > 0.01  // Not at top
      canDown = value < 0.99  // Not at bottom
    } else if orientation == "AXHorizontalOrientation" {
      canLeft = value > 0.01
      canRight = value < 0.99
    }
  }

  return (canUp, canDown, canLeft, canRight)
}

// MARK: - AX Frame Helper

/// Get the frame (position + size) of an AXUIElement.
private func axFrame(of element: AXUIElement) -> CGRect {
  let position = axPoint(element) ?? .zero
  let size = axSize(element) ?? .zero
  return CGRect(origin: position, size: size)
}
