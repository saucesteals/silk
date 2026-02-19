import AppKit
import ArgumentParser
import CoreGraphics
import Foundation
import Silk
import SilkAccessibility
import SilkApp
import SilkClipboard
import SilkCore
import SilkDialog
import SilkDrag
import SilkKeyboard
import SilkMenu
import SilkScroll
import SilkVision
import SilkWindow

@main
struct SilkV2: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "silk",
    abstract: "Accessibility-first macOS automation for AI agents",
    version: "2.1.0",
    subcommands: [
      ClickCommand.self,
      TypeCommand.self,
      FindCommand.self,
      ScreenshotCommand.self,
      OCRCommand.self,
      DragCommand.self,
      KeyCommand.self,
      PasteCommand.self,
      ScrollCommand.self,
      AppCommand.self,
      WindowCommand.self,
      MenuCommand.self,
      DockCommand.self,
      ClipboardCommand.self,
      DialogCommand.self,
    ]
  )
}

// MARK: - Vision Commands

struct ScreenshotCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "screenshot",
    abstract: "Capture a screenshot and save to file",
    discussion: """
      Examples:
        silk screenshot /tmp/screen.png
        silk screenshot --region 0,0,800,600 /tmp/region.png
        silk screenshot --info
        silk screenshot --json
      """
  )

  @Argument(help: "Output file path (default: /tmp/silk_screenshot.png)")
  var path: String?

  @Option(name: .long, help: "Capture region as X,Y,W,H (e.g. 100,200,800,600)")
  var region: String?

  @Option(name: .long, help: "Capture a specific window by name (not yet implemented)")
  var window: String?

  @Flag(name: .long, help: "Include screen metadata and OCR text in output")
  var info: Bool = false

  @Flag(name: .long, help: "Output result as JSON")
  var json: Bool = false

  func run() async throws {
    let outputPath = path ?? "/tmp/silk_screenshot.png"
    let parsedRegion = try parseRegion(region)

    do {
      let image: CGImage
      if let rect = parsedRegion {
        image = try await ScreenCapture.capture(region: rect)
      } else {
        image = try await ScreenCapture.capture()
      }

      try ScreenCapture.save(image, to: outputPath)

      if info {
        // Run OCR on the captured image
        let observations = try OCREngine.recognizeText(in: image)

        if json {
          struct ScreenshotInfoResult: Codable {
            let status: String
            let path: String
            let width: Int
            let height: Int
            let text_count: Int
            let texts: [TextItem]

            struct TextItem: Codable {
              let text: String
              let confidence: Float
              let x: Int
              let y: Int
              let width: Int
              let height: Int
            }
          }

          let items = observations.map { obs in
            let rect = obs.screenRect(
              imageWidth: CGFloat(image.width), imageHeight: CGFloat(image.height))
            return ScreenshotInfoResult.TextItem(
              text: obs.text,
              confidence: obs.confidence,
              x: Int(rect.origin.x),
              y: Int(rect.origin.y),
              width: Int(rect.width),
              height: Int(rect.height)
            )
          }

          let result = ScreenshotInfoResult(
            status: "ok",
            path: outputPath,
            width: image.width,
            height: image.height,
            text_count: observations.count,
            texts: items
          )
          print(encodeJSON(result))
        } else {
          print("✅ Screenshot saved: \(outputPath) (\(image.width)×\(image.height))")
          print("   Text regions found: \(observations.count)")
          for (i, obs) in observations.prefix(20).enumerated() {
            let conf = String(format: "%.0f%%", obs.confidence * 100)
            print("   [\(i)] \"\(obs.text)\" (\(conf))")
          }
          if observations.count > 20 {
            print("   ... and \(observations.count - 20) more")
          }
        }
      } else if json {
        let result = JSONOutput.CaptureResult(
          path: outputPath,
          width: image.width,
          height: image.height,
          format: outputPath.hasSuffix(".jpg") || outputPath.hasSuffix(".jpeg") ? "jpeg" : "png",
          displayID: CGMainDisplayID(),
          timestamp: Date(),
          region: parsedRegion
        )
        print(encodeJSON(result))
      } else {
        print("✅ Screenshot saved: \(outputPath) (\(image.width)×\(image.height))")
      }
    } catch {
      if json {
        print(
          encodeJSON(JSONOutput.ErrorResult(error: error.localizedDescription, type: "capture")))
      } else {
        print("❌ Screenshot failed: \(error.localizedDescription)")
      }
      throw ExitCode.failure
    }
  }
}

struct OCRCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ocr",
    abstract: "Extract text from the screen using OCR",
    discussion: """
      Examples:
        silk ocr
        silk ocr --region 0,0,800,600
        silk ocr --json
      """
  )

  @Argument(help: "Image file to OCR (default: capture screen)")
  var path: String?

  @Option(name: .long, help: "Screen region as X,Y,W,H (e.g. 100,200,800,600)")
  var region: String?

  @Option(name: .long, help: "Capture a specific window by name (not yet implemented)")
  var window: String?

  @Flag(name: .long, help: "Output result as JSON")
  var json: Bool = false

  func run() async throws {
    let parsedRegion = try parseRegion(region)

    do {
      let image: CGImage

      if let inputPath = path {
        // Load image from file
        let url = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath)
        guard let dataProvider = CGDataProvider(url: url as CFURL),
          let loaded = CGImage(
            pngDataProviderSource: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          ) ?? loadImageFromFile(url)
        else {
          if json {
            print(
              encodeJSON(
                JSONOutput.ErrorResult(error: "Cannot load image: \(inputPath)", type: "ocr")))
          } else {
            print("❌ Cannot load image: \(inputPath)")
          }
          throw ExitCode.failure
        }
        image = loaded
      } else if let rect = parsedRegion {
        image = try await ScreenCapture.capture(region: rect)
      } else {
        image = try await ScreenCapture.capture()
      }

      let observations = try OCREngine.recognizeText(in: image)

      if json {
        struct OCRResult: Codable {
          let status: String
          let text: String
          let line_count: Int
          let lines: [OCRLine]

          struct OCRLine: Codable {
            let text: String
            let confidence: Float
            let x: Int
            let y: Int
            let width: Int
            let height: Int
          }
        }

        let lines = observations.map { obs in
          let rect = obs.screenRect(
            imageWidth: CGFloat(image.width), imageHeight: CGFloat(image.height))
          return OCRResult.OCRLine(
            text: obs.text,
            confidence: obs.confidence,
            x: Int(rect.origin.x),
            y: Int(rect.origin.y),
            width: Int(rect.width),
            height: Int(rect.height)
          )
        }

        let fullText = observations.map(\.text).joined(separator: "\n")
        let result = OCRResult(
          status: "ok",
          text: fullText,
          line_count: observations.count,
          lines: lines
        )
        print(encodeJSON(result))
      } else {
        if observations.isEmpty {
          print("🔍 No text found on screen")
        } else {
          for obs in observations {
            print(obs.text)
          }
        }
      }
    } catch let error as CaptureError {
      if json {
        print(
          encodeJSON(JSONOutput.ErrorResult(error: error.localizedDescription, type: "capture")))
      } else {
        print("❌ \(error.localizedDescription)")
      }
      throw ExitCode.failure
    } catch {
      if json {
        print(encodeJSON(JSONOutput.ErrorResult(error: error.localizedDescription, type: "ocr")))
      } else {
        print("❌ OCR failed: \(error.localizedDescription)")
      }
      throw ExitCode.failure
    }
  }
}

// MARK: - Vision Helpers

/// Parse a region string "X,Y,W,H" into a CGRect
func parseRegion(_ regionStr: String?) throws -> CGRect? {
  guard let regionStr = regionStr else { return nil }
  let parts = regionStr.split(separator: ",").compactMap {
    Double($0.trimmingCharacters(in: .whitespaces))
  }
  guard parts.count == 4 else {
    throw ValidationError("Region must be X,Y,W,H (e.g. 100,200,800,600)")
  }
  return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
}

/// Load an image from file using NSImage (handles PNG, JPEG, etc.)
func loadImageFromFile(_ url: URL) -> CGImage? {
  guard let nsImage = NSImage(contentsOf: url) else { return nil }
  return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

// MARK: - Helper Functions

func printElement(_ element: Element) {
  let title = element.title ?? "(untitled)"
  let pos = "(\(Int(element.position.x)), \(Int(element.position.y)))"
  let size = "\(Int(element.size.width))×\(Int(element.size.height))"
  let path = element.path.joined(separator: " > ")
  print("\(element.role): \"\(title)\" at \(pos) [\(size)]")
  if !path.isEmpty {
    print("Path: \(path)")
  }

  // Phase 1 Validation: Show new precision attributes
  if let identifier = element.identifier {
    print("Identifier: \(identifier)")
  }
  if let siblingIndex = element.siblingIndex {
    print("Sibling Index: \(siblingIndex)")
  }
  if let parentRole = element.parentRole {
    print("Parent: \(parentRole)")
  }
  if let domId = element.domIdentifier {
    print("DOM ID: \(domId)")
  }
  if let domClasses = element.domClassList, !domClasses.isEmpty {
    print("DOM Classes: \(domClasses.joined(separator: ", "))")
  }

  // Phase 3: Show visibility info
  if let vis = element.visibility {
    if vis.inViewport {
      print("Visibility: ✅ fully visible")
    } else {
      print("Visibility: ⚠️ \(vis.reason.rawValue)")
      if let scroll = vis.requiresScroll {
        print("  Scroll needed: \(scroll.direction) ~\(scroll.estimatedPixels)px")
      }
    }
  }
  if let sc = element.scrollContainer {
    print("Scroll container: \(sc.role)")
    print(
      "  Can scroll: \(sc.canScrollUp ? "↑" : "") \(sc.canScrollDown ? "↓" : "") \(sc.canScrollLeft ? "←" : "") \(sc.canScrollRight ? "→" : "")"
    )
  }
}

// Note: Element and SearchResult Codable conformance added in their modules
