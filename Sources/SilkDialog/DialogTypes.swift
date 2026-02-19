import CoreGraphics
import Foundation

/// Dialog button click options
public struct DialogClickOptions: Sendable {
  public let buttonText: String  // Button text (e.g., "OK", "Cancel")
  public let timeout: TimeInterval  // Wait timeout

  public init(buttonText: String, timeout: TimeInterval = 5.0) {
    self.buttonText = buttonText
    self.timeout = timeout
  }
}

/// Dialog input options
public struct DialogInputOptions: Sendable {
  public let fieldLabel: String?  // Field label/placeholder
  public let fieldIndex: Int?  // Field index (0-based)
  public let text: String  // Text to enter
  public let submit: Bool  // Press Enter after typing

  public init(
    fieldLabel: String? = nil,
    fieldIndex: Int? = nil,
    text: String,
    submit: Bool = false
  ) {
    self.fieldLabel = fieldLabel
    self.fieldIndex = fieldIndex
    self.text = text
    self.submit = submit
  }
}

/// Dialog result
public struct DialogResult: Sendable, Encodable {
  public let action: String
  public let dialogTitle: String?
  public let found: Bool
  public let durationMs: Int

  enum CodingKeys: String, CodingKey {
    case action
    case dialogTitle = "dialog_title"
    case found
    case durationMs = "duration_ms"
  }

  public init(
    action: String,
    dialogTitle: String?,
    found: Bool,
    durationMs: Int
  ) {
    self.action = action
    self.dialogTitle = dialogTitle
    self.found = found
    self.durationMs = durationMs
  }
}

/// Dialog info
public struct DialogInfo: Sendable, Encodable {
  public let title: String
  public let message: String?
  public let buttons: [String]
  public let textFields: Int
  public let type: String  // alert, sheet, panel

  enum CodingKeys: String, CodingKey {
    case title, message, buttons
    case textFields = "text_fields"
    case type
  }

  public init(
    title: String,
    message: String?,
    buttons: [String],
    textFields: Int,
    type: String
  ) {
    self.title = title
    self.message = message
    self.buttons = buttons
    self.textFields = textFields
    self.type = type
  }
}
