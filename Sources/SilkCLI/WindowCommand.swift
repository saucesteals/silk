import ArgumentParser
import Foundation
import SilkWindow

struct WindowCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "window",
    abstract: "Manage application windows",
    subcommands: [
      WindowMoveCommand.self,
      WindowResizeCommand.self,
      WindowCloseCommand.self,
      WindowMinimizeCommand.self,
      WindowMaximizeCommand.self,
      WindowFullscreenCommand.self,
      WindowListCommand.self,
    ]
  )
}

// MARK: - Move

struct WindowMoveCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "move",
    abstract: "Move window to coordinates",
    discussion: """
      Examples:
        silk window move Safari 100 100
        silk window move Safari 100 100 --title "Google"
        silk window move Safari 100 100 --index 0
      """
  )

  @Argument(help: "Application name")
  var app: String

  @Argument(help: "X coordinate")
  var x: Int

  @Argument(help: "Y coordinate")
  var y: Int

  @Option(help: "Window title (partial match)")
  var title: String?

  @Option(help: "Window index (0 = frontmost)")
  var index: Int?

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = WindowController()
    let identifier = WindowIdentifier(app: app, title: title, index: index)
    let options = WindowMoveOptions(identifier: identifier, x: x, y: y)
    let result = try controller.move(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let titleStr = result.windowTitle.map { " (\($0))" } ?? ""
      print(
        "✅ Moved \(result.appName)\(titleStr) to (\(result.x ?? 0), \(result.y ?? 0)) in \(result.durationMs)ms"
      )
    }
  }
}

// MARK: - Resize

struct WindowResizeCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "resize",
    abstract: "Resize window",
    discussion: """
      Examples:
        silk window resize Chrome 1200 800
        silk window resize Safari 800 600 --title "Google"
      """
  )

  @Argument(help: "Application name")
  var app: String

  @Argument(help: "Width in pixels")
  var width: Int

  @Argument(help: "Height in pixels")
  var height: Int

  @Option(help: "Window title (partial match)")
  var title: String?

  @Option(help: "Window index (0 = frontmost)")
  var index: Int?

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = WindowController()
    let identifier = WindowIdentifier(app: app, title: title, index: index)
    let options = WindowResizeOptions(identifier: identifier, width: width, height: height)
    let result = try controller.resize(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let titleStr = result.windowTitle.map { " (\($0))" } ?? ""
      print(
        "✅ Resized \(result.appName)\(titleStr) to \(result.width ?? 0)×\(result.height ?? 0) in \(result.durationMs)ms"
      )
    }
  }
}

// MARK: - Close

struct WindowCloseCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "close",
    abstract: "Close window",
    discussion: """
      Examples:
        silk window close Terminal
        silk window close Safari --title "Google"
      """
  )

  @Argument(help: "Application name")
  var app: String

  @Option(help: "Window title (partial match)")
  var title: String?

  @Option(help: "Window index (0 = frontmost)")
  var index: Int?

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = WindowController()
    let identifier = WindowIdentifier(app: app, title: title, index: index)
    let options = WindowCloseOptions(identifier: identifier)
    let result = try controller.close(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let titleStr = result.windowTitle.map { " (\($0))" } ?? ""
      print("✅ Closed \(result.appName)\(titleStr) in \(result.durationMs)ms")
    }
  }
}

// MARK: - Minimize

struct WindowMinimizeCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "minimize",
    abstract: "Minimize window to dock",
    discussion: """
      Examples:
        silk window minimize Finder
        silk window minimize Safari --title "Google"
      """
  )

  @Argument(help: "Application name")
  var app: String

  @Option(help: "Window title (partial match)")
  var title: String?

  @Option(help: "Window index (0 = frontmost)")
  var index: Int?

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = WindowController()
    let identifier = WindowIdentifier(app: app, title: title, index: index)
    let options = WindowStateOptions(identifier: identifier, state: .minimize)
    let result = try controller.setState(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let titleStr = result.windowTitle.map { " (\($0))" } ?? ""
      print("✅ Minimized \(result.appName)\(titleStr) in \(result.durationMs)ms")
    }
  }
}

// MARK: - Maximize

struct WindowMaximizeCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "maximize",
    abstract: "Maximize window (zoom)",
    discussion: """
      Examples:
        silk window maximize TextEdit
        silk window maximize Safari --title "Google"
      """
  )

  @Argument(help: "Application name")
  var app: String

  @Option(help: "Window title (partial match)")
  var title: String?

  @Option(help: "Window index (0 = frontmost)")
  var index: Int?

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = WindowController()
    let identifier = WindowIdentifier(app: app, title: title, index: index)
    let options = WindowStateOptions(identifier: identifier, state: .maximize)
    let result = try controller.setState(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let titleStr = result.windowTitle.map { " (\($0))" } ?? ""
      print("✅ Maximized \(result.appName)\(titleStr) in \(result.durationMs)ms")
    }
  }
}

// MARK: - Fullscreen

struct WindowFullscreenCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "fullscreen",
    abstract: "Toggle fullscreen mode",
    discussion: """
      Examples:
        silk window fullscreen Safari
        silk window fullscreen Safari --title "Google"
      """
  )

  @Argument(help: "Application name")
  var app: String

  @Option(help: "Window title (partial match)")
  var title: String?

  @Option(help: "Window index (0 = frontmost)")
  var index: Int?

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = WindowController()
    let identifier = WindowIdentifier(app: app, title: title, index: index)
    let options = WindowStateOptions(identifier: identifier, state: .fullscreen)
    let result = try controller.setState(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let titleStr = result.windowTitle.map { " (\($0))" } ?? ""
      print("✅ Toggled fullscreen for \(result.appName)\(titleStr) in \(result.durationMs)ms")
    }
  }
}

// MARK: - List

struct WindowListCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List all windows",
    discussion: """
      Examples:
        silk window list
        silk window list --app Chrome
        silk window list --json
      """
  )

  @Option(help: "Filter by application name")
  var app: String?

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = WindowController()
    let windows = try controller.listWindows(app: app)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(windows)
      print(String(data: data, encoding: .utf8)!)
    } else {
      print("Windows (\(windows.count)):")
      for window in windows {
        let minimizedStr = window.isMinimized ? " (minimized)" : ""
        let fullscreenStr = window.isFullscreen ? " (fullscreen)" : ""
        print("  • [\(window.appName)] \(window.title)\(minimizedStr)\(fullscreenStr)")
        print("    Position: (\(window.x), \(window.y)) Size: \(window.width)×\(window.height)")
      }
    }
  }
}
