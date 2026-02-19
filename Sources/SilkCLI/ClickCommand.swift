import ArgumentParser
import CoreGraphics
import Foundation
import Silk
import SilkAccessibility
import SilkCore
import SilkScroll

struct ClickCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "click",
    abstract: "Find and click a UI element",
    discussion: """
      Examples:
        silk click "Button 1"
        silk click "Submit" --humanize --trail
        silk click --role button --app Chrome
        silk click "Submit" --identifier "submit-btn"
        silk click "1" --min-width 150  # Large button only
        silk click "OK" --parent-role toolbar
      """
  )

  @Argument(help: "Text/label to search for")
  var text: String?

  @Option(name: .long, help: "Filter by accessibility role (button, textField, etc.)")
  var role: String?

  @Option(name: .long, help: "Target application name")
  var app: String?

  @Flag(name: .long, help: "Require exact text match (no fuzzy)")
  var exact: Bool = false

  @Flag(name: .long, help: "Use humanized mouse movement")
  var humanize: Bool = false

  @Flag(name: .long, help: "Show visual trail during movement")
  var trail: Bool = false

  @Option(name: .long, help: "Trail visibility duration in seconds")
  var trailDuration: Double = 3.0

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  @Flag(name: .long, help: "Draw bounding box around target element before clicking")
  var highlight: Bool = false

  @Option(name: .long, help: "Highlight duration in seconds (shown before click)")
  var highlightDuration: Double = 1.5

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

  // MARK: Phase 1 - Scroll Into View

  @Flag(name: .long, help: "Disable auto-scroll for off-screen elements")
  var noScroll: Bool = false

  @Option(name: .long, help: "Maximum scroll attempts (default: 8)")
  var maxScrollAttempts: Int = 8

  func validate() throws {
    if text == nil && role == nil && identifier == nil {
      throw ValidationError("Provide search text, --role, or --identifier")
    }
  }

  func run() async throws {
    let element: Element

    // Check if text is a reference (starts with @)
    if let refText = text, ReferenceResolver.isReference(refText) {
      // Resolve reference
      guard let resolved = ReferenceResolver.resolve(refText, application: app) else {
        if !json {
          print("❌ Could not resolve reference: \(refText)")
        }
        throw ExitCode.failure
      }
      element = resolved
    } else {
      // Normal query
      let query = ElementQuery(
        text: text,
        role: role,
        application: app,
        fuzzyMatch: !exact,
        limit: 1,
        identifier: identifier,
        siblingIndex: siblingIndex,
        parentRole: parentRole,
        minWidth: minWidth.map { CGFloat($0) },
        maxWidth: maxWidth.map { CGFloat($0) },
        minHeight: minHeight.map { CGFloat($0) },
        maxHeight: maxHeight.map { CGFloat($0) }
      )

      let result = AccessibilityQuery.find(query)

      guard let found = result.elements.first else {
        if !json {
          print("❌ No matching element found")
        }
        throw ExitCode.failure
      }
      element = found
    }

    // Auto-scroll into view if element is off-screen (unless --no-scroll is set)
    var targetElement = element
    if !noScroll && isOffScreen(element) {
      if !json {
        print("⚠️  Element is off-screen, scrolling into view...")
      }

      do {
        let scrollService = ScrollIntoViewService(maxAttempts: maxScrollAttempts)
        let scrollResult = try await scrollService.scrollIntoView(element)

        if !json && scrollResult.success {
          print("✓ Scrolled into view (\(scrollResult.attempts) attempts, \(scrollResult.method))")
        }

        // Re-query element to get updated position
        if let updated = requeryElementForClick(element) {
          targetElement = updated
        }
      } catch let error as ScrollIntoViewError {
        if !json {
          print("❌ \(error.description)")
          print("")
          print("Hint: Element may be inside a collapsed section, behind a modal,")
          print("      or in a nested scroll area. Try:")
          print("  1. silk find \"\(element.label)\" --app \(app ?? "App") (check visibility)")
          print("  2. Manually expand any collapsed sections first")
          print("  3. Use silk scroll down --from \"Section Name\" if in nested container")
        }
        throw ExitCode.failure
      }
    }

    // Highlight before clicking if requested
    if highlight {
      let frame = CGRect(
        x: targetElement.position.x,
        y: targetElement.position.y,
        width: targetElement.size.width,
        height: targetElement.size.height
      )
      let label = targetElement.title ?? targetElement.role
      await ElementHighlight.highlight(frame: frame, duration: highlightDuration, label: label)

      // Wait for highlight to be visible
      try await Task.sleep(nanoseconds: UInt64(highlightDuration * 1_000_000_000))
    }

    let actions = ElementActions()
    try await actions.click(
      targetElement,
      humanize: humanize,
      showTrail: trail,
      trailDuration: trailDuration
    )

    if !json {
      let title = targetElement.title ?? "(untitled)"
      let pos = "(\(Int(targetElement.center.x)), \(Int(targetElement.center.y)))"
      print("✅ Clicked \(targetElement.role): \"\(title)\" at \(pos)")
    } else {
      printJSON(targetElement)
    }
  }

  // MARK: - Scroll Helpers

  /// Check if element is off-screen (zero size or outside viewport)
  private func isOffScreen(_ element: Element) -> Bool {
    // Zero-size elements are off-screen
    if element.size.height == 0 || element.size.width == 0 {
      return true
    }

    // Use visibility info if available
    if let visibility = element.visibility {
      return !visibility.inViewport
    }

    // Fallback: assume visible if we can't determine
    return false
  }

  /// Re-query element to get updated position after scroll
  private func requeryElementForClick(_ element: Element) -> Element? {
    let query = ElementQuery(
      text: element.title ?? element.value,
      role: element.role,
      application: app,
      fuzzyMatch: false,
      limit: 1,
      identifier: element.identifier,
      siblingIndex: element.siblingIndex,
      parentRole: element.parentRole,
      minWidth: element.size.width > 0 ? element.size.width - 5 : nil,
      maxWidth: element.size.width > 0 ? element.size.width + 5 : nil,
      minHeight: nil,
      maxHeight: nil
    )

    let result = AccessibilityQuery.find(query)
    return result.elements.first
  }
}
