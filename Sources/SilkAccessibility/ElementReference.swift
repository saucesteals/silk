// ElementReference.swift - Stable references to UI elements
// Generates smart IDs that work even when DOM changes

import CoreGraphics
import Foundation

/// A stable reference to a UI element with fallback resolution
public struct ElementReference: Codable, Sendable {
  /// Primary identifier (from kAXIdentifierAttribute if available)
  public let identifier: String?

  /// Role + sibling index + parent role (structural reference)
  public let structuralId: String?

  /// Role + approximate position (spatial reference, less stable)
  public let spatialId: String?

  /// XPath-like accessibility path (last resort)
  public let path: String?

  /// Human-readable reference (for debugging)
  public let displayName: String

  /// Generate a reference from an Element
  public init(from element: Element) {
    self.identifier = element.identifier

    // Structural ID: role + siblingIndex + parentRole
    if let siblingIndex = element.siblingIndex, let parentRole = element.parentRole {
      self.structuralId = "\(element.role.lowercased())-\(siblingIndex)-\(parentRole.lowercased())"
    } else {
      self.structuralId = nil
    }

    // Spatial ID: role + rounded position (grid-aligned to tolerate small shifts)
    let gridX = Int(element.position.x / 50) * 50  // 50px grid
    let gridY = Int(element.position.y / 50) * 50
    self.spatialId = "\(element.role.lowercased())-\(gridX)-\(gridY)"

    // Path: XPath-like accessibility tree path
    self.path = element.path.enumerated().map { index, role in
      // Count siblings of same role to get index
      // For now, simplified - just use role names
      role.lowercased()
    }.joined(separator: "/")

    // Display name: title or role
    self.displayName = element.title ?? element.role
  }

  /// Get the best available ID (priority order)
  public var bestId: String {
    if let id = identifier { return "id:\(id)" }
    if let structural = structuralId { return "struct:\(structural)" }
    if let spatial = spatialId { return "spatial:\(spatial)" }
    return "path:\(path ?? "unknown")"
  }

  /// Try to resolve this reference back to an element
  /// Returns a query that should find the element
  public func toQuery(application: String? = nil) -> [ElementQuery] {
    var queries: [ElementQuery] = []

    // Try 1: By identifier (most stable)
    if let id = identifier {
      queries.append(
        ElementQuery(
          application: application,
          limit: 1,
          identifier: id
        ))
    }

    // Try 2: By structural position (role + sibling + parent)
    if let structural = structuralId {
      let parts = structural.split(separator: "-")
      if parts.count == 3 {
        let role = String(parts[0])
        let siblingIndex = Int(parts[1])
        let parentRole = String(parts[2])

        queries.append(
          ElementQuery(
            role: role,
            application: application,
            limit: 10,  // Get multiple, filter by sibling index
            siblingIndex: siblingIndex,
            parentRole: parentRole
          ))
      }
    }

    // Try 3: By spatial position (role + approximate location)
    if let spatial = spatialId {
      let parts = spatial.split(separator: "-")
      if parts.count == 3 {
        let role = String(parts[0])
        let x = Int(parts[1]) ?? 0
        let y = Int(parts[2]) ?? 0

        // Search in 100px radius around grid point
        queries.append(
          ElementQuery(
            role: role,
            application: application,
            limit: 20
              // Note: Would need to add spatial filter here
              // For now, client filters by proximity
          ))
      }
    }

    return queries
  }
}

/// Extension to Element for generating references
extension Element {
  /// Generate a stable reference to this element
  public func toReference() -> ElementReference {
    ElementReference(from: self)
  }
}
