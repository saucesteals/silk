import CoreGraphics
import Foundation

/// Options for screen capture operations
public struct CaptureOptions: Sendable {
  /// Region to capture (nil = full screen)
  public let region: CGRect?

  /// Display ID to capture (nil = main display)
  public let displayID: CGDirectDisplayID?

  /// Output format
  public let format: ImageFormat

  /// JPEG quality (0.0-1.0, ignored for PNG)
  public let quality: CGFloat

  public enum ImageFormat: String, Sendable {
    case png
    case jpeg
  }

  public init(
    region: CGRect? = nil,
    displayID: CGDirectDisplayID? = nil,
    format: ImageFormat = .png,
    quality: CGFloat = 0.85
  ) {
    self.region = region
    self.displayID = displayID
    self.format = format
    self.quality = quality
  }
}

/// Result of a screen capture operation
public struct CaptureResult: Sendable {
  public let path: String
  public let width: Int
  public let height: Int
  public let format: String
  public let timestamp: Date
  public let displayID: CGDirectDisplayID

  public init(
    path: String,
    width: Int,
    height: Int,
    format: String,
    timestamp: Date,
    displayID: CGDirectDisplayID
  ) {
    self.path = path
    self.width = width
    self.height = height
    self.format = format
    self.timestamp = timestamp
    self.displayID = displayID
  }
}
