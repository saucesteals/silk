import ApplicationServices
import Foundation

/// Manages macOS permissions required for silk operations
public final class PermissionsManager: Sendable {

  /// Singleton instance
  public static let shared = PermissionsManager()

  private init() {}

  /// Check if Accessibility permission is granted
  /// - Returns: True if permission is granted
  public func hasAccessibilityPermission() -> Bool {
    let granted = AXIsProcessTrusted()
    SilkLogger.logPermissionCheck("Accessibility", granted: granted)
    return granted
  }

  /// Request Accessibility permission (shows system prompt)
  /// - Note: User must manually grant permission in System Settings
  /// - Returns: True if permission is already granted, false if prompt was shown
  @discardableResult
  public func requestAccessibilityPermission() -> Bool {
    SilkLogger.permission.info("Requesting Accessibility permission (showing prompt)")
    // Use string literal instead of C constant to avoid concurrency warnings
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// Verify permissions and throw if not granted
  /// - Throws: SilkError.permissionDenied if Accessibility permission is missing
  public func verifyPermissions() throws {
    guard hasAccessibilityPermission() else {
      throw SilkError.permissionDenied("Accessibility")
    }
  }

  /// Print permission status to console
  public func printPermissionStatus() {
    let hasAccessibility = hasAccessibilityPermission()

    print("silk Permission Status:")
    print("  Accessibility: \(hasAccessibility ? "✅ Granted" : "❌ Denied")")

    if !hasAccessibility {
      print("\n⚠️  Missing permissions detected!")
      print("   Grant permissions in:")
      print("   System Settings > Privacy & Security > Accessibility")
    }
  }
}
