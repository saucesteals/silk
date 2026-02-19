import ArgumentParser
import Foundation
import SilkKeyboard

struct PasteCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "paste",
    abstract: "Paste text via clipboard",
    discussion: """
      Examples:
        silk paste "Hello world"             # Paste text
        silk paste "secret" --clear          # Paste and clear clipboard
        echo "text" | silk paste             # Paste from stdin
        cat file.txt | silk paste            # Paste file contents
      """
  )

  @Argument(help: "Text to paste (reads from stdin if omitted)")
  var text: String?

  @Flag(help: "Clear clipboard after paste")
  var clear: Bool = false

  @Flag(help: "Output JSON")
  var json: Bool = false

  func run() async throws {
    let controller = KeyboardController()

    // Get text from argument or stdin
    let textToPaste: String
    if let providedText = text {
      textToPaste = providedText
    } else if isatty(fileno(stdin)) == 0 {
      // stdin is piped, read from it
      var input = ""
      while let line = readLine(strippingNewline: false) {
        input += line
      }
      // Trim trailing newline that shells typically add
      if input.hasSuffix("\n") {
        input = String(input.dropLast())
      }
      textToPaste = input
    } else {
      throw ValidationError("No text provided. Pass text as argument or pipe via stdin.")
    }

    guard !textToPaste.isEmpty else {
      throw ValidationError("No text provided")
    }

    let options = PasteOptions(text: textToPaste, clear: clear)
    let result = try await controller.paste(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      let clearStr = clear ? " (clipboard cleared)" : ""
      print("✅ Pasted \(textToPaste.count) characters in \(result.durationMs)ms\(clearStr)")
    }
  }
}
