import ArgumentParser
import Foundation
import SilkKeyboard

struct KeyCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "key",
    abstract: "Press keyboard shortcuts and special keys",
    discussion: """
      Examples:
        silk key cmd c                    # Copy
        silk key cmd shift n              # New window
        silk key enter                    # Enter
        silk key down --count 5           # Arrow down 5x
        silk key shift tab                # Shift+Tab
        silk key f11                      # Function key

      Modifiers (positional):
        cmd, command, ⌘
        shift, ⇧
        opt, option, alt, ⌥
        ctrl, control, ^
        fn

      Special keys:
        enter, return, tab, space, delete, backspace, escape
        up, down, left, right, home, end, pageup, pagedown
        f1-f12, volumeup, volumedown, mute
      """
  )

  @Argument(help: "Modifiers and key (e.g., cmd c, enter, shift tab)")
  var keys: [String]

  @Option(help: "Number of times to press")
  var count: Int = 1

  @Flag(help: "Output JSON")
  var json: Bool = false

  func validate() throws {
    guard !keys.isEmpty else {
      throw ValidationError("Need at least one key (e.g., enter) or modifier+key (e.g., cmd c)")
    }
    guard count > 0 else {
      throw ValidationError("Count must be positive")
    }
  }

  func run() async throws {
    let controller = KeyboardController()

    // Separate modifiers from the final key
    var modifiers: [Modifier] = []
    var finalKey: String?

    for key in keys {
      if let mod = Modifier.from(key) {
        modifiers.append(mod)
      } else {
        finalKey = key
        break
      }
    }

    guard let key = finalKey else {
      throw ValidationError("No key specified. Example: silk key cmd c")
    }

    // Check if it's a special key or regular hotkey
    if let specialKey = SpecialKey(rawValue: key.lowercased()) {
      // It's a special key - use press
      let options = PressOptions(
        key: specialKey,
        modifiers: modifiers,
        count: count
      )
      let result = try await controller.press(options)

      if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
      } else {
        let modStr = result.modifiers.isEmpty ? "" : result.modifiers.joined(separator: "+") + "+"
        let countStr = result.count > 1 ? " (\(result.count)x)" : ""
        print("✅ Pressed \(modStr)\(result.keys[0])\(countStr) in \(result.durationMs)ms")
      }
    } else if !modifiers.isEmpty {
      // Regular hotkey with modifiers
      let options = HotkeyOptions(
        modifiers: modifiers,
        key: key,
        count: count
      )
      let result = try await controller.hotkey(options)

      if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
      } else {
        let modStr = result.modifiers.joined(separator: "+")
        let keyStr = result.keys.joined(separator: "+")
        let combo = modStr.isEmpty ? keyStr : "\(modStr)+\(keyStr)"
        let countStr = result.count > 1 ? " (\(result.count)x)" : ""
        print("✅ Pressed \(combo)\(countStr) in \(result.durationMs)ms")
      }
    } else {
      // Single character without modifiers - still use hotkey with empty modifiers
      let options = HotkeyOptions(
        modifiers: [],
        key: key,
        count: count
      )
      let result = try await controller.hotkey(options)

      if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
      } else {
        let countStr = result.count > 1 ? " (\(result.count)x)" : ""
        print("✅ Pressed \(result.keys[0])\(countStr) in \(result.durationMs)ms")
      }
    }
  }
}
