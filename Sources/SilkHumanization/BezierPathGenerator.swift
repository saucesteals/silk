import CoreGraphics
import Foundation

/// Generates cubic Bezier curve paths for natural-looking mouse movement
public struct BezierPathGenerator: Sendable {

  /// Generate a cubic Bezier curve from start to end with randomized control points
  /// - Parameters:
  ///   - start: Starting point (P0)
  ///   - end: Ending point (P3)
  ///   - randomness: Control point randomization factor (0.0-1.0, default 0.3)
  ///   - steps: Number of interpolation points (default 50)
  /// - Returns: Array of CGPoint interpolated along the curve
  public static func generatePath(
    from start: CGPoint,
    to end: CGPoint,
    randomness: CGFloat = 0.3,
    steps: Int = 50
  ) -> [CGPoint] {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let distance = hypot(dx, dy)

    // For very short distances, just return start and end
    if distance < 2.0 {
      return [start, end]
    }

    // Perpendicular direction for control point offset
    let perpX = -dy / distance
    let perpY = dx / distance

    // Randomized control points offset perpendicular to the direct line
    let maxOffset = distance * randomness

    let cp1Offset = CGFloat.random(in: -maxOffset...maxOffset)
    let cp1Along = CGFloat.random(in: 0.2...0.4)
    let p1 = CGPoint(
      x: start.x + dx * cp1Along + perpX * cp1Offset,
      y: start.y + dy * cp1Along + perpY * cp1Offset
    )

    let cp2Offset = CGFloat.random(in: -maxOffset...maxOffset)
    let cp2Along = CGFloat.random(in: 0.6...0.8)
    let p2 = CGPoint(
      x: start.x + dx * cp2Along + perpX * cp2Offset,
      y: start.y + dy * cp2Along + perpY * cp2Offset
    )

    // Evaluate cubic Bezier: B(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
    var points: [CGPoint] = []
    points.reserveCapacity(steps + 1)

    for i in 0...steps {
      let t = CGFloat(i) / CGFloat(steps)
      let u = 1.0 - t

      let x =
        u * u * u * start.x
        + 3.0 * u * u * t * p1.x
        + 3.0 * u * t * t * p2.x
        + t * t * t * end.x

      let y =
        u * u * u * start.y
        + 3.0 * u * u * t * p1.y
        + 3.0 * u * t * t * p2.y
        + t * t * t * end.y

      points.append(CGPoint(x: x, y: y))
    }

    return points
  }
}
