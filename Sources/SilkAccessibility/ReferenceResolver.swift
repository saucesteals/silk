// ReferenceResolver.swift - Resolve stable references back to elements

import CoreGraphics
import Foundation

/// Resolves element references (IDs) back to actual elements
public enum ReferenceResolver {

  /// Parse a reference string and create a query to find the element
  /// Reference formats:
  /// - @id:submit-btn -> Find by identifier
  /// - @ref:button-2-toolbar -> Find by role + siblingIndex + parentRole
  /// - @pos:button-250-400 -> Find by role + grid position
  public static func parseReference(_ refString: String, application: String? = nil)
    -> ElementQuery?
  {
    // Remove @ prefix if present
    let ref = refString.hasPrefix("@") ? String(refString.dropFirst()) : refString

    // Split by :
    let parts = ref.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return nil }

    let type = String(parts[0])
    let value = String(parts[1])

    switch type {
    case "id":
      // Direct identifier lookup
      return ElementQuery(
        application: application,
        limit: 1,
        identifier: value
      )

    case "ref":
      // Structural: role-siblingIndex-parentRole
      let components = value.split(separator: "-")
      guard components.count == 3 else { return nil }

      let role = String(components[0])
      guard let siblingIndex = Int(components[1]) else { return nil }
      let parentRole = String(components[2])

      return ElementQuery(
        role: role,
        application: application,
        limit: 10,  // Get multiple, best match is first with matching siblingIndex
        siblingIndex: siblingIndex,
        parentRole: parentRole
      )

    case "pos":
      // Spatial: role-gridX-gridY
      let components = value.split(separator: "-")
      guard components.count == 3 else { return nil }

      let role = String(components[0])
      guard let gridX = Int(components[1]),
        let gridY = Int(components[2])
      else { return nil }

      // Search in area around grid point (±75px)
      return ElementQuery(
        role: role,
        application: application,
        limit: 20
          // Client will need to filter by proximity to (gridX, gridY)
      )

    default:
      return nil
    }
  }

  /// Resolve a reference to an element
  /// Tries the reference query, returns best match
  public static func resolve(_ refString: String, application: String? = nil) -> Element? {
    guard let query = parseReference(refString, application: application) else {
      return nil
    }

    let result = AccessibilityQuery.find(query)
    return result.elements.first
  }

  /// Check if a string is a reference (starts with @)
  public static func isReference(_ string: String) -> Bool {
    string.hasPrefix("@")
  }
}
