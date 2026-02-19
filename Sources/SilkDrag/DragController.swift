import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import SilkCore
import SilkHumanization

/// Performs drag operations using CGEvent mouse down/move/up sequences
public final class DragController: Sendable {

  private let eventPoster: EventPoster

  public init(eventPoster: EventPoster = CGEventPoster()) {
    self.eventPoster = eventPoster
  }

  /// Perform drag operation from one point to another
  /// - Parameters:
  ///   - options: Drag configuration (from, to, button, humanize, duration)
  /// - Returns: Result with timing and distance info
  /// - Throws: SilkError if drag fails or permissions missing
  public func drag(_ options: DragOptions) async throws -> DragResult {
    let start = DispatchTime.now()
    let distance = hypot(options.to.x - options.from.x, options.to.y - options.from.y)

    // 1. Move cursor to start point
    try eventPoster.postMouseMove(to: options.from)
    try await Task.sleep(for: .milliseconds(10))

    // 2. Mouse down at start
    try eventPoster.postMouseButton(options.button, down: true, at: options.from)
    try await Task.sleep(for: .milliseconds(50))  // Brief hold before dragging

    // 3. Move along path
    if options.humanize {
      try await performHumanizedDrag(options: options)
    } else if let duration = options.duration, duration > 0 {
      try await performTimedDrag(options: options, duration: duration)
    } else {
      // Instant: post a single drag event to the destination
      try eventPoster.postMouseDrag(options.button, to: options.to)
      try await Task.sleep(for: .milliseconds(10))
    }

    // 4. Mouse up at end point
    try eventPoster.postMouseButton(options.button, down: false, at: options.to)

    let elapsed =
      Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000.0

    return DragResult(
      fromX: options.from.x,
      fromY: options.from.y,
      toX: options.to.x,
      toY: options.to.y,
      distance: distance,
      durationMs: Int(elapsed * 1000),
      humanized: options.humanize
    )
  }

  /// Perform drag by element names (uses accessibility API)
  /// - Parameters:
  ///   - fromElement: Source element text/role
  ///   - toElement: Destination element text/role
  ///   - app: Optional app name filter
  ///   - humanize: Use human-like movement
  /// - Returns: Result with timing and distance info
  /// - Throws: SilkError if elements not found or drag fails
  public func dragElements(
    from fromElement: String,
    to toElement: String,
    app: String? = nil,
    humanize: Bool = false
  ) async throws -> DragResult {
    // Use accessibility API to find elements
    // Import is handled at link time since SilkDrag depends on SilkCore
    // We use AXUIElement APIs directly here to avoid circular dependency with SilkAccessibility

    guard let fromPoint = findElementCenter(named: fromElement, app: app) else {
      throw SilkError.systemAPIError("Could not find source element: \(fromElement)")
    }

    guard let toPoint = findElementCenter(named: toElement, app: app) else {
      throw SilkError.systemAPIError("Could not find destination element: \(toElement)")
    }

    let options = DragOptions(
      from: fromPoint,
      to: toPoint,
      button: .left,
      humanize: humanize
    )

    return try await drag(options)
  }

  // MARK: - Private

  /// Humanized drag using Bezier curves from SilkHumanization
  private func performHumanizedDrag(options: DragOptions) async throws {
    let steps = HumanizedMovement.generateMovement(
      from: options.from,
      to: options.to,
      targetSize: 10.0
    )

    for step in steps {
      try eventPoster.postMouseDrag(options.button, to: step.point)
      try await Task.sleep(for: .milliseconds(Int(step.delay * 1000)))
    }
  }

  /// Timed drag with linear interpolation over specified duration
  private func performTimedDrag(options: DragOptions, duration: TimeInterval) async throws {
    let stepCount = max(20, Int(duration * 60))  // ~60 steps per second
    let startTime = DispatchTime.now()

    for i in 1...stepCount {
      let targetT = Double(i) / Double(stepCount)
      let x = options.from.x + (options.to.x - options.from.x) * targetT
      let y = options.from.y + (options.to.y - options.from.y) * targetT
      let point = CGPoint(x: x, y: y)

      try eventPoster.postMouseDrag(options.button, to: point)

      // Sleep until the correct wall-clock time for this step
      let targetTimeNs = startTime.uptimeNanoseconds + UInt64(duration * targetT * 1_000_000_000)
      let now = DispatchTime.now()
      let remaining = Double(Int64(targetTimeNs) - Int64(now.uptimeNanoseconds)) / 1_000_000_000.0
      if remaining > 0 {
        try await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
      }
    }
  }

  /// Find element center point using accessibility API
  /// Searches across running applications for a UI element matching the given name
  private func findElementCenter(named name: String, app: String?) -> CGPoint? {
    let apps: [NSRunningApplication]
    if let appName = app {
      apps = NSWorkspace.shared.runningApplications.filter {
        $0.localizedName?.lowercased() == appName.lowercased()
      }
    } else {
      apps = NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular
      }
    }

    let deadline = DispatchTime.now() + .seconds(5)  // 5 second timeout

    for runningApp in apps {
      if DispatchTime.now() > deadline { break }
      let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
      if let point = searchElement(
        named: name, in: appElement, depth: 0, maxDepth: 8, deadline: deadline)
      {
        return point
      }
    }

    return nil
  }

  /// Recursively search for element by title/description
  private func searchElement(
    named name: String, in element: AXUIElement, depth: Int, maxDepth: Int, deadline: DispatchTime
  ) -> CGPoint? {
    guard depth < maxDepth, DispatchTime.now() < deadline else { return nil }

    let nameLower = name.lowercased()

    // Check title
    if let title = axStringAttribute(element, kAXTitleAttribute as String),
      title.lowercased().contains(nameLower)
    {
      return elementCenter(element)
    }

    // Check description
    if let desc = axStringAttribute(element, kAXDescriptionAttribute as String),
      desc.lowercased().contains(nameLower)
    {
      return elementCenter(element)
    }

    // Check value
    if let value = axStringAttribute(element, kAXValueAttribute as String),
      value.lowercased().contains(nameLower)
    {
      return elementCenter(element)
    }

    // Recurse into children
    var childrenRef: AnyObject?
    let result = AXUIElementCopyAttributeValue(
      element, kAXChildrenAttribute as CFString, &childrenRef)
    guard result == .success, let children = childrenRef as? [AXUIElement] else { return nil }

    for child in children {
      if let point = searchElement(
        named: name, in: child, depth: depth + 1, maxDepth: maxDepth, deadline: deadline)
      {
        return point
      }
    }

    return nil
  }

  /// Get string attribute from AXUIElement
  private func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else { return nil }
    return value as? String
  }

  /// Get center point of an AXUIElement
  private func elementCenter(_ element: AXUIElement) -> CGPoint? {
    // Get position
    var posRef: AnyObject?
    guard
      AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
      let posValue = posRef
    else { return nil }
    var position = CGPoint.zero
    guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position) else { return nil }

    // Get size
    var sizeRef: AnyObject?
    guard
      AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
      let sizeValue = sizeRef
    else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

    return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
  }

}
