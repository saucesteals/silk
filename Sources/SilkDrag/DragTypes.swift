import CoreGraphics
import Foundation
import SilkCore

/// Drag operation options
public struct DragOptions: Sendable {
  public let from: CGPoint
  public let to: CGPoint
  public let button: MouseButton
  public let humanize: Bool
  public let duration: TimeInterval?  // Manual duration override

  public init(
    from: CGPoint,
    to: CGPoint,
    button: MouseButton = .left,
    humanize: Bool = false,
    duration: TimeInterval? = nil
  ) {
    self.from = from
    self.to = to
    self.button = button
    self.humanize = humanize
    self.duration = duration
  }
}

/// Drag operation result
public struct DragResult: Sendable, Encodable {
  public let fromX: Double
  public let fromY: Double
  public let toX: Double
  public let toY: Double
  public let distance: Double
  public let durationMs: Int
  public let humanized: Bool

  enum CodingKeys: String, CodingKey {
    case fromX = "from_x"
    case fromY = "from_y"
    case toX = "to_x"
    case toY = "to_y"
    case distance
    case durationMs = "duration_ms"
    case humanized
  }

  public init(
    fromX: Double,
    fromY: Double,
    toX: Double,
    toY: Double,
    distance: Double,
    durationMs: Int,
    humanized: Bool
  ) {
    self.fromX = fromX
    self.fromY = fromY
    self.toX = toX
    self.toY = toY
    self.distance = distance
    self.durationMs = durationMs
    self.humanized = humanized
  }
}
