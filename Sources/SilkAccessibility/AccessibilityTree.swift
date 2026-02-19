// AccessibilityTree.swift - Recursive AXUIElement tree traversal
// Uses batch attribute queries for performance.

import AppKit
import ApplicationServices

/// Provides tree traversal over the macOS accessibility hierarchy.
/// Entry points: system-wide element, per-app element, or arbitrary subtree.
public enum AccessibilityTree {

  /// Check if the process is trusted for accessibility access.
  /// If not trusted, macOS will show a prompt (if `prompt` is true).
  public static func isTrusted(prompt: Bool = false) -> Bool {
    let key = "AXTrustedCheckOptionPrompt" as CFString
    let options = [key: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// Get the AXUIElement for an application by name.
  /// Uses NSWorkspace to find the running app's PID.
  public static func applicationElement(named name: String) -> AXUIElement? {
    guard
      let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame
      })
    else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
  }

  /// Get AXUIElements for all running applications.
  public static func allApplicationElements() -> [(name: String, element: AXUIElement)] {
    NSWorkspace.shared.runningApplications.compactMap { app in
      guard let name = app.localizedName, app.activationPolicy == .regular else { return nil }
      return (name, AXUIElementCreateApplication(app.processIdentifier))
    }
  }

  /// System-wide element — can query focused element, etc.
  public static var systemWide: AXUIElement {
    AXUIElementCreateSystemWide()
  }

  // MARK: - Tree Traversal

  /// Recursively traverse the accessibility tree, calling `visitor` for each element.
  /// The visitor receives the element and returns `true` to continue into children.
  /// Uses visited node tracking to handle circular references gracefully.
  ///
  /// **Cycle Detection:** We use `CFHash(AXUIElement)` to detect already-visited nodes.
  /// CFHash is not guaranteed unique — two distinct AXUIElements could theoretically
  /// produce the same hash, causing us to skip a legitimate node. In practice this is
  /// acceptable: (1) AXUIElement hashes are derived from PID + element token, making
  /// collisions extremely rare in a single app tree, (2) the consequence of a collision
  /// is merely a skipped subtree (safe degradation, not corruption), and (3) using
  /// `Unmanaged.passUnretained(_:).toOpaque()` as an alternative would track CFType
  /// wrapper identity rather than logical element identity, which is worse — the same
  /// logical element can have multiple CFType wrapper instances, defeating cycle detection.
  ///
  /// - Parameters:
  ///   - root: Starting AXUIElement
  ///   - maxDepth: Maximum recursion depth (default 100, safety fallback)
  ///   - path: Current hierarchy path (for building Element.path)
  ///   - visited: Set of visited element hashes (internal, leave nil)
  ///   - visitor: Called for each element. Return `true` to recurse into children.
  /// - Returns: Number of elements visited
  @discardableResult
  public static func traverse(
    _ root: AXUIElement,
    maxDepth: Int = 100,
    path: [String] = [],
    depth: Int = 0,
    visited: inout Set<UInt>,
    visitor: (Element) -> Bool
  ) -> Int {
    guard depth <= maxDepth else { return 0 }

    // Check if we've already visited this element (handles circular references)
    let hash = CFHash(root)
    guard !visited.contains(hash) else { return 0 }
    visited.insert(hash)

    var count = 0

    // Build element from AX node
    guard let element = buildElement(from: root, path: path, depth: depth) else { return 0 }
    count += 1

    let shouldRecurse = visitor(element)
    guard shouldRecurse, depth < maxDepth else { return count }

    // Get children
    guard let children: [AXUIElement] = axAttribute(root, kAXChildrenAttribute as String) else {
      return count
    }

    // Traverse children with sibling index
    for (index, child) in children.enumerated() {
      count += traverseChild(
        child,
        maxDepth: maxDepth,
        path: element.path,
        depth: depth + 1,
        siblingIndex: index,
        visited: &visited,
        visitor: visitor
      )
    }

    return count
  }

  /// Internal helper for traversing a child with known sibling index
  private static func traverseChild(
    _ root: AXUIElement,
    maxDepth: Int,
    path: [String],
    depth: Int,
    siblingIndex: Int,
    visited: inout Set<UInt>,
    visitor: (Element) -> Bool
  ) -> Int {
    guard depth <= maxDepth else { return 0 }

    // Check if we've already visited this element (handles circular references)
    let hash = CFHash(root)
    guard !visited.contains(hash) else { return 0 }
    visited.insert(hash)

    var count = 0

    // Build element with sibling index
    guard
      let element = buildElement(from: root, path: path, depth: depth, siblingIndex: siblingIndex)
    else {
      return 0
    }
    count += 1

    let shouldRecurse = visitor(element)
    guard shouldRecurse, depth < maxDepth else { return count }

    // Get children
    guard let children: [AXUIElement] = axAttribute(root, kAXChildrenAttribute as String) else {
      return count
    }

    for (index, child) in children.enumerated() {
      count += traverseChild(
        child,
        maxDepth: maxDepth,
        path: element.path,
        depth: depth + 1,
        siblingIndex: index,
        visited: &visited,
        visitor: visitor
      )
    }

    return count
  }

  /// Collect all elements from a subtree into an array.
  /// Convenience wrapper around `traverse`.
  public static func collectElements(
    from root: AXUIElement,
    maxDepth: Int = 100,
    filter: ((Element) -> Bool)? = nil
  ) -> [Element] {
    var results: [Element] = []
    var visited = Set<UInt>()
    traverse(root, maxDepth: maxDepth, visited: &visited) { element in
      if let filter = filter {
        if filter(element) { results.append(element) }
      } else {
        results.append(element)
      }
      return true  // always recurse into children
    }
    return results
  }

  /// Get the element at a specific screen coordinate using the system-wide hit test.
  /// This is the fastest way to identify what's under a point.
  public static func elementAtPosition(x: Float, y: Float) -> Element? {
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(systemWide, x, y, &element)
    guard result == .success, let ax = element else { return nil }
    return buildElement(from: ax, path: [], depth: 0)
  }

  /// Get the focused element across the system.
  public static func focusedElement() -> Element? {
    guard let ax: AXUIElement = axAttribute(systemWide, kAXFocusedUIElementAttribute as String)
    else {
      return nil
    }
    return buildElement(from: ax, path: [], depth: 0)
  }

  /// Get windows for an application element.
  public static func windows(of appElement: AXUIElement) -> [AXUIElement] {
    axAttribute(appElement, kAXWindowsAttribute as String) ?? []
  }
}
