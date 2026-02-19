import CoreGraphics
import Foundation

/// JSON-encodable output formats for CLI commands
public enum JSONOutput {
  /// Mouse position result
  public struct Position: Codable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  /// Mouse move result
  public struct MoveResult: Codable {
    public let status: String
    public let action: String
    public let x: Double
    public let y: Double
    public let humanized: Bool
    public let duration_ms: Int?

    public init(x: Double, y: Double, humanized: Bool, durationMs: Int?) {
      self.status = "ok"
      self.action = "move"
      self.x = x
      self.y = y
      self.humanized = humanized
      self.duration_ms = durationMs
    }
  }

  /// Mouse click result
  public struct ClickResult: Codable {
    public let status: String
    public let action: String
    public let x: Double
    public let y: Double
    public let button: String
    public let duration_ms: Int?

    public init(x: Double, y: Double, button: String, durationMs: Int?) {
      self.status = "ok"
      self.action = "click"
      self.x = x
      self.y = y
      self.button = button
      self.duration_ms = durationMs
    }
  }

  /// Screen capture result
  public struct CaptureResult: Codable {
    public let status: String
    public let path: String
    public let width: Int
    public let height: Int
    public let format: String
    public let display_id: UInt32
    public let timestamp: String
    public let region: Region?

    public struct Region: Codable {
      public let x: Int
      public let y: Int
      public let width: Int
      public let height: Int
    }

    public init(
      path: String,
      width: Int,
      height: Int,
      format: String,
      displayID: UInt32,
      timestamp: Date,
      region: CGRect? = nil
    ) {
      self.status = "ok"
      self.path = path
      self.width = width
      self.height = height
      self.format = format
      self.display_id = displayID

      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      self.timestamp = formatter.string(from: timestamp)

      if let rect = region {
        self.region = Region(
          x: Int(rect.origin.x),
          y: Int(rect.origin.y),
          width: Int(rect.width),
          height: Int(rect.height)
        )
      } else {
        self.region = nil
      }
    }
  }

  /// Error result
  public struct ErrorResult: Codable {
    public let status: String
    public let error: String
    public let error_type: String?

    public init(error: String, type: String? = nil) {
      self.status = "error"
      self.error = error
      self.error_type = type
    }
  }
}

/// JSON encoding helper - returns compact JSON string
public func encodeJSON<T: Encodable>(_ value: T) -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]

  guard let data = try? encoder.encode(value),
    let string = String(data: data, encoding: .utf8)
  else {
    return "{\"status\":\"error\",\"error\":\"JSON encoding failed\"}"
  }

  return string
}

/// Pretty-print JSON helper - prints formatted JSON to stdout
public func printJSON<T: Encodable>(_ value: T) {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  if let data = try? encoder.encode(value),
    let str = String(data: data, encoding: .utf8)
  {
    print(str)
  }
}
