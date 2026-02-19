import CoreGraphics
import Foundation

/// Errors that can occur during silk operations
public enum SilkError: LocalizedError {
  case eventCreationFailed
  case permissionDenied(String)
  case invalidCoordinates(x: CGFloat, y: CGFloat)
  case invalidKeyCode(CGKeyCode)
  case systemAPIError(String)

  public var errorDescription: String? {
    switch self {
    case .eventCreationFailed:
      return "Failed to create CGEvent"
    case .permissionDenied(let permission):
      return
        "Permission denied: \(permission). Grant access in System Settings > Privacy & Security."
    case .invalidCoordinates(let x, let y):
      return "Invalid coordinates: (\(x), \(y))"
    case .invalidKeyCode(let code):
      return "Invalid key code: \(code)"
    case .systemAPIError(let message):
      return "System API error: \(message)"
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .permissionDenied:
      return
        "Open System Settings > Privacy & Security > Accessibility and grant permission to this application."
    case .eventCreationFailed:
      return "Ensure your application has Accessibility permissions."
    default:
      return nil
    }
  }
}
