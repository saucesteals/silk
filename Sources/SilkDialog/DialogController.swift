import AppKit
import ApplicationServices
import Foundation

/// Errors specific to dialog operations
public enum DialogError: LocalizedError {
  case noDialogFound
  case buttonNotFound(String, available: [String])
  case fieldNotFound(String)
  case fieldIndexOutOfRange(Int, count: Int)
  case timeout(TimeInterval)
  case accessibilityError(String)
  case actionFailed(String)

  public var errorDescription: String? {
    switch self {
    case .noDialogFound:
      return "No dialog found on screen"
    case .buttonNotFound(let name, let available):
      let availStr = available.isEmpty ? "" : " Available: \(available.joined(separator: ", "))"
      return "Button not found: \(name).\(availStr)"
    case .fieldNotFound(let label):
      return "Text field not found with label: \(label)"
    case .fieldIndexOutOfRange(let index, let count):
      return "Field index \(index) out of range (found \(count) field(s))"
    case .timeout(let seconds):
      return "Timed out after \(Int(seconds))s waiting for dialog"
    case .accessibilityError(let msg):
      return "Accessibility API error: \(msg)"
    case .actionFailed(let msg):
      return "Dialog action failed: \(msg)"
    }
  }
}

public final class DialogController: Sendable {

  public init() {}

  // MARK: - Public API

  /// Click button in system dialog
  public func click(_ options: DialogClickOptions) throws -> DialogResult {
    let start = DispatchTime.now()

    // Poll for dialog with button until timeout
    let deadline = Date().addingTimeInterval(options.timeout)

    while Date() < deadline {
      let dialogs = try collectDialogs()

      for (dialogElement, info) in dialogs {
        // Search for matching button
        let buttons = findButtons(in: dialogElement)
        for (buttonElement, buttonTitle) in buttons {
          if buttonTitle.lowercased() == options.buttonText.lowercased()
            || buttonTitle.lowercased().contains(options.buttonText.lowercased())
          {
            // Press the button
            let err = AXUIElementPerformAction(buttonElement, kAXPressAction as CFString)
            guard err == .success else {
              throw DialogError.actionFailed(
                "Failed to press button '\(buttonTitle)' (error: \(err.rawValue))")
            }

            return DialogResult(
              action: "click",
              dialogTitle: info.title,
              found: true,
              durationMs: elapsedMs(since: start)
            )
          }
        }
      }

      // Not found yet, wait a bit and retry
      usleep(200_000)  // 200ms
    }

    // Final attempt - collect what's available for error message
    let dialogs = try collectDialogs()
    if dialogs.isEmpty {
      throw DialogError.noDialogFound
    }

    // Dialog found but button not found
    let allButtons = dialogs.flatMap { findButtons(in: $0.0).map { $0.1 } }
    throw DialogError.buttonNotFound(options.buttonText, available: allButtons)
  }

  /// Type into dialog text field
  public func input(_ options: DialogInputOptions) throws -> DialogResult {
    let start = DispatchTime.now()

    let dialogs = try collectDialogs()

    guard let (dialogElement, info) = dialogs.first else {
      throw DialogError.noDialogFound
    }

    // Find text fields
    let textFields = findTextFields(in: dialogElement)

    guard !textFields.isEmpty else {
      throw DialogError.fieldNotFound(options.fieldLabel ?? "any")
    }

    let targetField: AXUIElement

    if let label = options.fieldLabel {
      // Find by label
      if let match = findFieldByLabel(label, in: dialogElement, fields: textFields) {
        targetField = match
      } else {
        throw DialogError.fieldNotFound(label)
      }
    } else if let index = options.fieldIndex {
      // Find by index
      guard index >= 0, index < textFields.count else {
        throw DialogError.fieldIndexOutOfRange(index, count: textFields.count)
      }
      targetField = textFields[index]
    } else {
      // Default: first field
      targetField = textFields[0]
    }

    // Focus the field
    AXUIElementSetAttributeValue(targetField, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    usleep(50_000)  // 50ms for focus

    // Set the value
    let err = AXUIElementSetAttributeValue(
      targetField, kAXValueAttribute as CFString, options.text as CFTypeRef)
    guard err == .success else {
      throw DialogError.actionFailed("Failed to set text field value (error: \(err.rawValue))")
    }

    // Submit if requested (press Enter)
    if options.submit {
      usleep(50_000)  // 50ms before submit
      pressEnter()
    }

    return DialogResult(
      action: "input",
      dialogTitle: info.title,
      found: true,
      durationMs: elapsedMs(since: start)
    )
  }

  /// List all visible dialogs
  public func listDialogs() throws -> [DialogInfo] {
    return try collectDialogs().map { $0.1 }
  }

  /// Wait for dialog to appear
  public func waitForDialog(
    titleContains: String? = nil,
    timeout: TimeInterval = 10.0
  ) throws -> DialogInfo {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      let dialogs = try collectDialogs()

      for (_, info) in dialogs {
        if let titleFilter = titleContains {
          if info.title.lowercased().contains(titleFilter.lowercased()) {
            return info
          }
        } else {
          // Any dialog matches
          return info
        }
      }

      usleep(250_000)  // 250ms poll interval
    }

    throw DialogError.timeout(timeout)
  }

  // MARK: - Private: Dialog Collection

  /// Collect all visible dialog elements with their info
  private func collectDialogs() throws -> [(AXUIElement, DialogInfo)] {
    var results: [(AXUIElement, DialogInfo)] = []

    let runningApps = NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular
    }

    for app in runningApps {
      let pid = app.processIdentifier
      let appElement = AXUIElementCreateApplication(pid)

      // Get all windows
      var windowsRef: CFTypeRef?
      let err = AXUIElementCopyAttributeValue(
        appElement, kAXWindowsAttribute as CFString, &windowsRef)
      guard err == .success, let windows = windowsRef as? [AXUIElement] else {
        continue
      }

      for window in windows {
        let role = getStringAttribute(window, attribute: kAXRoleAttribute)
        let subrole = getStringAttribute(window, attribute: kAXSubroleAttribute)

        // Check if this is a dialog
        let dialogType = classifyDialog(role: role, subrole: subrole, element: window)
        guard let type = dialogType else { continue }

        // Extract dialog info
        let title = getStringAttribute(window, attribute: kAXTitleAttribute) ?? ""
        let message = extractDialogMessage(window)
        let buttons = findButtons(in: window).map { $0.1 }
        let textFieldCount = findTextFields(in: window).count

        let info = DialogInfo(
          title: title,
          message: message,
          buttons: buttons,
          textFields: textFieldCount,
          type: type
        )

        results.append((window, info))
      }
    }

    return results
  }

  /// Classify a window element as a dialog type, or nil if not a dialog
  private func classifyDialog(role: String?, subrole: String?, element: AXUIElement) -> String? {
    // Direct dialog subroles
    if let subrole = subrole {
      switch subrole {
      case "AXDialog":
        return "alert"
      case "AXSheet", "AXSystemDialog":
        return "sheet"
      case "AXFloatingWindow":
        // Could be a panel-style dialog
        // Check if it has buttons to confirm
        let buttons = findButtons(in: element)
        if !buttons.isEmpty {
          return "panel"
        }
        return nil
      default:
        break
      }
    }

    // For standard windows, check if they look like dialogs
    // Require BOTH a confirm and dismiss button to avoid false positives
    // from regular windows that happen to have a "Delete" or similar button
    if role == "AXWindow" && subrole == "AXStandardWindow" {
      let buttons = findButtons(in: element)
      let buttonNames = Set(buttons.map { $0.1.lowercased() })
      let confirmButtons = [
        "ok", "save", "yes", "allow", "continue", "replace", "overwrite", "submit", "done",
      ]
      let dismissButtons = ["cancel", "no", "deny", "don't save", "close", "abort"]
      let hasConfirm = buttonNames.contains { name in
        confirmButtons.contains(where: { name == $0 })
      }
      let hasDismiss = buttonNames.contains { name in
        dismissButtons.contains(where: { name == $0 })
      }
      if hasConfirm && hasDismiss {
        return "alert"
      }
    }

    return nil
  }

  // MARK: - Private: Element Search

  /// Find all buttons in a dialog element (recursive)
  private func findButtons(in element: AXUIElement) -> [(AXUIElement, String)] {
    var results: [(AXUIElement, String)] = []
    findButtonsRecursive(in: element, results: &results, depth: 0)
    return results
  }

  private func findButtonsRecursive(
    in element: AXUIElement, results: inout [(AXUIElement, String)], depth: Int
  ) {
    guard depth < 10 else { return }  // Prevent infinite recursion

    let role = getStringAttribute(element, attribute: kAXRoleAttribute)

    if role == "AXButton" {
      if let title = getStringAttribute(element, attribute: kAXTitleAttribute), !title.isEmpty {
        results.append((element, title))
      }
    }

    // Recurse into children
    let children = getChildren(element)
    for child in children {
      findButtonsRecursive(in: child, results: &results, depth: depth + 1)
    }
  }

  /// Find all text fields in a dialog element (recursive)
  private func findTextFields(in element: AXUIElement) -> [AXUIElement] {
    var results: [AXUIElement] = []
    findTextFieldsRecursive(in: element, results: &results, depth: 0)
    return results
  }

  private func findTextFieldsRecursive(
    in element: AXUIElement, results: inout [AXUIElement], depth: Int
  ) {
    guard depth < 10 else { return }

    let role = getStringAttribute(element, attribute: kAXRoleAttribute)

    if role == "AXTextField" || role == "AXSecureTextField" || role == "AXTextArea" {
      results.append(element)
    }

    let children = getChildren(element)
    for child in children {
      findTextFieldsRecursive(in: child, results: &results, depth: depth + 1)
    }
  }

  /// Find a text field by its associated label
  private func findFieldByLabel(_ label: String, in element: AXUIElement, fields: [AXUIElement])
    -> AXUIElement?
  {
    let loweredLabel = label.lowercased()

    for field in fields {
      // Check description/title/placeholder of the field itself
      let fieldTitle = getStringAttribute(field, attribute: kAXTitleAttribute)
      let fieldDesc = getStringAttribute(field, attribute: kAXDescriptionAttribute)
      let fieldPlaceholder = getStringAttribute(field, attribute: "AXPlaceholderValue")

      if let t = fieldTitle, t.lowercased().contains(loweredLabel) { return field }
      if let d = fieldDesc, d.lowercased().contains(loweredLabel) { return field }
      if let p = fieldPlaceholder, p.lowercased().contains(loweredLabel) { return field }

      // Check label element (AXTitleUIElement)
      var titleElementRef: CFTypeRef?
      let err = AXUIElementCopyAttributeValue(
        field, "AXTitleUIElement" as CFString, &titleElementRef)
      if err == .success, let titleElement = titleElementRef {
        let labelText =
          getStringAttribute(titleElement as! AXUIElement, attribute: kAXValueAttribute)
          ?? getStringAttribute(titleElement as! AXUIElement, attribute: kAXTitleAttribute)
        if let lt = labelText, lt.lowercased().contains(loweredLabel) {
          return field
        }
      }
    }

    // Fallback: search all static text elements near the fields
    let staticTexts = findStaticTexts(in: element)
    for text in staticTexts {
      let value =
        getStringAttribute(text, attribute: kAXValueAttribute)
        ?? getStringAttribute(text, attribute: kAXTitleAttribute)
      guard let v = value, v.lowercased().contains(loweredLabel) else { continue }

      // Found a matching label - return the closest field
      // (This is a heuristic: just return the first field if there's only one,
      // or try to match by position proximity)
      if fields.count == 1 {
        return fields[0]
      }

      // Try position-based matching
      if let labelPos = getPosition(text) {
        var closest: AXUIElement?
        var closestDist = Double.infinity
        for field in fields {
          if let fieldPos = getPosition(field) {
            let dx = Double(fieldPos.x - labelPos.x)
            let dy = Double(fieldPos.y - labelPos.y)
            let dist = sqrt(dx * dx + dy * dy)
            if dist < closestDist {
              closestDist = dist
              closest = field
            }
          }
        }
        if let found = closest {
          return found
        }
      }
    }

    return nil
  }

  /// Find static text elements (used for label matching)
  private func findStaticTexts(in element: AXUIElement) -> [AXUIElement] {
    var results: [AXUIElement] = []
    findStaticTextsRecursive(in: element, results: &results, depth: 0)
    return results
  }

  private func findStaticTextsRecursive(
    in element: AXUIElement, results: inout [AXUIElement], depth: Int
  ) {
    guard depth < 10 else { return }

    let role = getStringAttribute(element, attribute: kAXRoleAttribute)
    if role == "AXStaticText" {
      results.append(element)
    }

    let children = getChildren(element)
    for child in children {
      findStaticTextsRecursive(in: child, results: &results, depth: depth + 1)
    }
  }

  /// Extract the message/body text from a dialog
  private func extractDialogMessage(_ element: AXUIElement) -> String? {
    let staticTexts = findStaticTexts(in: element)
    // Typically the message is the longest static text that's not a button label
    let texts = staticTexts.compactMap { el -> String? in
      return getStringAttribute(el, attribute: kAXValueAttribute)
        ?? getStringAttribute(el, attribute: kAXTitleAttribute)
    }.filter { !$0.isEmpty }

    // Return the longest text as the "message"
    return texts.max(by: { $0.count < $1.count })
  }

  // MARK: - Private: AX Helpers

  private func getStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else { return nil }
    return value as? String
  }

  private func getChildren(_ element: AXUIElement) -> [AXUIElement] {
    var childrenRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    guard err == .success, let children = childrenRef as? [AXUIElement] else {
      return []
    }
    return children
  }

  private func getPosition(_ element: AXUIElement) -> CGPoint? {
    var posRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
    guard err == .success, let axValue = posRef, CFGetTypeID(axValue) == AXValueGetTypeID() else {
      return nil
    }
    var point = CGPoint.zero
    AXValueGetValue(axValue as! AXValue, .cgPoint, &point)
    return point
  }

  /// Press the Enter/Return key
  private func pressEnter() {
    // Virtual key code for Return = 0x24
    if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true) {
      keyDown.post(tap: .cghidEventTap)
    }
    if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: false) {
      keyUp.post(tap: .cghidEventTap)
    }
  }

  private func elapsedMs(since start: DispatchTime) -> Int {
    let end = DispatchTime.now()
    let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
    return Int(nanos / 1_000_000)
  }
}
