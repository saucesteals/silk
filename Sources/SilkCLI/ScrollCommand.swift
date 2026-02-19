import AppKit
import ApplicationServices
import ArgumentParser
import CoreGraphics
import Foundation
import Silk
import SilkAccessibility
import SilkScroll

struct ScrollCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "scroll",
    abstract: "Scroll in a direction or to an element",
    discussion: """
      Examples:
        silk scroll down                        # Default scroll (3 units)
        silk scroll down --pages 1              # Scroll one full page
        silk scroll up --pages 2                # Scroll two pages up
        silk scroll down --amount 10            # Scroll 10 units (100 pixels)
        silk scroll down --smooth               # Smooth scrolling
        silk scroll down --at 500,300           # Scroll at specific point
        silk scroll to "Submit" --app Chrome    # Scroll element into view
        silk scroll down --from "Content"       # Scroll in element's container
        silk scroll right --amount 5
        silk scroll down --json

      Scroll by pages (recommended):
        --pages 1    = Scroll exactly one viewport height
        --pages 0.5  = Scroll half a page
        
      This ensures you never miss content between scrolls.
      """
  )

  @Argument(help: "Direction (up, down, left, right, to)")
  var direction: String

  @Option(help: "Amount to scroll (in scroll units, default 3)")
  var amount: Int?

  @Option(help: "Scroll by viewport pages (1.0 = one full page, 0.5 = half page)")
  var pages: Double?

  @Option(help: "Scroll at specific point (X,Y)")
  var at: String?

  @Option(help: "Scroll from a named element (uses its scroll container center)")
  var from: String?

  @Option(help: "App name for element-based scroll")
  var app: String?

  @Flag(help: "Smooth scrolling")
  var smooth: Bool = false

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() async throws {
    // Handle 'to' direction - scroll element into view
    if direction.lowercased() == "to" {
      guard let targetText = from else {
        throw ValidationError("Direction 'to' requires --from <element_name>")
      }

      // Find element
      let query = ElementQuery(
        text: targetText,
        role: nil,
        application: app,
        fuzzyMatch: true,
        limit: 1,
        identifier: nil,
        siblingIndex: nil,
        parentRole: nil,
        minWidth: nil,
        maxWidth: nil,
        minHeight: nil,
        maxHeight: nil
      )

      let result = AccessibilityQuery.find(query)

      guard let element = result.elements.first else {
        if !json {
          print("❌ No matching element found")
        }
        throw ExitCode.failure
      }

      // Check if already visible
      let alreadyVisible =
        !(element.size.height == 0 || element.size.width == 0)
        && (element.visibility?.inViewport ?? true)

      if alreadyVisible {
        if json {
          struct ScrollToResult: Codable {
            let success = true
            let element: String
            let position: [String: CGFloat]
            let attempts = 0
            let scrolledBy = [String: CGFloat]()
            let method = "none"
            let message = "Element already visible"
          }
          let output = ScrollToResult(
            element: element.label,
            position: ["x": element.position.x, "y": element.position.y]
          )
          print(encodeJSON(output))
        } else {
          print(
            "✓ Element '\(targetText)' already visible at (\(Int(element.position.x)), \(Int(element.position.y)))"
          )
        }
        return
      }

      // Scroll into view
      do {
        let maxAttempts = 8
        let scrollService = ScrollIntoViewService(maxAttempts: maxAttempts)
        let scrollResult = try await scrollService.scrollIntoView(element)

        if json {
          struct ScrollToResult: Codable {
            let success: Bool
            let element: String
            let position: [String: CGFloat]
            let attempts: Int
            let scrolledBy: [String: CGFloat]
            let method: String
          }
          let output = ScrollToResult(
            success: scrollResult.success,
            element: element.label,
            position: [
              "x": scrollResult.finalPosition.x,
              "y": scrollResult.finalPosition.y,
            ],
            attempts: scrollResult.attempts,
            scrolledBy: [
              "x": scrollResult.scrolledBy.x,
              "y": scrollResult.scrolledBy.y,
            ],
            method: scrollResult.method
          )
          print(encodeJSON(output))
        } else {
          print("✓ Scrolled '\(targetText)' into view")
          print(
            "  Position: (\(Int(scrollResult.finalPosition.x)), \(Int(scrollResult.finalPosition.y)))"
          )
          print("  Attempts: \(scrollResult.attempts)")
          print("  Method: \(scrollResult.method)")
        }
      } catch let error as ScrollIntoViewError {
        if json {
          struct ErrorOutput: Codable {
            let success = false
            let error: String
            let element: String
          }
          print(encodeJSON(ErrorOutput(error: error.description, element: element.label)))
        } else {
          print("❌ \(error.description)")
        }
        throw ExitCode.failure
      }
      return
    }

    // Parse direction for normal scrolling
    guard let scrollDir = ScrollDirection(rawValue: direction.lowercased()) else {
      throw ValidationError(
        "Invalid direction: \(direction). Use: up, down, left, right, to"
      )
    }

    // Calculate scroll amount
    let scrollAmount: Int
    if let pageCount = pages {
      // Get viewport height and convert to scroll units
      let viewportHeight = getViewportHeight()
      let pixelsPerUnit: Int = 10
      scrollAmount = Int(Double(viewportHeight) * Double(pageCount) / Double(pixelsPerUnit))
    } else if let amt = amount {
      scrollAmount = amt
    } else {
      scrollAmount = 3  // default
    }

    // Determine target
    let target: ScrollTarget
    if let fromElement = from {
      // Resolve element and use its scroll container center
      let point = try resolveScrollContainerCenter(fromElement: fromElement)
      target = .point(point)
    } else if let atStr = at {
      let parts = atStr.split(separator: ",").compactMap {
        Double($0.trimmingCharacters(in: .whitespaces))
      }
      guard parts.count == 2 else {
        throw ValidationError(
          "Invalid point format. Use: X,Y (e.g. 500,300)"
        )
      }
      target = .point(CGPoint(x: parts[0], y: parts[1]))
    } else {
      target = .global
    }

    // Execute scroll
    let controller = ScrollController()
    let options = ScrollOptions(
      direction: scrollDir,
      amount: scrollAmount,
      smooth: smooth,
      target: target
    )
    let result = try await controller.scroll(options)

    // Output
    if json {
      printJSON(result)
    } else {
      let smoothStr = result.smooth ? " (smooth)" : ""
      print(
        "✅ Scrolled \(result.direction) by \(result.amount) in \(result.durationMs)ms\(smoothStr)"
      )
    }
  }

  /// Get the height of the frontmost window's viewport
  private func getViewportHeight() -> CGFloat {
    // Get the frontmost application
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
      // Fallback: use main screen height
      return NSScreen.main?.frame.height ?? 900
    }

    let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

    // Try to get the focused window
    var windowRef: AnyObject?
    if AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedWindowAttribute as CFString,
      &windowRef
    ) == .success,
      let window = windowRef
    {
      // Get window size
      var sizeRef: AnyObject?
      if AXUIElementCopyAttributeValue(
        window as! AXUIElement,
        kAXSizeAttribute as CFString,
        &sizeRef
      ) == .success,
        let sizeVal = sizeRef,
        CFGetTypeID(sizeVal) == AXValueGetTypeID()
      {
        var size = CGSize.zero
        if AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) {
          return size.height
        }
      }
    }

    // Fallback: use main screen height
    return NSScreen.main?.frame.height ?? 900
  }

  /// Resolve element and return its scroll container's center point
  private func resolveScrollContainerCenter(fromElement: String) throws -> CGPoint {
    // Find the element
    let query = ElementQuery(
      text: fromElement,
      role: nil,
      application: app,
      fuzzyMatch: true,
      limit: 1,
      identifier: nil,
      siblingIndex: nil,
      parentRole: nil,
      minWidth: nil,
      maxWidth: nil,
      minHeight: nil,
      maxHeight: nil
    )

    let result = AccessibilityQuery.find(query)

    guard let element = result.elements.first else {
      throw ValidationError("Element '\(fromElement)' not found")
    }

    // Find scroll container
    guard let (scrollContainer, _) = findScrollContainer(for: element.axElement) else {
      throw ValidationError("No scroll container found for element '\(fromElement)'")
    }

    // Get container frame
    let containerFrame = axFrame(of: scrollContainer)

    // Return center point
    return CGPoint(x: containerFrame.midX, y: containerFrame.midY)
  }

  /// Find scroll container for an element
  private func findScrollContainer(for element: AXUIElement) -> (AXUIElement, String)? {
    var current = element
    var steps = 0
    let maxSteps = 50

    while steps < maxSteps {
      var parentRef: AnyObject?
      guard
        AXUIElementCopyAttributeValue(
          current,
          kAXParentAttribute as CFString,
          &parentRef
        ) == .success
      else {
        return nil
      }

      let parent = parentRef as! AXUIElement

      var roleRef: AnyObject?
      if AXUIElementCopyAttributeValue(
        parent,
        kAXRoleAttribute as CFString,
        &roleRef
      ) == .success,
        let role = roleRef as? String
      {
        if scrollableRoles.contains(role) {
          return (parent, role)
        }
        if role == "AXApplication" {
          return nil
        }
      }

      current = parent
      steps += 1
    }

    return nil
  }

  /// Get frame of an AXUIElement
  private func axFrame(of element: AXUIElement) -> CGRect {
    var posRef: AnyObject?
    var sizeRef: AnyObject?

    let posResult = AXUIElementCopyAttributeValue(
      element,
      kAXPositionAttribute as CFString,
      &posRef
    )
    let sizeResult = AXUIElementCopyAttributeValue(
      element,
      kAXSizeAttribute as CFString,
      &sizeRef
    )

    guard posResult == .success, sizeResult == .success,
      let posVal = posRef, let sizeVal = sizeRef
    else {
      return .zero
    }

    var position = CGPoint.zero
    var size = CGSize.zero

    AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
    AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

    return CGRect(origin: position, size: size)
  }
}

// MARK: - Constants

private let scrollableRoles: Set<String> = [
  "AXScrollArea",
  "AXWebArea",
  "AXTable",
  "AXList",
]
