import AppKit
import Foundation

/// Controller for clipboard (pasteboard) operations
/// @unchecked because NSPasteboard is not declared Sendable, but NSPasteboard.general
/// is a process-wide singleton that is safe to use from any thread.
public final class ClipboardController: @unchecked Sendable {

  private let pasteboard: NSPasteboard

  public init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  // MARK: - Read

  /// Read clipboard contents
  /// - Parameter options: Read configuration specifying the desired type
  /// - Returns: Result with content (text or base64-encoded binary)
  /// - Throws: If clipboard is empty or requested type is not available
  public func read(_ options: ClipboardReadOptions) throws -> ClipboardReadResult {
    let start = DispatchTime.now()

    guard let types = pasteboard.types, !types.isEmpty else {
      throw ClipboardError.empty
    }

    let content: String
    let typeName: String

    switch options.type {
    case .text:
      guard let text = pasteboard.string(forType: .string) else {
        throw ClipboardError.typeNotAvailable("text")
      }
      content = text
      typeName = "text"

    case .image:
      // Try TIFF first (most common macOS image pasteboard type), then PNG
      if let data = pasteboard.data(forType: .tiff) {
        // Convert TIFF to PNG for a more portable base64 output
        if let bitmapRep = NSBitmapImageRep(data: data),
          let pngData = bitmapRep.representation(using: .png, properties: [:])
        {
          content = pngData.base64EncodedString()
        } else {
          content = data.base64EncodedString()
        }
      } else if let data = pasteboard.data(forType: .png) {
        content = data.base64EncodedString()
      } else {
        throw ClipboardError.typeNotAvailable("image")
      }
      typeName = "image"

    case .url:
      // Try URL type, fall back to string that looks like a URL
      if let urlString = pasteboard.string(forType: .URL) {
        content = urlString
      } else if let str = pasteboard.string(forType: .string),
        URL(string: str) != nil,
        str.hasPrefix("http")
      {
        content = str
      } else {
        throw ClipboardError.typeNotAvailable("url")
      }
      typeName = "url"

    case .fileURL:
      if let urlString = pasteboard.propertyList(forType: .fileURL) as? String {
        content = urlString
      } else if let urls = pasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
        let first = urls.first
      {
        content = first.path
      } else {
        throw ClipboardError.typeNotAvailable("fileURL")
      }
      typeName = "fileURL"

    case .rtf:
      if let data = pasteboard.data(forType: .rtf),
        let rtfString = String(data: data, encoding: .utf8)
      {
        content = rtfString
      } else {
        throw ClipboardError.typeNotAvailable("rtf")
      }
      typeName = "rtf"

    case .html:
      if let htmlString = pasteboard.string(forType: .html) {
        content = htmlString
      } else {
        throw ClipboardError.typeNotAvailable("html")
      }
      typeName = "html"
    }

    let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
    let durationMs = Int(elapsed / 1_000_000)

    return ClipboardReadResult(
      type: typeName,
      content: content,
      hasImage: hasType(.tiff) || hasType(.png),
      hasURL: hasType(.URL),
      hasFileURL: hasType(.fileURL),
      durationMs: durationMs
    )
  }

  // MARK: - Write

  /// Write content to clipboard
  /// - Parameter options: Write configuration with content and clear flag
  /// - Returns: Result with type and size info
  /// - Throws: If write operation fails
  public func write(_ options: ClipboardWriteOptions) throws -> ClipboardWriteResult {
    let start = DispatchTime.now()

    if options.clear {
      pasteboard.clearContents()
    }

    let typeName: String
    let size: Int

    switch options.content {
    case .text(let text):
      pasteboard.setString(text, forType: .string)
      typeName = "text"
      size = text.utf8.count

    case .image(let data):
      // Write as both PNG and TIFF for maximum compatibility
      guard let bitmapRep = NSBitmapImageRep(data: data) else {
        // If we can't parse it as a bitmap, try writing raw data as PNG
        pasteboard.setData(data, forType: .png)
        typeName = "image"
        size = data.count
        break
      }

      if let tiffData = bitmapRep.tiffRepresentation {
        pasteboard.setData(tiffData, forType: .tiff)
      }
      pasteboard.setData(data, forType: .png)
      typeName = "image"
      size = data.count

    case .url(let urlString):
      pasteboard.clearContents()
      pasteboard.setString(urlString, forType: .URL)
      // Also set as plain string so it's pasteable as text
      pasteboard.setString(urlString, forType: .string)
      typeName = "url"
      size = urlString.utf8.count

    case .fileURL(let path):
      let url = URL(fileURLWithPath: path)
      pasteboard.clearContents()
      pasteboard.writeObjects([url as NSURL])
      typeName = "fileURL"
      size = path.utf8.count

    case .rtf(let rtfString):
      guard let data = rtfString.data(using: .utf8) else {
        throw ClipboardError.writeFailed("Failed to encode RTF string")
      }
      pasteboard.setData(data, forType: .rtf)
      typeName = "rtf"
      size = data.count

    case .html(let htmlString):
      pasteboard.setString(htmlString, forType: .html)
      // Also set as plain string fallback
      pasteboard.setString(htmlString, forType: .string)
      typeName = "html"
      size = htmlString.utf8.count
    }

    let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
    let durationMs = Int(elapsed / 1_000_000)

    return ClipboardWriteResult(
      type: typeName,
      size: size,
      durationMs: durationMs
    )
  }

  // MARK: - Available Types

  /// Get list of available clipboard content types
  /// - Returns: Array of recognized clipboard types present on the pasteboard
  public func availableTypes() -> [ClipboardType] {
    guard let types = pasteboard.types else { return [] }

    var result: [ClipboardType] = []

    if types.contains(.string) {
      result.append(.text)
    }
    if types.contains(.tiff) || types.contains(.png) {
      result.append(.image)
    }
    if types.contains(.URL) {
      result.append(.url)
    }
    if types.contains(.fileURL) {
      result.append(.fileURL)
    }
    if types.contains(.rtf) {
      result.append(.rtf)
    }
    if types.contains(.html) {
      result.append(.html)
    }

    return result
  }

  // MARK: - Clear

  /// Clear all clipboard contents
  public func clear() {
    pasteboard.clearContents()
  }

  // MARK: - Private Helpers

  private func hasType(_ type: NSPasteboard.PasteboardType) -> Bool {
    pasteboard.types?.contains(type) ?? false
  }
}

// MARK: - Errors

public enum ClipboardError: Error, LocalizedError {
  case empty
  case typeNotAvailable(String)
  case writeFailed(String)

  public var errorDescription: String? {
    switch self {
    case .empty:
      return "Clipboard is empty"
    case .typeNotAvailable(let type):
      return "Clipboard does not contain \(type) content"
    case .writeFailed(let reason):
      return "Failed to write to clipboard: \(reason)"
    }
  }
}
