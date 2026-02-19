import CoreGraphics
import Foundation

/// Scroll direction
public enum ScrollDirection: String, Sendable, Codable {
  case up
  case down
  case left
  case right
}

/// Scroll target
public enum ScrollTarget: Sendable {
  case global  // Scroll wherever cursor is
  case point(CGPoint)  // Scroll at specific location
  case element(String, app: String?)  // Scroll in specific element
}

/// Scroll options
public struct ScrollOptions: Sendable {
  public let direction: ScrollDirection
  public let amount: Int  // Lines or pixels
  public let smooth: Bool  // Smooth scrolling vs instant
  public let target: ScrollTarget

  public init(
    direction: ScrollDirection,
    amount: Int,
    smooth: Bool = false,
    target: ScrollTarget = .global
  ) {
    self.direction = direction
    self.amount = amount
    self.smooth = smooth
    self.target = target
  }
}

/// Scroll result
public struct ScrollResult: Sendable, Encodable {
  public let direction: String
  public let amount: Int
  public let durationMs: Int
  public let smooth: Bool

  enum CodingKeys: String, CodingKey {
    case direction, amount
    case durationMs = "duration_ms"
    case smooth
  }

  public init(
    direction: String,
    amount: Int,
    durationMs: Int,
    smooth: Bool
  ) {
    self.direction = direction
    self.amount = amount
    self.durationMs = durationMs
    self.smooth = smooth
  }
}
