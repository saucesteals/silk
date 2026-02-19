import CoreGraphics
import Foundation

/// Protocol for posting input events
/// Abstraction layer for testability (mock event poster in tests)
public protocol EventPoster: Sendable {
  /// Post a mouse move event to specified coordinates
  func postMouseMove(to point: CGPoint) throws

  /// Post a mouse button event (press or release)
  func postMouseButton(_ button: MouseButton, down: Bool, at point: CGPoint) throws

  /// Post a keyboard event (key press or release)
  func postKeyPress(keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) throws

  /// Post a scroll event
  func postScroll(deltaY: Int32, deltaX: Int32) throws

  /// Post a mouse drag event (mouse move while button is held down)
  func postMouseDrag(_ button: MouseButton, to point: CGPoint) throws
}

/// Default implementation using CGEvent
/// Thread-safe: CGEventSource is a CFType with thread-safe reference counting,
/// and tapLocation is an immutable constant.
public final class CGEventPoster: EventPoster, @unchecked Sendable {

  /// Event tap location - kCGHIDEventTap for trusted events
  private let tapLocation: CGEventTapLocation = .cghidEventTap

  /// Event source (nil = default system source)
  private let eventSource: CGEventSource?

  public init(eventSource: CGEventSource? = nil) {
    self.eventSource = eventSource
  }

  public func postMouseMove(to point: CGPoint) throws {
    // Use CGDisplayMoveCursorToPoint for visual cursor movement
    // This actually moves the cursor on screen (unlike CGEvent posting which only updates logical position)
    let displayID = CGMainDisplayID()
    let result = CGDisplayMoveCursorToPoint(displayID, point)

    guard result == .success else {
      throw SilkError.eventCreationFailed
    }
  }

  public func postMouseButton(
    _ button: MouseButton,
    down: Bool,
    at point: CGPoint
  ) throws {
    let eventType = down ? button.downEventType : button.upEventType

    guard
      let event = CGEvent(
        mouseEventSource: eventSource,
        mouseType: eventType,
        mouseCursorPosition: point,
        mouseButton: button.cgButton
      )
    else {
      throw SilkError.eventCreationFailed
    }

    setTimestamp(event)
    event.post(tap: tapLocation)
  }

  public func postKeyPress(
    keyCode: CGKeyCode,
    down: Bool,
    flags: CGEventFlags = []
  ) throws {
    guard
      let event = CGEvent(
        keyboardEventSource: eventSource,
        virtualKey: keyCode,
        keyDown: down
      )
    else {
      throw SilkError.eventCreationFailed
    }

    if !flags.isEmpty {
      event.flags = flags
    }

    setTimestamp(event)
    event.post(tap: tapLocation)
  }

  public func postScroll(deltaY: Int32, deltaX: Int32 = 0) throws {
    guard
      let event = CGEvent(
        scrollWheelEvent2Source: eventSource,
        units: .pixel,
        wheelCount: 2,
        wheel1: deltaY,
        wheel2: deltaX,
        wheel3: 0
      )
    else {
      throw SilkError.eventCreationFailed
    }

    setTimestamp(event)
    event.post(tap: tapLocation)
  }

  public func postMouseDrag(_ button: MouseButton, to point: CGPoint) throws {
    guard
      let event = CGEvent(
        mouseEventSource: eventSource,
        mouseType: button.dragEventType,
        mouseCursorPosition: point,
        mouseButton: button.cgButton
      )
    else {
      throw SilkError.eventCreationFailed
    }

    setTimestamp(event)
    event.post(tap: tapLocation)
  }

  /// Cached timebase info (queried once, never changes at runtime)
  private static let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  /// Set proper timestamp for macOS Sequoia compatibility
  /// Uses mach_absolute_time() to get system uptime
  private func setTimestamp(_ event: CGEvent) {
    // Get current absolute time in ticks
    let uptimeTicks = mach_absolute_time()

    // Convert to nanoseconds using timebase (overflow-safe)
    // Using the classic pattern to avoid overflow on Intel Macs with >53 days uptime
    let timebase = Self.timebase
    let high = uptimeTicks / UInt64(timebase.denom)
    let low = uptimeTicks % UInt64(timebase.denom)
    let uptimeNanos =
      high * UInt64(timebase.numer) + low * UInt64(timebase.numer) / UInt64(timebase.denom)

    // Convert to CGEventTimestamp (nanoseconds since system boot)
    event.timestamp = CGEventTimestamp(uptimeNanos)
  }
}
