import ArgumentParser
import Foundation
import Silk
import SilkAccessibility
import SilkCore

struct TypeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "type",
    abstract: "Find and type into a UI element",
    discussion: """
      Examples:
        silk type "username" "user@example.com"
        silk type --role textField "Search" "hello world"
      """
  )

  @Argument(help: "Element text/label to search for")
  var selector: String?

  @Argument(help: "Text to type")
  var text: String

  @Option(name: .long, help: "Filter by accessibility role")
  var role: String?

  @Option(name: .long, help: "Target application name")
  var app: String?

  @Flag(name: .long, help: "Require exact text match (no fuzzy)")
  var exact: Bool = false

  @Flag(name: .long, help: "Use humanized movement for initial click")
  var humanize: Bool = false

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func validate() throws {
    if selector == nil && role == nil {
      throw ValidationError("Provide selector text or --role")
    }
  }

  func run() async throws {
    let query = ElementQuery(
      text: selector,
      role: role,
      application: app,
      fuzzyMatch: !exact,
      limit: 1
    )

    let result = AccessibilityQuery.find(query)

    guard let element = result.elements.first else {
      if !json {
        print("❌ No matching element found")
      }
      throw ExitCode.failure
    }

    let actions = ElementActions()
    try await actions.type(element, text: text, humanize: humanize)

    if !json {
      let title = element.title ?? "(untitled)"
      print("✅ Typed into \(element.role): \"\(title)\"")
    } else {
      printJSON(element)
    }
  }
}
