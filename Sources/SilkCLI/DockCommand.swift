import ArgumentParser
import Foundation
import SilkMenu

struct DockCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dock",
    abstract: "Interact with dock",
    subcommands: [
      DockClickCommand.self,
      DockListCommand.self,
    ]
  )
}

struct DockClickCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "click",
    abstract: "Click dock icon",
    discussion: """
      Examples:
        silk dock click Safari             # Launch/activate Safari
        silk dock click Safari --right     # Right-click for context menu
        silk dock click "System Settings"  # Click System Settings
      """
  )

  @Argument(help: "Application name")
  var appName: String

  @Flag(help: "Right-click (show context menu)")
  var right: Bool = false

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = DockController()
    let options = DockClickOptions(appName: appName, rightClick: right)
    let result = try controller.click(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let clickStr = right ? "Right-clicked" : "Clicked"
      print("✅ \(clickStr) \(result.appName) in dock in \(result.durationMs)ms")
    }
  }
}

struct DockListCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List dock apps",
    discussion: """
      Examples:
        silk dock list           # List all dock apps
        silk dock list --json    # List as JSON
      """
  )

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = DockController()
    let apps = try controller.listApps()

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(apps)
      print(String(data: data, encoding: .utf8)!)
    } else {
      print("Dock apps (\(apps.count)):")
      for app in apps {
        let runningStr = app.isRunning ? " ●" : ""
        print("  • \(app.name)\(runningStr)")
        if !app.bundleId.isEmpty {
          print("    \(app.bundleId)")
        }
      }
    }
  }
}
