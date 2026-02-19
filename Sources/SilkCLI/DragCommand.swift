import ArgumentParser
import Foundation
import SilkCore
import SilkDrag

struct DragCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "drag",
    abstract: "Drag from one location to another",
    discussion: """
      Examples:
        silk drag 100 200 500 600                    # Instant drag
        silk drag 100 200 500 600 --humanize         # Human-like drag
        silk drag "File.pdf" "Trash" --app Finder    # Element-based drag
        silk drag 100 200 500 600 --button right     # Right-button drag
        silk drag 100 200 500 600 --duration 2.0     # 2 second drag
        silk drag 100 200 500 600 --json             # JSON output
      """
  )

  @Argument(help: "Source X coordinate or element name")
  var fromX: String

  @Argument(help: "Source Y coordinate or destination element name")
  var fromY: String?

  @Argument(help: "Destination X coordinate")
  var toX: String?

  @Argument(help: "Destination Y coordinate")
  var toY: String?

  @Option(name: .long, help: "App name for element-based drag")
  var app: String?

  @Option(name: .long, help: "Mouse button (left, right, middle)")
  var button: String = "left"

  @Option(name: .long, help: "Manual duration override in seconds")
  var duration: Double?

  @Flag(name: .long, help: "Use human-like movement")
  var humanize: Bool = false

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func run() async throws {
    let controller = DragController()
    let result: DragResult

    // Detect mode: coordinates (4 numbers) vs elements (2 strings)
    if let fromYStr = fromY,
      let toXStr = toX,
      let toYStr = toY,
      let fromXNum = Double(fromX),
      let fromYNum = Double(fromYStr),
      let toXNum = Double(toXStr),
      let toYNum = Double(toYStr)
    {
      // Coordinate mode
      let mouseButton = parseButton(button)
      let options = DragOptions(
        from: CGPoint(x: fromXNum, y: fromYNum),
        to: CGPoint(x: toXNum, y: toYNum),
        button: mouseButton,
        humanize: humanize,
        duration: duration
      )
      result = try await controller.drag(options)
    } else if let toElement = fromY {
      // Element mode: fromX = source element, fromY = destination element
      result = try await controller.dragElements(
        from: fromX,
        to: toElement,
        app: app,
        humanize: humanize
      )
    } else {
      throw ValidationError("Provide 4 coordinates (fromX fromY toX toY) or 2 element names")
    }

    // Output
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let humanizedStr = result.humanized ? " (humanized)" : ""
      print(
        "✅ Dragged from (\(Int(result.fromX)), \(Int(result.fromY))) to (\(Int(result.toX)), \(Int(result.toY))) in \(result.durationMs)ms\(humanizedStr)"
      )
      print("   Distance: \(Int(result.distance))px")
    }
  }

  private func parseButton(_ str: String) -> MouseButton {
    switch str.lowercased() {
    case "right": return .right
    case "middle", "center": return .center
    default: return .left
    }
  }
}
