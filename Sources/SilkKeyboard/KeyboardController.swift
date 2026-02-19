import AppKit
import CoreGraphics
import Foundation
import SilkCore

public final class KeyboardController: Sendable {
  private let eventPoster: EventPoster

  public init(eventPoster: EventPoster = CGEventPoster()) {
    self.eventPoster = eventPoster
  }

  // MARK: - Public API

  /// Press hotkey combination (e.g., Cmd+C, Cmd+Shift+N)
  public func hotkey(_ options: HotkeyOptions) async throws -> KeyboardResult {
    let start = DispatchTime.now()

    let flags = Self.modifiersToFlags(options.modifiers)
    let keyCode = try Self.resolveKeyCode(for: options.key)

    for _ in 0..<options.count {
      try await pressKey(keyCode: keyCode, flags: flags)
    }

    let elapsed = Self.elapsedMs(since: start)

    return KeyboardResult(
      action: "hotkey",
      keys: [options.key],
      modifiers: options.modifiers.map(\.rawValue),
      count: options.count,
      durationMs: elapsed
    )
  }

  /// Press special key (enter, escape, arrows, etc.)
  public func press(_ options: PressOptions) async throws -> KeyboardResult {
    let start = DispatchTime.now()

    let flags = Self.modifiersToFlags(options.modifiers)
    let keyCode = Self.specialKeyCode(for: options.key)

    for _ in 0..<options.count {
      try await pressKey(keyCode: keyCode, flags: flags)
    }

    let elapsed = Self.elapsedMs(since: start)

    return KeyboardResult(
      action: "press",
      keys: [options.key.rawValue],
      modifiers: options.modifiers.map(\.rawValue),
      count: options.count,
      durationMs: elapsed
    )
  }

  /// Paste text via clipboard (set clipboard, then Cmd+V)
  public func paste(_ options: PasteOptions) async throws -> KeyboardResult {
    let start = DispatchTime.now()
    let pasteboard = NSPasteboard.general

    // Save current clipboard content by extracting raw data before clearing.
    // NSPasteboardItem refs become invalid after clearContents(), so we must
    // snapshot all type/data pairs into plain tuples first.
    let savedItemData: [[(NSPasteboard.PasteboardType, Data)]]?
    if !options.clear {
      savedItemData = pasteboard.pasteboardItems?.compactMap {
        item -> [(NSPasteboard.PasteboardType, Data)]? in
        let pairs: [(NSPasteboard.PasteboardType, Data)] = item.types.compactMap { type in
          guard let data = item.data(forType: type) else { return nil }
          return (type, data)
        }
        return pairs.isEmpty ? nil : pairs
      }
    } else {
      savedItemData = nil
    }

    // Set clipboard to new text
    pasteboard.clearContents()
    pasteboard.setString(options.text, forType: .string)

    // Small delay for clipboard to settle
    try await Task.sleep(for: .milliseconds(50))

    // Send Cmd+V
    let cmdFlag = CGEventFlags.maskCommand
    let vKeyCode: CGKeyCode = 9  // 'v' key
    try await pressKey(keyCode: vKeyCode, flags: cmdFlag)

    // Small delay to let paste complete
    try await Task.sleep(for: .milliseconds(100))

    // Restore clipboard if not clearing
    if !options.clear, let items = savedItemData {
      pasteboard.clearContents()
      for itemPairs in items {
        let newItem = NSPasteboardItem()
        for (type, data) in itemPairs {
          newItem.setData(data, forType: type)
        }
        pasteboard.writeObjects([newItem])
      }
    }

    // If clearing, clear clipboard
    if options.clear {
      pasteboard.clearContents()
    }

    let elapsed = Self.elapsedMs(since: start)

    return KeyboardResult(
      action: "paste",
      keys: ["v"],
      modifiers: ["cmd"],
      count: 1,
      durationMs: elapsed
    )
  }

  /// Type text character by character
  public func type(_ text: String, delayMs: Int = 0) async throws -> KeyboardResult {
    let start = DispatchTime.now()

    for char in text {
      let (keyCode, flags) = try Self.resolveCharacter(char)
      try await pressKey(keyCode: keyCode, flags: flags)

      if delayMs > 0 {
        try await Task.sleep(for: .milliseconds(delayMs))
      }
    }

    let elapsed = Self.elapsedMs(since: start)

    return KeyboardResult(
      action: "type",
      keys: [text],
      modifiers: [],
      count: text.count,
      durationMs: elapsed
    )
  }

  // MARK: - Private Helpers

  /// Press and release a key with optional modifier flags
  private func pressKey(keyCode: CGKeyCode, flags: CGEventFlags) async throws {
    // Key down
    try eventPoster.postKeyPress(keyCode: keyCode, down: true, flags: flags)

    // Small realistic delay between down and up
    try await Task.sleep(for: .milliseconds(Int.random(in: 20...60)))

    // Key up
    try eventPoster.postKeyPress(keyCode: keyCode, down: false, flags: flags)

    // Small delay between repeated presses
    try await Task.sleep(for: .milliseconds(Int.random(in: 30...70)))
  }

  /// Convert modifier array to CGEventFlags
  static func modifiersToFlags(_ modifiers: [Modifier]) -> CGEventFlags {
    var flags = CGEventFlags()
    for mod in modifiers {
      switch mod {
      case .command: flags.insert(.maskCommand)
      case .shift: flags.insert(.maskShift)
      case .option: flags.insert(.maskAlternate)
      case .control: flags.insert(.maskControl)
      case .fn: flags.insert(.maskSecondaryFn)
      }
    }
    return flags
  }

  /// Resolve a key string to a keycode - supports single chars and special key names
  static func resolveKeyCode(for key: String) throws -> CGKeyCode {
    let lower = key.lowercased()

    // Check if it's a special key name first
    if let specialKey = SpecialKey(rawValue: lower) {
      return specialKeyCode(for: specialKey)
    }

    // Single character
    if key.count == 1, let char = key.lowercased().first {
      if let code = charToKeyCode[char] {
        return code
      }
    }

    throw SilkError.systemAPIError("Unknown key: \(key)")
  }

  /// Resolve a character to keycode + required modifier flags (e.g., shift for uppercase)
  static func resolveCharacter(_ char: Character) throws -> (CGKeyCode, CGEventFlags) {
    guard let (keyCode, needsShift) = Self.keyMapping(for: char) else {
      throw SilkError.systemAPIError("Unmappable character: \(char)")
    }

    let flags: CGEventFlags = needsShift ? .maskShift : CGEventFlags()
    return (keyCode, flags)
  }

  /// Map SpecialKey enum to CGKeyCode
  static func specialKeyCode(for key: SpecialKey) -> CGKeyCode {
    switch key {
    case .enter, .return: return 36
    case .tab: return 48
    case .space: return 49
    case .delete,
      .backspace:
      return 51
    case .escape: return 53
    case .up: return 126
    case .down: return 125
    case .left: return 123
    case .right: return 124
    case .home: return 115
    case .end: return 119
    case .pageUp: return 116
    case .pageDown: return 121
    case .f1: return 122
    case .f2: return 120
    case .f3: return 99
    case .f4: return 118
    case .f5: return 96
    case .f6: return 97
    case .f7: return 98
    case .f8: return 100
    case .f9: return 101
    case .f10: return 109
    case .f11: return 103
    case .f12: return 111
    case .volumeUp: return 72
    case .volumeDown: return 73
    case .mute: return 74
    case .brightnessUp: return 144
    case .brightnessDown: return 145
    case .playPause: return 164  // NX keycode for media
    }
  }

  /// Elapsed milliseconds since a given time
  private static func elapsedMs(since start: DispatchTime) -> Int {
    let end = DispatchTime.now()
    let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
    return Int(nanos / 1_000_000)
  }

  // MARK: - Public Key Mapping API

  /// Map a character to its keycode and whether shift is needed.
  /// Returns (keyCode, needsShift) for the character, or nil if unmappable.
  ///
  /// This is the single source of truth for character-to-keycode mapping,
  /// used by both KeyboardController and ElementActions.
  public static func keyMapping(for char: Character) -> (CGKeyCode, Bool)? {
    let lower = char.lowercased().first ?? char

    // Check base character mapping
    if let keyCode = charToKeyCode[lower] {
      // Uppercase letters need shift
      if char.isUppercase && char.isLetter {
        return (keyCode, true)
      }
      return (keyCode, false)
    }

    // Check shifted symbols
    if let (keyCode, _) = shiftedCharToKeyCode[char] {
      return (keyCode, true)
    }

    return nil
  }

  // MARK: - Keycode Maps

  /// Character to macOS virtual keycode mapping (lowercase/base characters)
  private static let charToKeyCode: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
    "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
    "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
    ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
    " ": 49, "`": 50, "\t": 48, "\n": 36,
  ]

  /// Shifted/symbol characters that require shift + a base key
  private static let shiftedCharToKeyCode: [Character: (CGKeyCode, CGEventFlags)] = [
    "!": (18, .maskShift),  // shift+1
    "@": (19, .maskShift),  // shift+2
    "#": (20, .maskShift),  // shift+3
    "$": (21, .maskShift),  // shift+4
    "%": (23, .maskShift),  // shift+5
    "^": (22, .maskShift),  // shift+6
    "&": (26, .maskShift),  // shift+7
    "*": (28, .maskShift),  // shift+8
    "(": (25, .maskShift),  // shift+9
    ")": (29, .maskShift),  // shift+0
    "_": (27, .maskShift),  // shift+-
    "+": (24, .maskShift),  // shift+=
    "{": (33, .maskShift),  // shift+[
    "}": (30, .maskShift),  // shift+]
    "|": (42, .maskShift),  // shift+\
    ":": (41, .maskShift),  // shift+;
    "\"": (39, .maskShift),  // shift+'
    "<": (43, .maskShift),  // shift+,
    ">": (47, .maskShift),  // shift+.
    "?": (44, .maskShift),  // shift+/
    "~": (50, .maskShift),  // shift+`
  ]
}
