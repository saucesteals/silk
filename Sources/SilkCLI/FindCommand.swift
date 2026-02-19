import AppKit
import ArgumentParser
import CoreGraphics
import Foundation
import Silk
import SilkAccessibility
import SilkCore

struct FindCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "find",
    abstract: "Find UI elements (inspection only, no action)",
    discussion: """
      Examples:
        silk find "Button 1"
        silk find --role button --app Chrome --json
        silk find "Submit" --all
        silk find "1" --min-width 150  # Large buttons only
        silk find "OK" --parent-role toolbar --sibling-index 2
      """
  )

  @Argument(help: "Text/label to search for")
  var text: String?

  @Option(name: .long, help: "Filter by accessibility role")
  var role: String?

  @Option(name: .long, help: "Target application name")
  var app: String?

  @Flag(name: .long, help: "Require exact text match (no fuzzy)")
  var exact: Bool = false

  @Flag(name: .long, help: "Return all matches, not just best")
  var all: Bool = false

  @Flag(name: .long, help: "Inspect element at current cursor position")
  var atCursor: Bool = false

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  @Flag(name: .long, help: "Draw bounding box around found elements")
  var highlight: Bool = false

  @Option(name: .long, help: "Highlight duration in seconds")
  var highlightDuration: Double = 3.0

  // MARK: Phase 1 Precision Filters

  @Option(name: .long, help: "Filter by accessibility identifier")
  var identifier: String?

  @Option(name: .long, help: "Filter by sibling index (0-based)")
  var siblingIndex: Int?

  @Option(name: .long, help: "Filter by parent element role")
  var parentRole: String?

  @Option(name: .long, help: "Minimum width in pixels")
  var minWidth: Double?

  @Option(name: .long, help: "Maximum width in pixels")
  var maxWidth: Double?

  @Option(name: .long, help: "Minimum height in pixels")
  var minHeight: Double?

  @Option(name: .long, help: "Maximum height in pixels")
  var maxHeight: Double?

  func validate() throws {
    if !atCursor && text == nil && role == nil && identifier == nil {
      throw ValidationError("Provide search text, --role, --identifier, or --at-cursor")
    }
  }

  func run() async throws {
    // Handle --at-cursor mode
    if atCursor {
      let mouse = MouseController()
      let pos = mouse.getPosition()
      let screenHeight = NSScreen.main?.frame.height ?? 1080
      let cgY = screenHeight - pos.y

      if var element = AccessibilityQuery.elementAt(x: pos.x, y: cgY) {
        // Compute visibility for single element
        let (vis, sc) = computeVisibility(for: element)
        element.visibility = vis
        element.scrollContainer = sc

        if json {
          printJSON(element)
        } else {
          printElement(element)
        }
      } else {
        if !json {
          print("❌ No element found at cursor position (\(Int(pos.x)), \(Int(pos.y)))")
        }
        throw ExitCode.failure
      }
      return
    }

    // Normal query mode
    let query = ElementQuery(
      text: text,
      role: role,
      application: app,
      fuzzyMatch: !exact,
      limit: all ? 100 : 10,
      identifier: identifier,
      siblingIndex: siblingIndex,
      parentRole: parentRole,
      minWidth: minWidth.map { CGFloat($0) },
      maxWidth: maxWidth.map { CGFloat($0) },
      minHeight: minHeight.map { CGFloat($0) },
      maxHeight: maxHeight.map { CGFloat($0) }
    )

    let result = AccessibilityQuery.find(query)

    // Highlight elements if requested
    if highlight {
      for el in result.elements {
        let frame = CGRect(
          x: el.position.x,
          y: el.position.y,
          width: el.size.width,
          height: el.size.height
        )
        let label = el.title ?? el.role
        await ElementHighlight.highlight(frame: frame, duration: highlightDuration, label: label)
      }
    }

    if json {
      printJSON(result)
    } else {
      print(
        "Found \(result.elements.count) element(s) in \(result.durationMs)ms (searched \(result.searchedCount))"
      )
      for (i, el) in result.elements.enumerated() {
        let title = el.title ?? "(untitled)"
        let pos = "(\(Int(el.position.x)), \(Int(el.position.y)))"
        let size = "\(Int(el.size.width))×\(Int(el.size.height))"
        let path = el.path.joined(separator: " > ")

        // Phase 3: Show visibility info
        var visStr = ""
        if let vis = el.visibility {
          if vis.inViewport {
            visStr = " ✅"
          } else {
            visStr = " ⚠️ \(vis.reason.rawValue)"
            if let scroll = vis.requiresScroll {
              visStr += " (scroll \(scroll.direction) ~\(scroll.estimatedPixels)px)"
            }
          }
        }

        print("  [\(i)] \(el.role): \"\(title)\" at \(pos) [\(size)]\(visStr)")
        if !path.isEmpty {
          print("      Path: \(path)")
        }
      }
    }

    // Keep process alive for highlight duration if not JSON mode
    if highlight && !json {
      try? await Task.sleep(nanoseconds: UInt64(highlightDuration * 1_000_000_000))
    }
  }
}
