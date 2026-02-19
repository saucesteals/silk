import ApplicationServices
import Foundation
import os.log

/// Simple logging infrastructure for debugging silk operations.
/// Opt-in via SILK_DEBUG or SILK_VERBOSE environment variable.
///
/// Usage:
///   SilkLogger.ax.debug("Found element: \(elementRole)")
///   SilkLogger.coordinate.info("Converting: \(x), \(y)")
///   SilkLogger.permission.error("AX permission denied")
public enum SilkLogger {

  /// Logging categories for different subsystems
  public enum Category: Sendable {
    case accessibility  // AX API calls, element queries
    case coordinate  // Coordinate conversions, screen math
    case permission  // Permission checks
    case action  // Click, type, drag operations
    case general  // General operations

    var subsystem: String { "sh.sauce.silk" }

    var category: String {
      switch self {
      case .accessibility: return "accessibility"
      case .coordinate: return "coordinate"
      case .permission: return "permission"
      case .action: return "action"
      case .general: return "general"
      }
    }

    var osLog: OSLog {
      OSLog(subsystem: subsystem, category: category)
    }
  }

  // MARK: - Category Loggers

  /// Accessibility API logging (element queries, tree traversal)
  public static let ax = Logger(.accessibility)

  /// Coordinate conversion logging (screen ↔ CG, viewport calculations)
  public static let coordinate = Logger(.coordinate)

  /// Permission check logging (AX trust status, prompts)
  public static let permission = Logger(.permission)

  /// Action logging (clicks, types, drags, scrolls)
  public static let action = Logger(.action)

  /// General logging (everything else)
  public static let general = Logger(.general)

  // MARK: - Configuration

  /// Check if logging is enabled via environment variable
  /// Set SILK_DEBUG=1 or SILK_VERBOSE=1 to enable logging
  public static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["SILK_DEBUG"] == "1"
      || ProcessInfo.processInfo.environment["SILK_VERBOSE"] == "1"
  }

  // MARK: - Logger Implementation

  /// Thread-safe logger for a specific category
  public struct Logger: Sendable {
    private let category: Category

    init(_ category: Category) {
      self.category = category
    }

    /// Log debug-level message (only when debugging enabled)
    public func debug(_ message: String, file: String = #file, line: Int = #line) {
      log(.debug, message, file: file, line: line)
    }

    /// Log info-level message
    public func info(_ message: String, file: String = #file, line: Int = #line) {
      log(.info, message, file: file, line: line)
    }

    /// Log error-level message
    public func error(_ message: String, file: String = #file, line: Int = #line) {
      log(.error, message, file: file, line: line)
    }

    /// Log fault-level message (critical errors)
    public func fault(_ message: String, file: String = #file, line: Int = #line) {
      log(.fault, message, file: file, line: line)
    }

    private func log(_ type: OSLogType, _ message: String, file: String, line: Int) {
      guard SilkLogger.isEnabled else { return }

      let filename = (file as NSString).lastPathComponent
      let formatted = "[\(category.category)] \(filename):\(line) - \(message)"

      os_log("%{public}@", log: category.osLog, type: type, formatted)
    }
  }
}

// MARK: - Convenience Extensions

extension SilkLogger {
  /// Log an AX API call with its result
  public static func logAXCall(
    _ function: String,
    element: String? = nil,
    attribute: String? = nil,
    result: AXError,
    file: String = #file,
    line: Int = #line
  ) {
    var msg = "AXCall: \(function)"
    if let element = element { msg += " element=\(element)" }
    if let attr = attribute { msg += " attr=\(attr)" }
    msg += " → \(result.rawValue)"

    if result == .success {
      ax.debug(msg, file: file, line: line)
    } else {
      ax.error(msg, file: file, line: line)
    }
  }

  /// Log a coordinate conversion
  public static func logCoordinateConversion(
    from: String,
    to: String,
    x: CGFloat,
    y: CGFloat,
    newX: CGFloat,
    newY: CGFloat,
    file: String = #file,
    line: Int = #line
  ) {
    coordinate.debug(
      "Convert: \(from)→\(to) (\(x),\(y)) → (\(newX),\(newY))",
      file: file,
      line: line
    )
  }

  /// Log a permission check
  public static func logPermissionCheck(
    _ permissionName: String,
    granted: Bool,
    file: String = #file,
    line: Int = #line
  ) {
    let status = granted ? "✅ granted" : "❌ denied"
    permission.info("\(permissionName): \(status)", file: file, line: line)
  }
}
