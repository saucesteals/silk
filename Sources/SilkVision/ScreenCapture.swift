import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Errors

/// Errors produced by the vision layer.
public enum CaptureError: Error, LocalizedError, Sendable {
  case screenRecordingDenied
  case noDisplayFound
  case displayNotFound(CGDirectDisplayID)
  case captureFailed(String)
  case saveFailed(String)

  public var errorDescription: String? {
    switch self {
    case .screenRecordingDenied:
      "Screen Recording permission required. Grant access in System Settings → Privacy & Security → Screen Recording, then restart the app."
    case .noDisplayFound:
      "No displays found."
    case .displayNotFound(let id):
      "Display \(id) not found."
    case .captureFailed(let reason):
      "Capture failed: \(reason)"
    case .saveFailed(let reason):
      "Save failed: \(reason)"
    }
  }
}

// MARK: - Display info

/// Lightweight display descriptor.
public struct DisplayInfo: Sendable {
  public let displayID: CGDirectDisplayID
  public let width: Int
  public let height: Int
  public let isMain: Bool
}

// MARK: - ScreenCapture

/// Screenshot capture via ScreenCaptureKit (macOS 14.0+).
///
/// All methods are static and thread-safe.
public struct ScreenCapture: Sendable {

  // MARK: - List displays

  /// Enumerate connected displays.
  public static func listDisplays() async throws -> [DisplayInfo] {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    let mainID = CGMainDisplayID()
    return content.displays.map { d in
      DisplayInfo(
        displayID: d.displayID, width: d.width, height: d.height, isMain: d.displayID == mainID)
    }
  }

  // MARK: - Capture

  /// Capture the full screen of a display.
  /// - Parameters:
  ///   - display: Target display ID. Pass `0` or `CGMainDisplayID()` for the main display.
  ///   - showCursor: Include the mouse cursor in the capture.
  ///   - retina: Capture at Retina (2×) resolution. Default `true`.
  /// - Returns: Captured `CGImage`.
  public static func capture(
    display: CGDirectDisplayID = 0,
    showCursor: Bool = false,
    retina: Bool = true
  ) async throws -> CGImage {
    try ScreenRecordingPermission.ensureGranted()
    let (scDisplay, _) = try await resolveDisplay(display)
    let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
    let config = makeConfig(scDisplay: scDisplay, retina: retina, showCursor: showCursor)
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
  }

  /// Capture a region of the screen.
  /// - Parameters:
  ///   - region: Screen-coordinate rect to capture.
  ///   - display: Target display ID.
  ///   - retina: Capture at Retina resolution.
  public static func capture(
    region: CGRect,
    display: CGDirectDisplayID = 0,
    showCursor: Bool = false,
    retina: Bool = true
  ) async throws -> CGImage {
    try ScreenRecordingPermission.ensureGranted()
    let (scDisplay, _) = try await resolveDisplay(display)
    let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
    let scale = retina ? 2 : 1
    let config = SCStreamConfiguration()
    config.sourceRect = region
    config.width = Int(region.width) * scale
    config.height = Int(region.height) * scale
    config.showsCursor = showCursor
    config.captureResolution = .best
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
  }

  // MARK: - Save

  /// Save a `CGImage` to disk as PNG or JPEG.
  public static func save(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let ext = url.pathExtension.lowercased()
    let utType: UTType = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png

    guard
      let dest = CGImageDestinationCreateWithURL(
        url as CFURL, utType.identifier as CFString, 1, nil)
    else {
      throw CaptureError.saveFailed("Cannot create image destination at \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
      throw CaptureError.saveFailed("Failed to write image to \(path)")
    }
  }

  // MARK: - Private

  private static func resolveDisplay(_ id: CGDirectDisplayID) async throws -> (
    SCDisplay, SCShareableContent
  ) {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    guard !content.displays.isEmpty else { throw CaptureError.noDisplayFound }
    let targetID = (id == 0) ? CGMainDisplayID() : id
    guard let scDisplay = content.displays.first(where: { $0.displayID == targetID }) else {
      throw CaptureError.displayNotFound(targetID)
    }
    return (scDisplay, content)
  }

  private static func makeConfig(scDisplay: SCDisplay, retina: Bool, showCursor: Bool)
    -> SCStreamConfiguration
  {
    let config = SCStreamConfiguration()
    let scale = retina ? 2 : 1
    config.width = scDisplay.width * scale
    config.height = scDisplay.height * scale
    config.showsCursor = showCursor
    config.captureResolution = .best
    return config
  }
}
