import ArgumentParser
import Foundation
import SilkDialog

struct DialogCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dialog",
    abstract: "System dialog operations",
    subcommands: [
      DialogClickCommand.self,
      DialogInputCommand.self,
      DialogListCommand.self,
      DialogWaitCommand.self,
    ]
  )
}

// MARK: - Click

struct DialogClickCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "click",
    abstract: "Click button in dialog",
    discussion: """
      Examples:
        silk dialog click "OK"
        silk dialog click "Cancel" --timeout 10
        silk dialog click "Save" --json
      """
  )

  @Argument(help: "Button text (e.g., OK, Cancel, Save)")
  var buttonText: String

  @Option(help: "Timeout in seconds")
  var timeout: Double = 5.0

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = DialogController()
    let options = DialogClickOptions(buttonText: buttonText, timeout: timeout)
    let result = try controller.click(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      if result.found {
        let titleStr = result.dialogTitle.map { " in \"\($0)\"" } ?? ""
        print("✅ Clicked \"\(buttonText)\"\(titleStr) in \(result.durationMs)ms")
      } else {
        print("❌ Dialog or button not found")
      }
    }
  }
}

// MARK: - Input

struct DialogInputCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "input",
    abstract: "Type into dialog text field",
    discussion: """
      Examples:
        silk dialog input "username" --field "Username"
        silk dialog input "password" --field-index 1
        silk dialog input "text" --submit
      """
  )

  @Argument(help: "Text to type")
  var text: String

  @Option(help: "Field label/placeholder")
  var field: String?

  @Option(name: .long, help: "Field index (0-based)")
  var fieldIndex: Int?

  @Flag(help: "Press Enter after typing")
  var submit: Bool = false

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = DialogController()
    let options = DialogInputOptions(
      fieldLabel: field,
      fieldIndex: fieldIndex,
      text: text,
      submit: submit
    )
    let result = try controller.input(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      if result.found {
        let submitStr = submit ? " and submitted" : ""
        print("✅ Typed text\(submitStr) in \(result.durationMs)ms")
      } else {
        print("❌ Dialog or field not found")
      }
    }
  }
}

// MARK: - List

struct DialogListCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List all visible dialogs",
    discussion: """
      Examples:
        silk dialog list
        silk dialog list --json
      """
  )

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = DialogController()
    let dialogs = try controller.listDialogs()

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(dialogs)
      print(String(data: data, encoding: .utf8)!)
    } else {
      if dialogs.isEmpty {
        print("No dialogs found")
      } else {
        print("Visible dialogs (\(dialogs.count)):")
        for dialog in dialogs {
          print("  • \"\(dialog.title)\" [\(dialog.type)]")
          if let message = dialog.message {
            print("    \(message)")
          }
          if !dialog.buttons.isEmpty {
            print("    Buttons: \(dialog.buttons.joined(separator: ", "))")
          }
          if dialog.textFields > 0 {
            print("    Text fields: \(dialog.textFields)")
          }
        }
      }
    }
  }
}

// MARK: - Wait

struct DialogWaitCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "wait",
    abstract: "Wait for dialog to appear",
    discussion: """
      Examples:
        silk dialog wait --title "Save"
        silk dialog wait --timeout 20
        silk dialog wait --json
      """
  )

  @Option(help: "Expected title (substring match)")
  var title: String?

  @Option(help: "Timeout in seconds")
  var timeout: Double = 10.0

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() throws {
    let controller = DialogController()
    let dialog = try controller.waitForDialog(titleContains: title, timeout: timeout)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(dialog)
      print(String(data: data, encoding: .utf8)!)
    } else {
      print("✅ Dialog appeared: \"\(dialog.title)\"")
      if !dialog.buttons.isEmpty {
        print("   Buttons: \(dialog.buttons.joined(separator: ", "))")
      }
      if dialog.textFields > 0 {
        print("   Text fields: \(dialog.textFields)")
      }
    }
  }
}
