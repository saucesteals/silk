import CoreGraphics

/// Mouse button types
public enum MouseButton: Sendable {
  case left
  case right
  case center

  /// Convert to CGMouseButton
  var cgButton: CGMouseButton {
    switch self {
    case .left: return .left
    case .right: return .right
    case .center: return .center
    }
  }

  /// Mouse event type for button down
  var downEventType: CGEventType {
    switch self {
    case .left: return .leftMouseDown
    case .right: return .rightMouseDown
    case .center: return .otherMouseDown
    }
  }

  /// Mouse event type for button up
  var upEventType: CGEventType {
    switch self {
    case .left: return .leftMouseUp
    case .right: return .rightMouseUp
    case .center: return .otherMouseUp
    }
  }

  /// Mouse event type for dragging (mouse move while button held)
  public var dragEventType: CGEventType {
    switch self {
    case .left: return .leftMouseDragged
    case .right: return .rightMouseDragged
    case .center: return .otherMouseDragged
    }
  }
}
