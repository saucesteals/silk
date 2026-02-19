import ArgumentParser
import Foundation
import SilkClipboard

struct ClipboardCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clipboard",
    abstract: "Clipboard operations",
    discussion: """
      Read, write, inspect, and clear the system clipboard.

      Examples:
        silk clipboard read
        silk clipboard write "Hello world"
        silk clipboard types
        silk clipboard clear
      """,
    subcommands: [
      ClipboardReadCommand.self,
      ClipboardWriteCommand.self,
      ClipboardTypesCommand.self,
      ClipboardClearCommand.self,
    ]
  )
}

// MARK: - Read

struct ClipboardReadCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "read",
    abstract: "Read clipboard contents",
    discussion: """
      Examples:
        silk clipboard read                  # Read text
        silk clipboard read --type image     # Read image (base64)
        silk clipboard read --type url       # Read URL
        silk clipboard read --json           # JSON output
      """
  )

  @Option(help: "Content type (text, image, url, fileURL, rtf, html)")
  var type: String = "text"

  @Flag(help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    guard let clipboardType = ClipboardType(rawValue: type) else {
      throw ValidationError(
        "Invalid type: \(type). Valid types: text, image, url, fileURL, rtf, html")
    }

    let controller = ClipboardController()
    let options = ClipboardReadOptions(type: clipboardType)
    let result = try controller.read(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      print(result.content)
    }
  }
}

// MARK: - Write

struct ClipboardWriteCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "write",
    abstract: "Write to clipboard",
    discussion: """
      Examples:
        silk clipboard write "Hello world"           # Write text
        echo "test" | silk clipboard write            # Write from stdin
        silk clipboard write --file /path/to/file.txt # Write file contents
        silk clipboard write --image /path/to/img.png # Write image
        silk clipboard write --url https://example.com # Write URL
      """
  )

  @Argument(help: "Content to write (or read from stdin if omitted)")
  var content: String?

  @Option(help: "Read content from file")
  var file: String?

  @Option(help: "Write image from file path")
  var image: String?

  @Option(help: "Write URL")
  var url: String?

  @Flag(help: "Don't clear existing clipboard before writing")
  var append: Bool = false

  @Flag(help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    let controller = ClipboardController()

    // Determine content to write
    let clipboardContent: ClipboardContent

    if let imagePath = image {
      let expandedPath = (imagePath as NSString).expandingTildeInPath
      let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
      clipboardContent = .image(data)
    } else if let urlString = url {
      clipboardContent = .url(urlString)
    } else if let filePath = file {
      let expandedPath = (filePath as NSString).expandingTildeInPath
      let text = try String(contentsOfFile: expandedPath, encoding: .utf8)
      clipboardContent = .text(text)
    } else if let text = content {
      clipboardContent = .text(text)
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
      guard !input.isEmpty else {
        throw ValidationError("No content provided via stdin")
      }
      clipboardContent = .text(input)
    } else {
      throw ValidationError(
        "No content provided. Pass text as argument, use --file, --image, --url, or pipe via stdin."
      )
    }

    let options = ClipboardWriteOptions(content: clipboardContent, clear: !append)
    let result = try controller.write(options)

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      print(String(data: data, encoding: .utf8)!)
    } else {
      print("✅ Wrote \(result.size) bytes of \(result.type) to clipboard in \(result.durationMs)ms")
    }
  }
}

// MARK: - Types

struct ClipboardTypesCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "types",
    abstract: "List available clipboard content types",
    discussion: """
      Examples:
        silk clipboard types
        silk clipboard types --json
      """
  )

  @Flag(help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    let controller = ClipboardController()
    let types = controller.availableTypes()

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let typeStrings = types.map { $0.rawValue }
      let data = try encoder.encode(typeStrings)
      print(String(data: data, encoding: .utf8)!)
    } else {
      if types.isEmpty {
        print("Clipboard is empty — no types available")
      } else {
        print("Available clipboard types:")
        for type in types {
          print("  • \(type.rawValue)")
        }
      }
    }
  }
}

// MARK: - Clear

struct ClipboardClearCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clear",
    abstract: "Clear clipboard contents"
  )

  func run() throws {
    let controller = ClipboardController()
    controller.clear()
    print("✅ Clipboard cleared")
  }
}
