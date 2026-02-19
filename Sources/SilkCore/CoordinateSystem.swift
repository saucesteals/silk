import AppKit

/// Utility for converting between macOS coordinate systems.
///
/// macOS uses two coordinate systems:
///
/// - **AppKit (NSPoint):** Origin at the **bottom-left** of the primary screen.
///   Y increases upward. Used by NSWindow, NSView, NSEvent, and NSScreen.
///
/// - **Core Graphics (CGPoint):** Origin at the **top-left** of the primary screen.
///   Y increases downward. Used by CGEvent, CGDisplay, and Accessibility APIs.
///
/// The conversion flips the Y axis using the primary screen height:
///   `cgY = screenHeight - appKitY` (and vice versa).
///
/// - Note: All conversions use `NSScreen.main?.frame.height`. If no screen is
///   available (e.g., headless environment), the point is returned unchanged.
public enum CoordinateSystem {

  /// Converts an AppKit point (bottom-left origin) to a Core Graphics point (top-left origin).
  ///
  /// - Parameter point: A point in AppKit coordinates.
  /// - Returns: The equivalent point in Core Graphics coordinates.
  public static func appKitToCG(_ point: NSPoint) -> CGPoint {
    guard let screenHeight = NSScreen.main?.frame.height else {
      return CGPoint(x: point.x, y: point.y)
    }
    return CGPoint(x: point.x, y: screenHeight - point.y)
  }

  /// Converts a Core Graphics point (top-left origin) to an AppKit point (bottom-left origin).
  ///
  /// - Parameter point: A point in Core Graphics coordinates.
  /// - Returns: The equivalent point in AppKit coordinates.
  public static func cgToAppKit(_ point: CGPoint) -> NSPoint {
    guard let screenHeight = NSScreen.main?.frame.height else {
      return NSPoint(x: point.x, y: point.y)
    }
    return NSPoint(x: point.x, y: screenHeight - point.y)
  }
}
