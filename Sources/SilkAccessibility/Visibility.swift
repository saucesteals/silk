// Visibility.swift - Spatial awareness types for viewport detection
// Phase 3, Layer 1: Enhanced Primitives
//
// These types are attached to Element results to give agents
// spatial awareness — can they see/interact with this element?

import ApplicationServices
import CoreGraphics

// MARK: - Core Types

/// Visibility status of an element relative to its viewport/scroll container.
public struct ElementVisibility: Sendable, Encodable {
  /// Whether the element is fully within the visible viewport
  public let inViewport: Bool
  /// Fraction of element area currently visible (0.0 to 1.0)
  public let percentVisible: Double
  /// What's blocking visibility, if anything
  public let reason: VisibilityReason
  /// How to scroll the element into view (nil if already visible)
  public let requiresScroll: ScrollDelta?

  enum CodingKeys: String, CodingKey {
    case inViewport = "in_viewport"
    case percentVisible = "percent_visible"
    case reason
    case requiresScroll = "requires_scroll"
  }

  public init(
    inViewport: Bool,
    percentVisible: Double,
    reason: VisibilityReason,
    requiresScroll: ScrollDelta?
  ) {
    self.inViewport = inViewport
    self.percentVisible = percentVisible
    self.reason = reason
    self.requiresScroll = requiresScroll
  }
}

/// Why an element isn't fully visible.
public enum VisibilityReason: String, Sendable, Encodable {
  case fullyVisible = "fully_visible"
  case partiallyVisible = "partially_visible"
  case belowViewport = "below_viewport"
  case aboveViewport = "above_viewport"
  case leftOfViewport = "left_of_viewport"
  case rightOfViewport = "right_of_viewport"
  case outsideWindow = "outside_window"
  case zeroSize = "zero_size"
  case noScrollContainer = "no_scroll_container"
  case unknown = "unknown"
}

/// How far and in what direction to scroll to make an element visible.
public struct ScrollDelta: Sendable, Encodable {
  /// Primary scroll direction needed
  public let direction: String
  /// Estimated pixels to scroll
  public let estimatedPixels: Int

  enum CodingKeys: String, CodingKey {
    case direction
    case estimatedPixels = "estimated_pixels"
  }

  public init(direction: String, estimatedPixels: Int) {
    self.direction = direction
    self.estimatedPixels = estimatedPixels
  }
}

/// Information about the nearest scrollable ancestor container.
public struct ScrollContainerInfo: Sendable, Encodable {
  /// Role of the scroll container (e.g. "AXScrollArea", "AXWebArea")
  public let role: String
  /// The visible frame of the scroll container (screen coordinates)
  public let visibleFrame: EncodableRect
  /// Total content size if available
  public let contentSize: EncodableSize?
  /// Current scroll position if available
  public let scrollPosition: EncodablePoint?
  /// Whether the container can scroll in each direction
  public let canScrollUp: Bool
  public let canScrollDown: Bool
  public let canScrollLeft: Bool
  public let canScrollRight: Bool

  enum CodingKeys: String, CodingKey {
    case role
    case visibleFrame = "visible_frame"
    case contentSize = "content_size"
    case scrollPosition = "scroll_position"
    case canScrollUp = "can_scroll_up"
    case canScrollDown = "can_scroll_down"
    case canScrollLeft = "can_scroll_left"
    case canScrollRight = "can_scroll_right"
  }

  public init(
    role: String,
    visibleFrame: CGRect,
    contentSize: CGSize?,
    scrollPosition: CGPoint?,
    canScrollUp: Bool,
    canScrollDown: Bool,
    canScrollLeft: Bool,
    canScrollRight: Bool
  ) {
    self.role = role
    self.visibleFrame = EncodableRect(rect: visibleFrame)
    self.contentSize = contentSize.map { EncodableSize(size: $0) }
    self.scrollPosition = scrollPosition.map { EncodablePoint(point: $0) }
    self.canScrollUp = canScrollUp
    self.canScrollDown = canScrollDown
    self.canScrollLeft = canScrollLeft
    self.canScrollRight = canScrollRight
  }
}

// MARK: - Encodable Geometry Wrappers

/// CGRect wrapper for clean JSON output
public struct EncodableRect: Sendable, Encodable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(rect: CGRect) {
    self.x = Double(rect.origin.x)
    self.y = Double(rect.origin.y)
    self.width = Double(rect.width)
    self.height = Double(rect.height)
  }
}

/// CGSize wrapper for clean JSON output
public struct EncodableSize: Sendable, Encodable {
  public let width: Double
  public let height: Double

  public init(size: CGSize) {
    self.width = Double(size.width)
    self.height = Double(size.height)
  }
}

/// CGPoint wrapper for clean JSON output
public struct EncodablePoint: Sendable, Encodable {
  public let x: Double
  public let y: Double

  public init(point: CGPoint) {
    self.x = Double(point.x)
    self.y = Double(point.y)
  }
}
