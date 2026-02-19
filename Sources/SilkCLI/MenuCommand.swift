import ArgumentParser
import Foundation
import SilkMenu

struct MenuCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "menu",
    abstract: "Interact with menu bar",
    subcommands: [
      MenuClickCommand.self,
      MenuListCommand.self,
    ]
  )
}

struct MenuClickCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "click",
    abstract: "Click a menu item",
    discussion: """
      Examples:
        silk menu click File "New Window"
        silk menu click Edit Copy --app Safari
        silk menu click View "Enter Full Screen"
      """
  )

  @Argument(help: "Menu path (e.g., File 'New Window')")
  var path: [String]

  @Option(help: "Application name (default: frontmost app)")
  var app: String?

  @Flag(help: "Output JSON")
  var json: Bool = false

  func validate() throws {
    guard path.count >= 2 else {
      throw ValidationError("Menu path must have at least 2 items (e.g., File 'New Window')")
    }
  }

  func run() throws {
    let controller = MenuController()
    let options = MenuClickOptions(app: app, menuPath: path)
    let result = try controller.click(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let appStr = result.appName.map { " in \($0)" } ?? ""
      let pathStr = result.menuPath.joined(separator: " → ")
      print("✅ Clicked menu: \(pathStr)\(appStr) in \(result.durationMs)ms")
    }
  }
}

struct MenuListCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List menu items",
    discussion: """
      Examples:
        silk menu list                  # List top-level menus
        silk menu list File             # List File menu items
        silk menu list File --app Chrome
      """
  )

  @Argument(help: "Menu path (optional, e.g., File)")
  var path: [String] = []

  @Option(help: "Application name (default: frontmost app)")
  var app: String?

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = MenuController()
    let items = try controller.listItems(app: app, path: path)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(items)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let pathStr = path.isEmpty ? "Top-level menus" : path.joined(separator: " → ")
      print("\(pathStr) (\(items.count) items):")
      for item in items {
        if item.title == "---" {
          print("  ─────────────────")
          continue
        }
        let enabledStr = item.enabled ? "" : " (disabled)"
        let submenuStr = item.hasSubmenu ? " ▸" : ""
        let shortcutStr = item.shortcut.map { " [\($0)]" } ?? ""
        print("  • \(item.title)\(enabledStr)\(submenuStr)\(shortcutStr)")
      }
    }
  }
}
