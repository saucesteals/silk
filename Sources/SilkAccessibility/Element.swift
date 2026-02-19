// Element.swift - Core accessibility element representation
// Wraps AXUIElement with extracted attributes for easy consumption

import ApplicationServices
import CoreGraphics

/// Represents a discovered UI element with its key attributes pre-extracted.
/// AXUIElement itself is a CFType (thread-safe, reference-counted) so we mark this Sendable.
public struct Element: @unchecked Sendable, Encodable {
  /// Display title (button label, window title, etc.)
  public let title: String?
  /// Accessibility description (fallback when title is nil)
  public let accessibilityDescription: String?
  /// Role identifier (e.g. "AXButton", "AXTextField", "AXStaticText")
  public let role: String
  /// Subrole for more specific identification (e.g. "AXCloseButton")
  public let subrole: String?
  /// Current value (text content, checkbox state, slider value)
  public let value: String?
  /// Screen position (top-left corner)
  public let position: CGPoint
  /// Element dimensions
  public let size: CGSize
  /// The underlying AXUIElement for performing actions or deeper queries
  public let axElement: AXUIElement
  /// UI hierarchy path from root (e.g. ["AXApplication", "AXWindow", "AXGroup", "AXButton"])
  public let path: [String]
  /// Depth in the tree (0 = root)
  public let depth: Int

  // MARK: - New Precision Attributes (Phase 1 Validation)

  /// Accessibility identifier (kAXIdentifierAttribute) - similar to DOM id
  public let identifier: String?
  /// Index among siblings with same parent (0-based)
  public let siblingIndex: Int?
  /// DOM identifier for web content (AXDOMIdentifier, browser-specific)
  public let domIdentifier: String?
  /// DOM class list for web content (AXDOMClassList, browser-specific)
  public let domClassList: [String]?
  /// Parent element role (for hierarchy queries) - we store role, not full Element to avoid circular refs
  public let parentRole: String?

  // MARK: - Phase 3: Spatial Awareness (optional, computed post-query)

  /// Visibility status relative to viewport/scroll container.
  /// Computed by ViewportDetection after element discovery.
  public var visibility: ElementVisibility?

  /// Information about the nearest scrollable ancestor container.
  /// Computed by ViewportDetection after element discovery.
  public var scrollContainer: ScrollContainerInfo?

  // MARK: - Stable Reference (for agent reuse)

  /// Generate a stable reference ID for this element
  /// Can be used later to re-find the element even if DOM changes
  public var referenceId: String {
    // Priority: identifier > structural > spatial
    if let id = identifier {
      return "id:\(id)"
    }

    if let sibIdx = siblingIndex, let parent = parentRole {
      // Keep proper case for role names (Button not button)
      let roleShort = role.replacingOccurrences(of: "AX", with: "")
      let parentShort = parent.replacingOccurrences(of: "AX", with: "")
      return "ref:\(roleShort)-\(sibIdx)-\(parentShort)"
    }

    // Fallback: role + grid-aligned position
    let gridX = Int(position.x / 50) * 50
    let gridY = Int(position.y / 50) * 50
    let roleShort = role.replacingOccurrences(of: "AX", with: "")
    return "pos:\(roleShort)-\(gridX)-\(gridY)"
  }

  /// Center point of the element — useful for click targeting
  public var center: CGPoint {
    CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
  }

  /// The best human-readable label: title, description, value, or role
  public var label: String {
    title ?? accessibilityDescription ?? value ?? role
  }

  /// Frame rectangle
  public var frame: CGRect {
    CGRect(origin: position, size: size)
  }

  // MARK: - Codable

  enum CodingKeys: String, CodingKey {
    case title
    case accessibilityDescription = "accessibility_description"
    case role, subrole, value, position, size, path, depth
    case identifier
    case siblingIndex = "sibling_index"
    case domIdentifier = "dom_identifier"
    case domClassList = "dom_class_list"
    case parentRole = "parent_role"
    case ref
    case visibility
    case scrollContainer = "scroll_container"
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(title, forKey: .title)
    try container.encodeIfPresent(accessibilityDescription, forKey: .accessibilityDescription)
    try container.encode(role, forKey: .role)
    try container.encodeIfPresent(subrole, forKey: .subrole)
    try container.encodeIfPresent(value, forKey: .value)
    try container.encode(["x": position.x, "y": position.y], forKey: .position)
    try container.encode(["width": size.width, "height": size.height], forKey: .size)
    try container.encode(path, forKey: .path)
    try container.encode(depth, forKey: .depth)
    try container.encodeIfPresent(identifier, forKey: .identifier)
    try container.encodeIfPresent(siblingIndex, forKey: .siblingIndex)
    try container.encodeIfPresent(domIdentifier, forKey: .domIdentifier)
    try container.encodeIfPresent(domClassList, forKey: .domClassList)
    try container.encodeIfPresent(parentRole, forKey: .parentRole)
    try container.encode(referenceId, forKey: .ref)  // Include stable reference
    try container.encodeIfPresent(visibility, forKey: .visibility)
    try container.encodeIfPresent(scrollContainer, forKey: .scrollContainer)
  }
}

// MARK: - AXUIElement Attribute Helpers

/// Errors from accessibility operations
public enum AccessibilityError: Error, Sendable {
  case notTrusted
  case invalidElement
  case attributeUnsupported(String)
  case apiError(AXError)
  case applicationNotFound(String)
  case timeout
}

/// Extract a typed attribute from an AXUIElement.
/// This is the fundamental building block for all attribute access.
@inline(__always)
func axAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
  var value: AnyObject?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success else { return nil }
  return value as? T
}

/// Extract CGPoint from an AXValue attribute (position).
func axPoint(_ element: AXUIElement, _ attribute: String = kAXPositionAttribute as String)
  -> CGPoint?
{
  var value: AnyObject?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success, let axVal = value else { return nil }
  var point = CGPoint.zero
  guard AXValueGetValue(axVal as! AXValue, .cgPoint, &point) else { return nil }
  return point
}

/// Extract CGSize from an AXValue attribute (size).
func axSize(_ element: AXUIElement, _ attribute: String = kAXSizeAttribute as String) -> CGSize? {
  var value: AnyObject?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success, let axVal = value else { return nil }
  var size = CGSize.zero
  guard AXValueGetValue(axVal as! AXValue, .cgSize, &size) else { return nil }
  return size
}

/// Batch-fetch multiple attributes at once using AXUIElementCopyMultipleAttributeValues.
/// NOTE: Currently unused - batch fetching was failing so we use individual attribute queries.
/// Kept for reference in case we want to optimize later.
func axBatchAttributes(_ element: AXUIElement, _ attributes: [String]) -> [String: AnyObject] {
  let cfAttributes = attributes as CFArray
  var values: CFArray?
  let result = AXUIElementCopyMultipleAttributeValues(element, cfAttributes, .stopOnError, &values)

  guard result == .success, let cfValues = values else {
    return [:]
  }

  let arr = cfValues as [AnyObject]
  var dict: [String: AnyObject] = [:]
  for (i, attr) in attributes.enumerated() where i < arr.count {
    let val = arr[i]
    // AXUIElementCopyMultipleAttributeValues returns AXValueGetTypeError for missing attrs
    if !(val is NSError) {
      dict[attr] = val
    }
  }
  return dict
}

/// Build an Element from an AXUIElement by fetching common attributes individually.
/// This is the primary factory — used by tree traversal.
/// - Parameters:
///   - ax: The AXUIElement to wrap
///   - path: Hierarchy path from root
///   - depth: Depth in tree (0 = root)
///   - siblingIndex: Optional index among siblings (0-based)
/// - Returns: Populated Element or nil if required attributes are missing
func buildElement(from ax: AXUIElement, path: [String], depth: Int, siblingIndex: Int? = nil)
  -> Element?
{
  // Get role first (required)
  guard let role: String = axAttribute(ax, kAXRoleAttribute as String) else {
    return nil
  }

  // Get standard attributes individually
  let title: String? = axAttribute(ax, kAXTitleAttribute as String)
  let description: String? = axAttribute(ax, kAXDescriptionAttribute as String)
  let subrole: String? = axAttribute(ax, kAXSubroleAttribute as String)
  let position = axPoint(ax) ?? .zero
  let size = axSize(ax) ?? .zero

  // Value can be many types
  let rawValue: AnyObject? = axAttribute(ax, kAXValueAttribute as String)
  let value = rawValue.map { "\($0)" }

  // MARK: Phase 1 Validation - New Precision Attributes

  // Identifier (standard attribute, like DOM id)
  let identifier: String? = axAttribute(ax, kAXIdentifierAttribute as String)

  // Parent role (for hierarchy queries, avoid circular refs by storing only role)
  let parentRole: String? = {
    guard let parent: AXUIElement = axAttribute(ax, kAXParentAttribute as String) else {
      return nil
    }
    return axAttribute(parent, kAXRoleAttribute as String)
  }()

  // DOM-specific attributes (undocumented, browser-only)
  let domIdentifier: String? = axAttribute(ax, "AXDOMIdentifier")
  let domClassList: [String]? = {
    if let classList: String = axAttribute(ax, "AXDOMClassList") {
      return classList.split(separator: " ").map(String.init)
    }
    return nil
  }()

  return Element(
    title: title,
    accessibilityDescription: description,
    role: role,
    subrole: subrole,
    value: value,
    position: position,
    size: size,
    axElement: ax,
    path: path + [role],
    depth: depth,
    identifier: identifier,
    siblingIndex: siblingIndex,
    domIdentifier: domIdentifier,
    domClassList: domClassList,
    parentRole: parentRole,
    visibility: nil,
    scrollContainer: nil
  )
}
