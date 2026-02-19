import CoreGraphics
import Foundation

/// Screen Recording permission management for ScreenCaptureKit.
public enum ScreenRecordingPermission {

  /// Non-blocking check. Returns `true` if Screen Recording is already granted.
  public static var isGranted: Bool {
    CGPreflightScreenCaptureAccess()
  }

  /// Opens System Settings → Privacy → Screen Recording if not yet granted.
  /// Returns `true` only if permission was **already** granted (macOS requires
  /// an app restart after the user toggles the switch).
  @discardableResult
  public static func requestIfNeeded() -> Bool {
    if isGranted { return true }
    CGRequestScreenCaptureAccess()
    return false
  }

  /// Throws ``CaptureError/screenRecordingDenied`` when permission is missing.
  public static func ensureGranted() throws {
    guard isGranted else {
      CGRequestScreenCaptureAccess()
      throw CaptureError.screenRecordingDenied
    }
  }
}
