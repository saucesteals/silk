import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - AX Attribute Helpers

/// Get a string attribute from an AXUIElement.
///
/// Replaces the per-controller `axStringAttribute`, `getStringAttribute`, and `getTitle` helpers
/// that were duplicated across DragController, DialogController, WindowController, and MenuController.
public func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
  var value: AnyObject?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success else { return nil }
  return value as? String
}

/// Get the children of an AXUIElement.
///
/// Replaces `getChildren()` duplicated in DragController, MenuController, and DialogController.
public func axChildren(_ element: AXUIElement) -> [AXUIElement] {
  var childrenRef: AnyObject?
  let result = AXUIElementCopyAttributeValue(
    element, kAXChildrenAttribute as CFString, &childrenRef)
  guard result == .success, let children = childrenRef as? [AXUIElement] else {
    return []
  }
  return children
}

/// Get the position (origin) of an AXUIElement.
///
/// Replaces `getPosition()` in DialogController and similar inline patterns.
public func axPosition(_ element: AXUIElement) -> CGPoint? {
  var posRef: AnyObject?
  let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
  guard result == .success, let axValue = posRef, CFGetTypeID(axValue) == AXValueGetTypeID() else {
    return nil
  }
  var point = CGPoint.zero
  AXValueGetValue(axValue as! AXValue, .cgPoint, &point)
  return point
}

/// Get the size of an AXUIElement.
public func axSize(_ element: AXUIElement) -> CGSize? {
  var sizeRef: AnyObject?
  let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
  guard result == .success, let axValue = sizeRef, CFGetTypeID(axValue) == AXValueGetTypeID() else {
    return nil
  }
  var size = CGSize.zero
  AXValueGetValue(axValue as! AXValue, .cgSize, &size)
  return size
}

/// Get the center point of an AXUIElement (position + size/2).
///
/// Replaces `elementCenter()` in DragController and `centerPoint(of:)` in ScrollController.
public func axElementCenter(_ element: AXUIElement) -> CGPoint? {
  guard let position = axPosition(element),
    let size = axSize(element)
  else { return nil }
  return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
}

/// Get the frame (position + size) of an AXUIElement.
public func axFrame(_ element: AXUIElement) -> CGRect? {
  guard let position = axPosition(element),
    let size = axSize(element)
  else { return nil }
  return CGRect(origin: position, size: size)
}

/// Get an AXValue attribute (position or size) from an AXUIElement.
///
/// Replaces `getAXValue()` in WindowController.
public func axGetValue(_ element: AXUIElement, attribute: String) -> AXValue? {
  var value: AnyObject?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success, let v = value, CFGetTypeID(v) == AXValueGetTypeID() else {
    return nil
  }
  return (v as! AXValue)
}

// MARK: - Element Search

/// Check if an element's title, description, or value contains the given name (case-insensitive).
///
/// Replaces `elementMatchesName()` in ScrollController and inline checks in DragController.
public func axElementMatchesName(_ element: AXUIElement, _ name: String) -> Bool {
  let lowered = name.lowercased()

  if let title = axStringAttribute(element, kAXTitleAttribute as String),
    title.lowercased().contains(lowered)
  {
    return true
  }

  if let desc = axStringAttribute(element, kAXDescriptionAttribute as String),
    desc.lowercased().contains(lowered)
  {
    return true
  }

  if let value = axStringAttribute(element, kAXValueAttribute as String),
    value.lowercased().contains(lowered)
  {
    return true
  }

  return false
}

/// Recursively search for an element matching a name and return its center point.
///
/// Replaces `searchElement(named:in:...)` in DragController and `findElementCenter(in:matching:...)`
/// in ScrollController.
///
/// - Parameters:
///   - name: Text to search for (case-insensitive, partial match)
///   - element: Root element to search within
///   - maxDepth: Maximum recursion depth (default 10)
///   - deadline: Absolute time deadline to abort search (default: 5s from now)
/// - Returns: Center point of the matching element, or nil
public func axSearchElementCenter(
  named name: String,
  in element: AXUIElement,
  maxDepth: Int = 10,
  deadline: CFAbsoluteTime = CFAbsoluteTimeGetCurrent() + 5.0
) -> CGPoint? {
  return _axSearchElementCenter(
    named: name, in: element, depth: 0, maxDepth: maxDepth, deadline: deadline)
}

private func _axSearchElementCenter(
  named name: String,
  in element: AXUIElement,
  depth: Int,
  maxDepth: Int,
  deadline: CFAbsoluteTime
) -> CGPoint? {
  guard depth < maxDepth, CFAbsoluteTimeGetCurrent() < deadline else { return nil }

  if axElementMatchesName(element, name) {
    return axElementCenter(element)
  }

  for child in axChildren(element) {
    if let point = _axSearchElementCenter(
      named: name, in: child, depth: depth + 1, maxDepth: maxDepth, deadline: deadline)
    {
      return point
    }
  }

  return nil
}

// MARK: - App Resolution

/// Find the center of a named UI element across running applications.
///
/// Replaces `findElementCenter(named:app:)` in DragController and `resolveElementCenter(name:app:)`
/// in ScrollController.
///
/// - Parameters:
///   - name: Element text to search for
///   - app: Optional app name filter (case-insensitive)
///   - maxDepth: Maximum AX tree depth to search
///   - timeout: Timeout in seconds
/// - Returns: Center point of the matching element, or nil
public func axFindElementCenter(
  named name: String,
  app: String? = nil,
  maxDepth: Int = 10,
  timeout: TimeInterval = 5.0
) -> CGPoint? {
  let runningApps: [NSRunningApplication]
  if let appName = app {
    runningApps = NSWorkspace.shared.runningApplications.filter {
      $0.localizedName?.lowercased() == appName.lowercased()
    }
  } else {
    runningApps = NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular
    }
  }

  let deadline = CFAbsoluteTimeGetCurrent() + timeout

  for runningApp in runningApps {
    if CFAbsoluteTimeGetCurrent() > deadline { break }
    let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
    if let point = axSearchElementCenter(
      named: name, in: appElement, maxDepth: maxDepth, deadline: deadline)
    {
      return point
    }
  }

  return nil
}

/// Find a running application by name (case-insensitive exact match).
///
/// Replaces `findRunningApp(named:)` in WindowController and `resolveApp()` in MenuController.
public func axFindRunningApp(named name: String) -> NSRunningApplication? {
  let lowered = name.lowercased()
  return NSWorkspace.shared.runningApplications.first {
    $0.localizedName?.lowercased() == lowered
  }
}

// MARK: - Recursive Element Finders

/// Recursively find all elements matching a role within an AX tree.
///
/// Replaces `findButtons(in:)`, `findTextFields(in:)`, `findStaticTexts(in:)` patterns
/// in DialogController.
///
/// - Parameters:
///   - role: AX role to match (e.g. "AXButton", "AXTextField", "AXStaticText")
///   - element: Root element
///   - maxDepth: Maximum depth (default 10)
/// - Returns: Array of matching elements
public func axFindElements(withRole role: String, in element: AXUIElement, maxDepth: Int = 10)
  -> [AXUIElement]
{
  var results: [AXUIElement] = []
  _axFindElements(withRole: role, in: element, results: &results, depth: 0, maxDepth: maxDepth)
  return results
}

/// Find elements matching any of the given roles.
public func axFindElements(
  withRoles roles: Set<String>, in element: AXUIElement, maxDepth: Int = 10
) -> [AXUIElement] {
  var results: [AXUIElement] = []
  _axFindElements(withRoles: roles, in: element, results: &results, depth: 0, maxDepth: maxDepth)
  return results
}

private func _axFindElements(
  withRole role: String, in element: AXUIElement, results: inout [AXUIElement], depth: Int,
  maxDepth: Int
) {
  guard depth < maxDepth else { return }
  if axStringAttribute(element, kAXRoleAttribute as String) == role {
    results.append(element)
  }
  for child in axChildren(element) {
    _axFindElements(
      withRole: role, in: child, results: &results, depth: depth + 1, maxDepth: maxDepth)
  }
}

private func _axFindElements(
  withRoles roles: Set<String>, in element: AXUIElement, results: inout [AXUIElement], depth: Int,
  maxDepth: Int
) {
  guard depth < maxDepth else { return }
  if let r = axStringAttribute(element, kAXRoleAttribute as String), roles.contains(r) {
    results.append(element)
  }
  for child in axChildren(element) {
    _axFindElements(
      withRoles: roles, in: child, results: &results, depth: depth + 1, maxDepth: maxDepth)
  }
}
