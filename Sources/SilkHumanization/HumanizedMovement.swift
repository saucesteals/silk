import CoreGraphics
import Foundation

/// Combines Bezier path generation with Fitts's Law timing for realistic mouse movement
public struct HumanizedMovement: Sendable {

  /// A single step in a humanized movement: position + delay before next step
  public struct Step: Sendable {
    public let point: CGPoint
    public let delay: TimeInterval
  }

  /// Generate a complete humanized movement from start to end
  /// - Parameters:
  ///   - start: Starting position
  ///   - end: Target position
  ///   - targetSize: Size of target for Fitts's Law calculation (default 10)
  /// - Returns: Array of movement steps with positions and delays
  public static func generateMovement(
    from start: CGPoint,
    to end: CGPoint,
    targetSize: CGFloat = 10.0
  ) -> [Step] {
    let distance = hypot(end.x - start.x, end.y - start.y)

    // Very short distance: just move directly
    if distance < 3.0 {
      return [Step(point: end, delay: 0.01)]
    }

    // Scale steps with distance (more steps = smoother for longer moves)
    let steps = max(20, min(80, Int(distance / 8.0)))

    // Generate Bezier path
    var points = BezierPathGenerator.generatePath(
      from: start,
      to: end,
      randomness: 0.3,
      steps: steps
    )

    // Add micro-corrections near the end (overshoot + correction)
    addMicroCorrections(to: &points, target: end)

    // Calculate total movement time via Fitts's Law
    let totalTime = FittsLawCalculator.movementTime(
      distance: distance,
      targetWidth: targetSize
    )

    // Distribute time non-linearly across steps
    let delays = distributeTime(totalTime: totalTime, stepCount: points.count)

    // Combine into steps (skip the first point since we're already there)
    var result: [Step] = []
    result.reserveCapacity(points.count - 1)

    for i in 1..<points.count {
      result.append(Step(point: points[i], delay: delays[i - 1]))
    }

    return result
  }

  /// Add micro-corrections near the target (slight overshoot then correction)
  private static func addMicroCorrections(to points: inout [CGPoint], target: CGPoint) {
    guard points.count >= 4 else { return }

    // ~20% chance of a visible overshoot for realism
    guard Double.random(in: 0...1) < 0.2 else { return }

    let overshootAmount = CGFloat.random(in: 2.0...6.0)
    let lastIdx = points.count - 1
    let secondLast = points[lastIdx - 1]

    // Direction of approach
    let dx = target.x - secondLast.x
    let dy = target.y - secondLast.y
    let d = hypot(dx, dy)
    guard d > 0.1 else { return }

    // Overshoot point: go past the target slightly
    let overshoot = CGPoint(
      x: target.x + (dx / d) * overshootAmount,
      y: target.y + (dy / d) * overshootAmount
    )

    // Replace last point with overshoot, then add correction back to target
    points[lastIdx] = overshoot
    points.append(target)
  }

  /// Distribute total time non-linearly: slower at start and end, faster in middle
  /// Uses a sine-based easing curve
  private static func distributeTime(totalTime: TimeInterval, stepCount: Int) -> [TimeInterval] {
    guard stepCount > 1 else { return [totalTime] }

    // Generate raw weights using sine easing (slow-fast-slow)
    var weights: [Double] = []
    weights.reserveCapacity(stepCount)

    for i in 0..<stepCount {
      let t = Double(i) / Double(stepCount - 1)
      // Bell curve via sin: peaks at t=0.5, low at t=0 and t=1
      // Add a floor so endpoints aren't infinitely slow
      let w = 0.3 + sin(t * .pi)
      weights.append(w)
    }

    let totalWeight = weights.reduce(0, +)

    return weights.map { w in
      totalTime * (w / totalWeight)
    }
  }
}
