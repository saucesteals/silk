import ArgumentParser
import Foundation
import SilkApp

struct AppCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "app",
    abstract: "Manage applications",
    subcommands: [
      AppLaunchCommand.self,
      AppQuitCommand.self,
      AppHideCommand.self,
      AppSwitchCommand.self,
      AppListCommand.self,
    ]
  )
}

// MARK: - Launch

struct AppLaunchCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "launch",
    abstract: "Launch an application",
    discussion: """
      Examples:
        silk app launch Chrome
        silk app launch Safari --url https://google.com
        silk app launch TextEdit --file ~/document.txt
        silk app launch Terminal --hidden
        silk app launch Finder --background
      """
  )

  @Argument(help: "Application name")
  var appName: String

  @Option(help: "URL or file path to open")
  var url: String?

  @Option(help: "File path to open (alias for --url)")
  var file: String?

  @Flag(help: "Launch hidden")
  var hidden: Bool = false

  @Flag(help: "Don't activate (stay in background)")
  var background: Bool = false

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() async throws {
    let controller = AppController()

    let openURL = url ?? file
    let options = LaunchOptions(
      appName: appName,
      openURL: openURL,
      hidden: hidden,
      activate: !background
    )

    let result = try await controller.launch(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      print("✅ Launched \(result.appName) (PID: \(result.pid ?? -1)) in \(result.durationMs)ms")
      if let bundleId = result.bundleId {
        print("   Bundle ID: \(bundleId)")
      }
    }
  }
}

// MARK: - Quit

struct AppQuitCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "quit",
    abstract: "Quit an application",
    discussion: """
      Examples:
        silk app quit Chrome
        silk app quit Safari --force
      """
  )

  @Argument(help: "Application name")
  var appName: String

  @Flag(help: "Force quit (SIGKILL)")
  var force: Bool = false

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() async throws {
    let controller = AppController()
    let options = QuitOptions(appName: appName, force: force)
    let result = try await controller.quit(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let forceStr = force ? " (forced)" : ""
      if result.success {
        print("✅ Quit \(result.appName)\(forceStr) in \(result.durationMs)ms")
      } else {
        print(
          "⚠️  Quit sent to \(result.appName)\(forceStr) but app may still be running (\(result.durationMs)ms)"
        )
      }
    }
  }
}

// MARK: - Hide

struct AppHideCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "hide",
    abstract: "Hide an application",
    discussion: """
      Examples:
        silk app hide Chrome
        silk app hide Safari --json
      """
  )

  @Argument(help: "Application name")
  var appName: String

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = AppController()
    let options = HideOptions(appName: appName)
    let result = try controller.hide(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      if result.success {
        print("✅ Hid \(result.appName) in \(result.durationMs)ms")
      } else {
        print("❌ Failed to hide \(result.appName)")
      }
    }
  }
}

// MARK: - Switch

struct AppSwitchCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "switch",
    abstract: "Switch to an application (bring to front)",
    discussion: """
      Examples:
        silk app switch Chrome
        silk app switch Terminal --json
      """
  )

  @Argument(help: "Application name")
  var appName: String

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = AppController()
    let options = SwitchOptions(appName: appName)
    let result = try controller.switchTo(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      if result.success {
        print(
          "✅ Switched to \(result.appName) (PID: \(result.pid ?? -1)) in \(result.durationMs)ms")
      } else {
        print("❌ Failed to switch to \(result.appName)")
      }
    }
  }
}

// MARK: - List

struct AppListCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List all running applications",
    discussion: """
      Examples:
        silk app list
        silk app list --json
      """
  )

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = AppController()
    let apps = controller.listRunning()

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(apps)
      print(String(data: data, encoding: .utf8)!)
    } else {
      print("Running applications (\(apps.count)):")
      for app in apps {
        let activeStr = app.isActive ? " (active)" : ""
        let hiddenStr = app.isHidden ? " (hidden)" : ""
        print("  • \(app.name) [PID: \(app.pid)]\(activeStr)\(hiddenStr)")
        print("    \(app.bundleId)")
      }
    }
  }
}
