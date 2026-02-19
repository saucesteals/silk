import CoreGraphics
import Foundation

/// Keyboard modifier keys
public enum Modifier: String, Sendable, Codable, CaseIterable {
  case command = "cmd"
  case shift = "shift"
  case option = "opt"
  case control = "ctrl"
  case fn = "fn"

  /// Parse modifier from various string representations
  public static func from(_ string: String) -> Modifier? {
    let lower = string.lowercased()
    switch lower {
    case "cmd", "command", "⌘": return .command
    case "shift", "⇧": return .shift
    case "opt", "option", "alt", "⌥": return .option
    case "ctrl", "control", "^": return .control
    case "fn": return .fn
    default: return nil
    }
  }
}

/// Special keys (non-character)
public enum SpecialKey: String, Sendable, Codable {
  case enter = "enter"
  case `return` = "return"
  case tab = "tab"
  case space = "space"
  case delete = "delete"
  case backspace = "backspace"
  case escape = "escape"
  case up = "up"
  case down = "down"
  case left = "left"
  case right = "right"
  case home = "home"
  case end = "end"
  case pageUp = "pageup"
  case pageDown = "pagedown"
  case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
  case volumeUp = "volumeup"
  case volumeDown = "volumedown"
  case mute = "mute"
  case brightnessUp = "brightnessup"
  case brightnessDown = "brightnessdown"
  case playPause = "playpause"
}

/// Hotkey press options
public struct HotkeyOptions: Sendable {
  public let modifiers: [Modifier]
  public let key: String  // Character or special key name
  public let count: Int  // Number of times to press

  public init(modifiers: [Modifier], key: String, count: Int = 1) {
    self.modifiers = modifiers
    self.key = key
    self.count = count
  }
}

/// Special key press options
public struct PressOptions: Sendable {
  public let key: SpecialKey
  public let modifiers: [Modifier]
  public let count: Int

  public init(key: SpecialKey, modifiers: [Modifier] = [], count: Int = 1) {
    self.key = key
    self.modifiers = modifiers
    self.count = count
  }
}

/// Paste options
public struct PasteOptions: Sendable {
  public let text: String
  public let clear: Bool  // Clear clipboard after paste

  public init(text: String, clear: Bool = false) {
    self.text = text
    self.clear = clear
  }
}

/// Keyboard operation result
public struct KeyboardResult: Sendable, Encodable {
  public let action: String
  public let keys: [String]
  public let modifiers: [String]
  public let count: Int
  public let durationMs: Int

  enum CodingKeys: String, CodingKey {
    case action, keys, modifiers, count
    case durationMs = "duration_ms"
  }

  public init(
    action: String,
    keys: [String],
    modifiers: [String] = [],
    count: Int = 1,
    durationMs: Int
  ) {
    self.action = action
    self.keys = keys
    self.modifiers = modifiers
    self.count = count
    self.durationMs = durationMs
  }
}
