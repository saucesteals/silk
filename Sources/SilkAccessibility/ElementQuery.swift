// ElementQuery.swift - Search criteria for finding UI elements

import Foundation

/// Criteria for searching the accessibility tree.
public struct ElementQuery: Sendable {
  /// Text to match against title, description, or value
  public let text: String?
  /// Role to filter by (e.g. "AXButton", "AXTextField"). Case-insensitive, "button" → "AXButton".
  public let role: String?
  /// Application name (e.g. "Chrome", "Safari")
  public let application: String?
  /// Allow approximate/substring matching for text
  public let fuzzyMatch: Bool
  /// Maximum number of results to return (0 = unlimited)
  public let limit: Int
  /// Maximum tree depth to search
  public let maxDepth: Int

  // MARK: - Phase 1 Precision Attributes

  /// Filter by accessibility identifier (like DOM id)
  public let identifier: String?
  /// Filter by sibling position (0-based index among parent's children)
  public let siblingIndex: Int?
  /// Filter by parent element role
  public let parentRole: String?
  /// Minimum width in pixels
  public let minWidth: CGFloat?
  /// Maximum width in pixels
  public let maxWidth: CGFloat?
  /// Minimum height in pixels
  public let minHeight: CGFloat?
  /// Maximum height in pixels
  public let maxHeight: CGFloat?

  public init(
    text: String? = nil,
    role: String? = nil,
    application: String? = nil,
    fuzzyMatch: Bool = true,
    limit: Int = 10,
    maxDepth: Int = 100,
    identifier: String? = nil,
    siblingIndex: Int? = nil,
    parentRole: String? = nil,
    minWidth: CGFloat? = nil,
    maxWidth: CGFloat? = nil,
    minHeight: CGFloat? = nil,
    maxHeight: CGFloat? = nil
  ) {
    self.text = text
    self.role = Self.normalizeRole(role)
    self.application = application
    self.fuzzyMatch = fuzzyMatch
    self.limit = limit
    self.maxDepth = maxDepth
    self.identifier = identifier
    self.siblingIndex = siblingIndex
    self.parentRole = Self.normalizeRole(parentRole)
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.minHeight = minHeight
    self.maxHeight = maxHeight
  }

  /// Normalize role name: "button" → "AXButton", "AXButton" → "AXButton"
  private static func normalizeRole(_ role: String?) -> String? {
    guard let r = role, !r.isEmpty else { return nil }
    if r.hasPrefix("AX") { return r }
    // Capitalize first letter
    return "AX\(r.prefix(1).uppercased())\(r.dropFirst())"
  }
}

/// Result of a search operation, includes timing info.
public struct SearchResult: Sendable, Encodable {
  public let elements: [Element]
  /// How long the search took in milliseconds
  public let durationMs: Int
  /// How many elements were visited during search
  public let searchedCount: Int

  enum CodingKeys: String, CodingKey {
    case elements
    case durationMs = "duration_ms"
    case searchedCount = "searched_count"
  }
}

// MARK: - Fuzzy Matching

/// Simple fuzzy text matching: checks if all characters of the needle appear in order in the haystack.
/// Also supports substring containment for non-fuzzy mode.
func textMatches(_ haystack: String, _ needle: String, fuzzy: Bool) -> Bool {
  let h = haystack.lowercased()
  let n = needle.lowercased()

  if h == n { return true }
  if h.contains(n) { return true }

  if fuzzy {
    // Subsequence match: all chars of needle appear in order
    var hIdx = h.startIndex
    for char in n {
      guard let found = h[hIdx...].firstIndex(of: char) else { return false }
      hIdx = h.index(after: found)
    }
    return true
  }

  return false
}

/// Check if an element matches the query criteria.
func elementMatchesQuery(_ element: Element, _ query: ElementQuery) -> Bool {
  // Role filter
  if let role = query.role, element.role != role { return false }

  // Text filter — match against title, description, or value
  if let text = query.text {
    let candidates = [element.title, element.accessibilityDescription, element.value]
    let matched = candidates.contains { candidate in
      guard let c = candidate else { return false }
      return textMatches(c, text, fuzzy: query.fuzzyMatch)
    }
    if !matched { return false }
  }

  // MARK: Phase 1 Precision Filters

  // Identifier filter
  if let queryId = query.identifier {
    guard let elemId = element.identifier, elemId == queryId else { return false }
  }

  // Sibling index filter
  if let querySibIdx = query.siblingIndex {
    guard let elemSibIdx = element.siblingIndex, elemSibIdx == querySibIdx else { return false }
  }

  // Parent role filter
  if let queryParentRole = query.parentRole {
    guard let elemParentRole = element.parentRole, elemParentRole == queryParentRole else {
      return false
    }
  }

  // Size filters
  if let minW = query.minWidth, element.size.width < minW { return false }
  if let maxW = query.maxWidth, element.size.width > maxW { return false }
  if let minH = query.minHeight, element.size.height < minH { return false }
  if let maxH = query.maxHeight, element.size.height > maxH { return false }

  return true
}
