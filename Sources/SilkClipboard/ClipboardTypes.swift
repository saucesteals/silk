import AppKit
import Foundation

/// Clipboard content type
public enum ClipboardType: String, Sendable, Codable {
  case text
  case image
  case url
  case fileURL
  case rtf
  case html
}

/// Clipboard read options
public struct ClipboardReadOptions: Sendable {
  public let type: ClipboardType

  public init(type: ClipboardType = .text) {
    self.type = type
  }
}

/// Clipboard write options
public struct ClipboardWriteOptions: Sendable {
  public let content: ClipboardContent
  public let clear: Bool  // Clear existing clipboard first

  public init(content: ClipboardContent, clear: Bool = true) {
    self.content = content
    self.clear = clear
  }
}

/// Clipboard content
public enum ClipboardContent: Sendable {
  case text(String)
  case image(Data)  // PNG/JPEG data
  case url(String)
  case fileURL(String)
  case rtf(String)
  case html(String)
}

/// Clipboard read result
public struct ClipboardReadResult: Sendable, Encodable {
  public let type: String
  public let content: String  // Text content or base64 for binary
  public let hasImage: Bool
  public let hasURL: Bool
  public let hasFileURL: Bool
  public let durationMs: Int

  enum CodingKeys: String, CodingKey {
    case type, content
    case hasImage = "has_image"
    case hasURL = "has_url"
    case hasFileURL = "has_file_url"
    case durationMs = "duration_ms"
  }

  public init(
    type: String,
    content: String,
    hasImage: Bool,
    hasURL: Bool,
    hasFileURL: Bool,
    durationMs: Int
  ) {
    self.type = type
    self.content = content
    self.hasImage = hasImage
    self.hasURL = hasURL
    self.hasFileURL = hasFileURL
    self.durationMs = durationMs
  }
}

/// Clipboard write result
public struct ClipboardWriteResult: Sendable, Encodable {
  public let type: String
  public let size: Int  // Bytes or character count
  public let durationMs: Int

  enum CodingKeys: String, CodingKey {
    case type, size
    case durationMs = "duration_ms"
  }

  public init(type: String, size: Int, durationMs: Int) {
    self.type = type
    self.size = size
    self.durationMs = durationMs
  }
}
